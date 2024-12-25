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


/// A writer for writing a stream.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, *)
public final class VideoWriter: @unchecked Sendable {
    
    private let assetWriter: AVAssetWriter
    
    private let assetWriterVideoInput: AVAssetWriterInput
    
    private let size: CGSize
    
    private let destination: FinderItem
    
    private let frameRate: Int
    
    private let queue = DispatchQueue(label: "package.MediaKit.VideoWriter.mediaQueue")
    
    
    /// Starts writing to destination.
    ///
    /// - Parameters:
    ///   - yield: The yield function, see discussion for more information.
    ///
    /// Parameters for `yield`:
    /// - term index: The index of the frame.
    /// - term returns: An image at the given index, or `nil`, indicating the end of video.
    ///
    /// To cancel the video writer, cancel the parent task. The cancellation will be propagated to `yield`.
    ///
    /// Returns after the video is finalized.
    ///
    /// - Precondition: The images produced from `yield` must match the `size` when initializing the writer.
    ///
    /// > Tip:
    /// > The native video frame buffer format is:
    /// > ```
    /// > CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    /// > ```
    /// > If the frames provided are also in this format, `VideoWriter` will not need to convert between formats and can directly use the internal storage of these frames, significantly improving rendering performance.
    public func startWriting(yield: @escaping (_ index: Int) async throws -> CGImage?) async throws {
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
        
        let drawCGRect = CGRect(x: 0, y: 0, width: Int(size.width), height: Int(size.height))
        let defaultColorSpace = CGColorSpaceCreateDeviceRGB()
        
        nonisolated(unsafe)
        var _continuation: CheckedContinuation<Void, any Error>? = nil
        
        nonisolated(unsafe)
        var nextFrameTask: Task<CGImage?, any Error>? = nil
        
        let isTaskCanceled = Atomic<Bool>(false)
        let counter = Atomic<Int>(0)
        let videoState = Mutex<VideoState>(.rendering)
        let frameRate = frameRate
        let size = self.size
        
        @Sendable func dispatchNextFrame(index: Int) -> Task<CGImage?, any Error>? {
            Task.detached {
                try await yield(index)
            }
        }
        nextFrameTask = dispatchNextFrame(index: 0)
        
        try await withTaskCancellationHandler {
            let _: Void = try await withCheckedThrowingContinuation { continuation in
                _continuation = continuation
                
                assetWriterVideoInput.requestMediaDataWhenReady(on: self.queue) { [weak self] in
                    
                    while (self?.assetWriterVideoInput.isReadyForMoreMediaData ?? false) && videoState.withLock({ $0 == .rendering }) {
                        let semaphore = DispatchSemaphore(value: 0)
                        // semaphore runs on media queue, ensures it waits for task to complete. otherwise it would keep requesting medias.
                        
                        Task {
                            defer { semaphore.signal() }
                            guard !isTaskCanceled.load(ordering: .sequentiallyConsistent) else { return }
                            
                            // prepare buffer
                            let pixelBufferPointer = UnsafeMutablePointer<CVPixelBuffer?>.allocate(capacity: 1)
                            
                            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, pixelBufferPointer)
                            let pixelBuffer = pixelBufferPointer.pointee!
                            
                            let index = counter.add(1, ordering: .sequentiallyConsistent).oldValue
                            let presentationTime = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(frameRate))
                            
                            // Draw image into context
                            defer {
                                pixelBufferPointer.deinitialize(count: 1)
                                pixelBufferPointer.deallocate()
                            }
                            
                            do {
                                guard !isTaskCanceled.load(ordering: .sequentiallyConsistent) else { return }
                                guard let frame = try await nextFrameTask?.value else {
                                    videoState.withLock({ $0 = .willCancel })
                                    return
                                }
                                
                                nextFrameTask = dispatchNextFrame(index: index + 1)
                                
                                CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
                                
                                let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)
                                let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
                                
                                if frame.bitsPerComponent == 8 && frame.bitsPerPixel == 32,
                                   frame.bitmapInfo.rawValue == CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue,
                                   bytesPerRow == frame.bytesPerRow,
                                   let data = frame.dataProvider?.data {
                                    let length = CFDataGetLength(data)
                                    memcpy(pixelData, CFDataGetBytePtr(data), length)
                                } else {
                                    // Create CGBitmapContext
                                    let context = CGContext(
                                        data: pixelData,
                                        width: Int(size.width),
                                        height: Int(size.height),
                                        bitsPerComponent: 8,
                                        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                        space: defaultColorSpace,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
                                    )!
                                    
                                    context.draw(frame, in: drawCGRect)
                                }
                                
                                CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
                                pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                            } catch {
                                videoState.withLock({ $0 = .errored(error as NSError) })
                            }
                        }
                        
                        semaphore.wait()
                    }
                    
                    videoState.withLock { state in
                        switch state {
                        case .rendering:
                            break
                        case .willCancel:
                            continuation.resume()
                            state = .didCancel
                        case .errored(let error):
                            continuation.resume(throwing: error)
                            state = .didCancel
                        case .didCancel:
                            break
                        }
                    }
                }
            }
            
            if Task.isCancelled {
                // run in on cancel
                return
            }
            
            self.queue.sync { }
            await assetWriter.finishWriting()
            
            if let error = assetWriter.error {
                throw error
            }
        } onCancel: {
            isTaskCanceled.store(true, ordering: .sequentiallyConsistent)
            nextFrameTask?.cancel()
            _continuation?.resume()
            assetWriterVideoInput.markAsFinished()
            
            assetWriter.finishWriting {
                try? self.destination.removeIfExists()
            }
        }
    }
    
    
    private enum VideoState: Equatable {
        case rendering
        case willCancel
        case errored(NSError)
        case didCancel
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
