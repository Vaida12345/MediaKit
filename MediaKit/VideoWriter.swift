//
//  VideoWriter.swift
//
//
//  Created by Vaida on 11/23/24.
//

import AVFoundation
import Foundation
import Synchronization
import FinderItem
import Essentials
import Accelerate


/// A video writer for writing a stream of images.
///
/// - Experiment: It is best not to have writers run in parallel.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, *)
public final class VideoWriter: @unchecked Sendable {

    private let assetWriter: AVAssetWriter

    private let assetWriterVideoInput: AVAssetWriterInput

    private let size: CGSize

    private let destination: FinderItem

    private let frameRate: Int

    private let queue = DispatchQueue(label: "package.MediaKit.VideoWriter.mediaQueue")
    
    private static var hasShownConvertWarning: Bool = false


    /// Copies or converts a CGImage into a CVPixelBuffer in BGRA8, premultiplied-alpha.
    /// Checks if the CGImage matches the desired format; if so, uses memcpy.
    /// Otherwise, uses vImage for color/format conversion.
    ///
    /// - Parameters:
    ///   - source:       The source CGImage.
    ///   - pixelBuffer:  The target CVPixelBuffer (already allocated).
    ///   - colorSpace:   The color space that you want in the pixel buffer.
    ///
    nonisolated
    private static func copyOrConvertCGImage(
        _ source: CGImage,
        to pixelBuffer: CVPixelBuffer,
        colorSpace: CGColorSpace
    ) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])

        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }

        guard let destBaseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw WriteError.pixelBufferBaseAddressNil
        }

        let destBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Fast path when source pixels already match destination layout.
        if source.bitsPerComponent == 8,
           source.bitsPerPixel == 32,
           source.bitmapInfo.alpha == .premultipliedFirst,
           source.bitmapInfo.byteOrder == .order32Little,
           source.bytesPerRow == destBytesPerRow,
            let data = source.dataProvider?.data {

            let srcLength = CFDataGetLength(data)
            let expectedLength = destBytesPerRow * height
            if srcLength >= expectedLength {
                memcpy(destBaseAddress, CFDataGetBytePtr(data), expectedLength)
                return
            }
        }

        // convert image
        if !VideoWriter.hasShownConvertWarning {
            let logger = Logger(subsystem: "MediaKit", category: "VideoWriter")
            logger.warning("VideoWriter is converting input CGImage to BGRA8, premultiplied-alpha. This is extra work, you can avoid this by setting input to correct format.")
            VideoWriter.hasShownConvertWarning = true
        }
        
        var srcFormat = vImage_CGImageFormat(cgImage: source)!
        let dstFormat = vImageCVImageFormat.make(format: .format32BGRA, colorSpace: colorSpace, alphaIsOpaqueHint: false)!

        var srcBuffer = vImage_Buffer()
        defer {
            free(srcBuffer.data)
        }

        let initError = vImageBuffer_InitWithCGImage(
            &srcBuffer,
            &srcFormat,
            nil,
            source,
            vImage_Flags(kvImageNoFlags)
        )
        guard initError == kvImageNoError else { throw vImage.Error(vImageError: initError) }

        var dstBuffer = vImage_Buffer(
            data: destBaseAddress,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: destBytesPerRow
        )

        var converterError: Int = 0
        guard let converter = vImageConverter_CreateForCGToCVImageFormat(
            &srcFormat,
            dstFormat,
            nil,
            vImage_Flags(kvImagePrintDiagnosticsToConsole),
            &converterError
        ) else {
            throw vImage.Error(vImageError: converterError)
        }

        let convertError = vImageConvert_AnyToAny(
            converter.takeRetainedValue(),
            &srcBuffer,
            &dstBuffer,
            nil,
            vImage_Flags(kvImageNoFlags)
        )
        guard convertError == kvImageNoError else { throw vImage.Error(vImageError: convertError) }
    }

    /// Starts writing to destination.
    ///
    /// - Parameters:
    ///   - yield: The yield function, see discussion for more information.
    ///
    /// Parameters for `yield`:
    /// - term index: The index of the frame.
    /// - term returns: An image at the given index, or `nil`, indicating the end of video.
    ///
    /// To cancel the video writer, cancel the parent task. The cancellation will be propagated to `yield`. No new calls will be made after cancelation.
    ///
    /// Returns after the video is finalized.
    ///
    /// - Precondition: The images produced from `yield` must match the `size` when initializing the writer.
    ///
    /// > Tip:
    /// > The native video frame buffer format is:
    /// > ```
    /// > CGImageAlphaInfo.premultipliedFirst | CGBitmapInfo.byteOrder32Little
    /// > ```
    /// > with `bitsPerComponent = 8`, and `bitsPerPixel = 32`
    /// >
    /// > If the frames provided are also in this format, `VideoWriter` won't need to convert between formats and can directly use the internal storage of these frames, significantly improving rendering performance.
    public consuming func startWriting(yield: @escaping @Sendable (_ index: Int) async throws -> CGImage?) async throws {
        if #available(iOS 26.0, macOS 26.0, visionOS 26, *) {
            return try await self.startWriting_post26(yield: yield)
        } else {
            return try await self.startWriting_pre26(yield: yield)
        }
    }
    
    
    /// Writes frames using AVFoundation's iOS 26+ async pixel-buffer receiver API.
    ///
    /// The method keeps at most one frame-generation task in flight to overlap frame production
    /// with encoding while avoiding unbounded memory growth.
    ///
    /// - Parameter yield: Produces the frame at the given index, or `nil` to end the stream.
    @available(iOS 26.0, macOS 26.0, visionOS 26, *)
    private func startWriting_post26(yield: @escaping @Sendable (_ index: Int) async throws -> CGImage?) async throws {
        nonisolated(unsafe) let writer = assetWriter
        guard writer.status == .unknown else { throw WriteError.invalidAssetWriterState(writer.status.rawValue) }

        let attributes = CVPixelBufferCreationAttributes(
            pixelFormatType: .init(rawValue: kCVPixelFormatType_32BGRA),
            size: CVImageSize(size)
        )
        let inputReceiver = writer.inputPixelBufferReceiver(for: assetWriterVideoInput, pixelBufferAttributes: attributes)

        try writer.start()
        writer.startSession(atSourceTime: .zero)

        guard let pixelBufferPool = inputReceiver.pixelBufferPool else { throw WriteError.pixelBufferPoolNil }

        let defaultColorSpace = CGColorSpaceCreateDeviceRGB()
        let timescale = CMTimeScale(frameRate)

        do {
            var frameIndex = 0

            try await withThrowingTaskGroup(of: CGImage?.self) { taskGroup in
                taskGroup.addTask {
                    try await yield(0)
                }

                while let nextFrame = try await taskGroup.next() {
                    guard let frame = nextFrame else { break }

                    let currIndex = frameIndex
                    frameIndex += 1
                    
                    // dispatch next frame
                    try Task.checkCancellation() // we put check cancellation here based on the assumption that generating frame is the heaviest stack.
                    taskGroup.addTask {
                        try await yield(currIndex + 1)
                    }

                    let presentationTime = CMTime(value: CMTimeValue(currIndex), timescale: timescale)

                    let mutablePixelBuffer = try pixelBufferPool.makeMutablePixelBuffer()
                    try mutablePixelBuffer.withUnsafeBuffer { pixelBuffer in
                        try VideoWriter.copyOrConvertCGImage(frame, to: pixelBuffer, colorSpace: defaultColorSpace)
                    }

                    try await inputReceiver.append(.init(mutablePixelBuffer), with: presentationTime)
                }
            }

            inputReceiver.finish()
            await writer.finishWriting()

            if let error = writer.error {
                throw error
            }
        } catch {
            writer.cancelWriting()
            throw error
        }
    }
    
    private func startWriting_pre26(yield: @escaping @Sendable (_ index: Int) async throws -> CGImage?) async throws {
        nonisolated(unsafe) let writer = assetWriter
        guard writer.status == .unknown else { throw WriteError.invalidAssetWriterState(writer.status.rawValue) }
        
        writer.add(assetWriterVideoInput)
        
        let sourceBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height
        ]
        
        nonisolated(unsafe)
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterVideoInput, sourcePixelBufferAttributes: sourceBufferAttributes)
        
        guard writer.startWriting() else {
            throw writer.error ?? WriteError.failedToStartWriting(writer.status.rawValue)
        }
        writer.startSession(atSourceTime: .zero)
        
        guard let _pixelBufferPool = pixelBufferAdaptor.pixelBufferPool else { throw WriteError.pixelBufferPoolNil }
        nonisolated(unsafe) let pixelBufferPool = _pixelBufferPool
        
        let defaultColorSpace = CGColorSpaceCreateDeviceRGB()
        
        nonisolated(unsafe)
        var nextFrameTask: Task<CGImage?, any Error>? = nil
        
        let counter = Atomic<Int>(0)
        let videoState = Mutex<VideoState>(.rendering)
        let frameRate = frameRate
        
        @Sendable func dispatchNextFrame(index: Int) -> Task<CGImage?, any Error>? {
            Task.detached {
                try await yield(index)
            }
        }
        nextFrameTask = dispatchNextFrame(index: 0)
        
        try await withTaskCancellationHandler {
            let _: Void = await withCheckedContinuation { continuation in
                assetWriterVideoInput.requestMediaDataWhenReady(on: self.queue) { [weak self] in
                    guard videoState.withLock({ $0 == .rendering }) else { return }
                    
                    while (self?.assetWriterVideoInput.isReadyForMoreMediaData ?? false) && videoState.withLock({ $0 == .rendering }) {
                        print("request next")
                        
                        let semaphore = DispatchSemaphore(value: 0)
                        // semaphore runs on media queue, ensures it waits for task to complete. otherwise it would keep requesting medias.
                        Task { @Sendable in
                            defer { semaphore.signal() }
                            
                            let index = counter.add(1, ordering: .sequentiallyConsistent).oldValue
                            let presentationTime = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(frameRate))
                            
                            do {
                                guard videoState.withLock({ $0 == .rendering }) else {
                                    nextFrameTask?.cancel()
                                    return
                                }
                                
                                guard let frame = try await nextFrameTask?.value else {
                                    videoState.withLock { state in
                                        if state == .rendering {
                                            state = .willFinish
                                        }
                                    }
                                    return
                                }
                                
                                guard videoState.withLock({ $0 == .rendering }) else {
                                    nextFrameTask?.cancel()
                                    return
                                }
                                nextFrameTask = dispatchNextFrame(index: index + 1)
                                
                                // prepare buffer
                                var pixelBuffer: CVPixelBuffer? = nil
                                let pixelBufferCreationStatus = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBuffer)
                                guard pixelBufferCreationStatus == kCVReturnSuccess, let pixelBuffer else {
                                    throw WriteError.failedToCreatePixelBuffer(pixelBufferCreationStatus)
                                }
                                
                                try VideoWriter.copyOrConvertCGImage(frame, to: pixelBuffer, colorSpace: defaultColorSpace)
                                guard pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                                    throw writer.error ?? WriteError.failedToAppendFrame(index)
                                }
                            } catch {
                                videoState.withLock { state in
                                    if state == .rendering {
                                        state = .errored(error as NSError)
                                    }
                                }
                            }
                        }
                        semaphore.wait()
                        
                        print("render complete")
                    }
                    
                    print("no longer rendering")
                    
                    videoState.withLock { state in
                        print("video state is \(state)")
                        
                        switch state {
                        case .rendering:
                            break
                        case .willCancel:
                            self?.assetWriterVideoInput.markAsFinished()
                            continuation.resume()
                            state = .didCancel(nil)
                        case .errored(let error):
                            self?.assetWriterVideoInput.markAsFinished()
                            continuation.resume()
                            state = .didCancel(error)
                        case .didCancel:
                            break
                        case .willFinish:
                            self?.assetWriterVideoInput.markAsFinished()
                            continuation.resume()
                            state = .didFinish
                        case .didFinish:
                            break
                        }
                    }
                }
            } // end withCheckedThrowingContinuation
            
            print("end video")
            
            guard videoState.withLock({ $0.isFinished }) else {
                writer.cancelWriting()
                
                return try videoState.withLock { state in
                    switch state {
                    case .rendering, .willCancel, .errored, .willFinish, .didFinish:
                        fatalError()
                    case .didCancel(let error):
                        if let error {
                            throw error
                        }
                    }
                }
            }
            
            self.queue.sync { }
            await writer.finishWriting()
            
            if let error = writer.error {
                throw error
            }
        } onCancel: {
            videoState.withLock { $0 = .willCancel }
            nextFrameTask?.cancel()
            nextFrameTask = nil
        }
    }


    private enum VideoState: Equatable {
        case rendering
        case willCancel
        case errored(NSError)
        case didCancel(NSError?)
        case willFinish
        case didFinish

        var isFinished: Bool {
            switch self {
            case .willFinish, .didFinish: true
            default: false
            }
        }
    }


    /// Creates a video writer.
    ///
    /// Transparency is only recorded when codec is `ProRess4444`.
    ///
    /// - Parameters:
    ///   - size: The resulting video size.
    ///   - frameRate: The resulting video frame rate.
    ///   - destination: The resulting video location.
    ///   - container: The file format.
    ///   - codec: The codec used.
    public init(size: CGSize, frameRate: Int, to destination: FinderItem, container: AVFileType = .mov, codec: AVVideoCodecType = .hevc) throws {
        guard frameRate > 0 else { throw WriteError.invalidFrameRate(frameRate) }
        if codec == .hevc {
            guard size.width <= 8192 && size.height <= 4320 else { throw WriteError.videoSizeTooLarge(size) }
        }

        self.size = size
        self.frameRate = frameRate
        self.destination = destination

        let videoWidth = size.width
        let videoHeight = size.height

        try destination.removeIfExists()

        self.assetWriter = try AVAssetWriter(outputURL: destination.url, fileType: container)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight
        ]

        self.assetWriterVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    }


    public enum WriteError: GenericError, Equatable {

        case pixelBufferPoolNil
        case pixelBufferBaseAddressNil
        case failedToCreatePixelBuffer(CVReturn)
        case failedToAppendFrame(Int)
        case failedToStartWriting(Int)
        case invalidAssetWriterState(Int)
        case invalidFrameRate(Int)
        case videoSizeTooLarge(CGSize)

        public var message: String {
            switch self {
            case .pixelBufferPoolNil:
                "Pixel buffer pool is nil after starting writing session, this typically means you do not have permission to write to the given file, or a file with the same name already exists."
            case .pixelBufferBaseAddressNil:
                "Failed to access the pixel buffer base address."
            case .failedToCreatePixelBuffer(let status):
                "Failed to create a pixel buffer from the pool. Status: \(status)."
            case .failedToAppendFrame(let index):
                "Failed to append frame at index \(index) to the asset writer input."
            case .failedToStartWriting(let status):
                "AVAssetWriter failed to start writing. Status: \(status)."
            case .invalidAssetWriterState(let state):
                "VideoWriter is in an invalid state for startWriting. AVAssetWriter status: \(state)."
            case .invalidFrameRate(let frameRate):
                "Frame rate must be greater than zero. Received \(frameRate)."
            case .videoSizeTooLarge(let size):
                "HEVC codec supports the resolutions up to 8192×4320, the given size, \(Int(size.width))×\(Int(size.height)), is too large"
            }
        }

    }

}
