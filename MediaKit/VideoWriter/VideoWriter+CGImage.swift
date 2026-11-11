//
//  VideoWriter+CGImage.swift
//  MediaKit
//
//  Created by Vaida on 2026-11-11.
//

import Accelerate
import AVFoundation
import Synchronization


extension VideoWriter {
    
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
    /// > with `bitsPerComponent = 8`, `bitsPerPixel = 32`, and `sRGB`-compatible.
    /// >
    /// > If the frames provided are also in this format, `VideoWriter` won't need to convert between formats and can directly use the internal storage of these frames, significantly improving rendering performance.
    public consuming func startWriting(yield: @escaping (_ index: Int) async throws -> sending CGImage?) async throws {
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
    ///
    /// Not private, so that tests can run both write paths on any system.
    @available(iOS 26.0, macOS 26.0, visionOS 26, *)
    func startWriting_post26(yield: @escaping (_ index: Int) async throws -> sending CGImage?) async throws {
        nonisolated(unsafe) let writer = assetWriter
        guard writer.status == .unknown else { throw WriteError.invalidAssetWriterState(writer.status.rawValue) }
        
        let attributes = CVPixelBufferCreationAttributes(
            pixelFormatType: .init(rawValue: kCVPixelFormatType_32BGRA),
            size: CVImageSize(size)
        )
        let inputReceiver = writer.inputPixelBufferReceiver(for: assetWriterVideoInput, pixelBufferAttributes: attributes)
        
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        
        guard let pixelBufferPool = inputReceiver.pixelBufferPool else { writer.cancelWriting(); throw WriteError.pixelBufferPoolNil }
        
        let defaultColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
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
    
    /// Writes frames using `requestMediaDataWhenReady`, for systems earlier than iOS 26, macOS 26, and visionOS 26.
    ///
    /// Not private, so that tests can run both write paths on any system.
    func startWriting_pre26(yield: @escaping (_ index: Int) async throws -> sending CGImage?) async throws {
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
        
        guard let _pixelBufferPool = pixelBufferAdaptor.pixelBufferPool else { writer.cancelWriting(); throw WriteError.pixelBufferPoolNil }
        nonisolated(unsafe) let pixelBufferPool = _pixelBufferPool
        
        let defaultColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        
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
                    while (self?.assetWriterVideoInput.isReadyForMoreMediaData ?? false) && videoState.withLock({ $0 == .rendering }) {
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
                    }
                    
                    videoState.withLock { state in
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
            
            guard videoState.withLock({ $0.isFinished }) else {
                writer.cancelWriting()
                
                return try videoState.withLock { state -> Void in
                    switch state {
                    case .rendering, .willCancel, .errored, .willFinish, .didFinish:
                        fatalError()
                    case .didCancel(let error):
                        throw error ?? CancellationError()
                    }
                }
            }
            
            self.queue.sync { }
            await writer.finishWriting()
            
            if let error = writer.error {
                throw error
            }
        } onCancel: {
            videoState.withLock { if $0 == .rendering { $0 = .willCancel } }
            nextFrameTask?.cancel()
            nextFrameTask = nil
        }
        
        
        enum VideoState: Equatable {
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
    }
    
}


extension VideoWriter {
    
    /// Whether bytes in this color space can be copied into the sRGB output as they are. Device RGB counts, because the converter below treats it as sRGB too.
    private static func isSRGB(_ colorSpace: CGColorSpace?) -> Bool {
        guard let colorSpace else { return false }
        return colorSpace.name == CGColorSpace.sRGB || CFEqual(colorSpace, CGColorSpaceCreateDeviceRGB())
    }
    
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
           VideoWriter.isSRGB(source.colorSpace),
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
            let logger = Logger(subsystem: "dev.vaida.mediakit", category: "VideoWriter")
            logger.warning("VideoWriter is converting input CGImage to BGRA8, premultiplied-alpha. This is extra work, you can avoid this by setting input to correct format.")
            VideoWriter.hasShownConvertWarning = true
        }
        
        var srcFormat = vImage_CGImageFormat(cgImage: source)!
        var dstFormat = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            renderingIntent: .defaultIntent
        )!
        
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
        guard let converter = vImageConverter_CreateWithCGImageFormat(
            &srcFormat,
            &dstFormat,
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
}
