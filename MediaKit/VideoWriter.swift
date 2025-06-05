//
//  VideoWriter.swift
//
//
//  Created by Vaida on 11/23/24.
//

import AVFoundation
import Foundation
import Metal
import MetalKit
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
        // 2. Lock the base address before modifying.
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }
        
        let destBaseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)!
        
        let destBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let width  = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // 3. If the CGImage is already in 8-bit BGRA premultiplied-first, little-endian,
        //    and matches the row bytes, we can just do a raw copy.
        if  source.bitsPerComponent == 8,
            source.bitsPerPixel == 32,
            source.bitmapInfo.rawValue == CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue,
            source.bytesPerRow == destBytesPerRow,
            let data = source.dataProvider?.data {
            
            let length = CFDataGetLength(data)
            memcpy(destBaseAddress, CFDataGetBytePtr(data), length)
            return
        }
        
        // 4. Otherwise, use Accelerate/vImage to convert from the CGImage format
        //    into the pixel buffer’s format.
        // Create vImage format descriptors for source and destination.
        var srcFormat = vImage_CGImageFormat(cgImage: source)!
        let dstFormat = vImageCVImageFormat.make(format: .format32BGRA, colorSpace: colorSpace, alphaIsOpaqueHint: false)!
        
        // Prepare a vImage buffer for the source image.
        var srcBuffer = vImage_Buffer()
        defer {
            free(srcBuffer.data)
        }
        
        // Initialize that buffer with the CGImage’s pixels.
        let initError = vImageBuffer_InitWithCGImage(
            &srcBuffer,
            &srcFormat,
            nil,
            source,
            vImage_Flags(kvImageNoFlags)
        )
        guard initError == kvImageNoError else { throw vImage.Error(vImageError: initError) }
        
        // Prepare a vImage buffer pointing directly at the CVPixelBuffer’s memory.
        var dstBuffer = vImage_Buffer(
            data: destBaseAddress,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: destBytesPerRow
        )
        
        // Create a converter that handles any needed color or alpha transformations.
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
        
        // Run the conversion.
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
    public func startWriting(yield: @escaping @Sendable (_ index: Int) async throws -> CGImage?) async throws {
        assetWriter.add(assetWriterVideoInput)
        
        // If here, AVAssetWriter exists so create AVAssetWriterInputPixelBufferAdaptor
        let sourceBufferAttributes : [String : AnyObject] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA as AnyObject,
            kCVPixelBufferWidthKey           as String: size.width                as AnyObject,
            kCVPixelBufferHeightKey          as String: size.height               as AnyObject
        ]
        
        nonisolated(unsafe)
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterVideoInput, sourcePixelBufferAttributes: sourceBufferAttributes)
        
        // Start writing session
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: CMTime.zero)
        
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
                        let semaphore = DispatchSemaphore(value: 0)
                        // semaphore runs on media queue, ensures it waits for task to complete. otherwise it would keep requesting medias.
                        Task { @Sendable in
                            defer { semaphore.signal() }
                            
                            // prepare buffer
                            var pixelBuffer: CVPixelBuffer? = nil
                            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBuffer)
                            
                            let index = counter.add(1, ordering: .sequentiallyConsistent).oldValue
                            let presentationTime = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(frameRate))
                            
                            do {
                                guard videoState.withLock({ $0 == .rendering }) else { nextFrameTask?.cancel(); return }
                                
                                guard let frame = try await nextFrameTask?.value else {
                                    videoState.withLock { state in
                                        if state == .rendering {
                                            state = .willFinish
                                        }
                                    }
                                    return
                                }
                                
                                guard videoState.withLock({ $0 == .rendering }) else { nextFrameTask?.cancel(); return }
                                nextFrameTask = dispatchNextFrame(index: index + 1)
                                
                                try VideoWriter.copyOrConvertCGImage(frame, to: pixelBuffer!, colorSpace: defaultColorSpace)
                                pixelBufferAdaptor.append(pixelBuffer!, withPresentationTime: presentationTime)
                            } catch {
                                videoState.withLock { state in
                                    if state == .rendering {
                                        state = .errored(error as NSError)
                                    }
                                }
                            }
                        }
                        semaphore.wait()
                    } // end while loop
                    
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
                assetWriter.cancelWriting()
                
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
            await assetWriter.finishWriting()
            
            if let error = assetWriter.error {
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
        guard size.width <= 8192 && size.height <= 4320 else { throw WriteError.videoSizeTooLarge(size) }
        
        self.size = size
        self.frameRate = frameRate
        self.destination = destination
        
        let videoWidth  = size.width
        let videoHeight = size.height
        
        try destination.removeIfExists()
        
        self.assetWriter = try AVAssetWriter(outputURL: destination.url, fileType: container)
        
        // Define settings for video input
        let videoSettings: [String : AnyObject] = [
            AVVideoCodecKey : codec       as AnyObject,
            AVVideoWidthKey : videoWidth  as AnyObject,
            AVVideoHeightKey: videoHeight as AnyObject
        ]
        
        // Add video input to writer
        self.assetWriterVideoInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
    }
    
    
    private class MetalImageConverter {
        private let device: MTLDevice
        private let commandQueue: MTLCommandQueue
        private let textureLoader: MTKTextureLoader
        
        init() {
            self.device = MTLCreateSystemDefaultDevice()!
            self.commandQueue = self.device.makeCommandQueue()!
            self.textureLoader = MTKTextureLoader(device: self.device)
        }
        
        func convertImageToPixelBuffer(_ image: CGImage, pixelBuffer: CVPixelBuffer?, size: CGSize)  {
            let texture = try! textureLoader.newTexture(cgImage: image, options: nil)
            
            let buffer = pixelBuffer!
            
            CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
            defer {
                CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
            }
            
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: Int(size.width),
                height: Int(size.height),
                mipmapped: false
            )
            
            textureDescriptor.usage = [.shaderWrite, .shaderRead]
            
            let textureFromBuffer = device.makeTexture(
                descriptor: textureDescriptor,
                iosurface: CVPixelBufferGetIOSurface(buffer)!.takeUnretainedValue(),
                plane: 0)!
            
            let commandBuffer = commandQueue.makeCommandBuffer()!
            let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
            
            var drawCGRect = CGRect(center: CGPoint(x: image.size.width / 2, y: image.size.height / 2), size: size)
            
            if drawCGRect.origin == CGPoint(x: 44, y: 44) {
                // caused by focus, use auto correct
                drawCGRect.origin.y -= 20
            }
            
            blitEncoder.copy(
                from: texture,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: max(0, Int(drawCGRect.origin.x)), y: max(0, Int(drawCGRect.origin.y)), z: 0),
                sourceSize: MTLSize(width: Int(drawCGRect.width), height: Int(drawCGRect.height), depth: 1),
                to: textureFromBuffer,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOriginMake(0, 0, 0)
            )
            blitEncoder.endEncoding()
            
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            assert(commandBuffer.status.rawValue == 4)
        }
    }
    
    public enum WriteError: GenericError, Equatable {
        
        case pixelBufferPoolNil
        case videoSizeTooLarge(CGSize)
        
        public var message: String {
            switch self {
            case .pixelBufferPoolNil:
                "Pixel buffer pool is nil after starting writing session, this typically means you do not have permission to write to the given file"
            case .videoSizeTooLarge(let size):
                "HEVC codec supports the resolutions up to 8192×4320, the given size, \(Int(size.width))×\(Int(size.height)), is too large"
            }
        }
        
    }
    
}
