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


/// A writer for writing a stream.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, *)
public final class VideoWriter: @unchecked Sendable {
    
    let assetWriter: AVAssetWriter
    
    let assetWriterVideoInput: AVAssetWriterInput
    
    let size: CGSize
    
    let frameRate: Int
    
    let mediaQueue = DispatchQueue(label: "app.PianoVisualizer.VideoWriter.mediaQueue")
    
    // Must use GCD instead of swift concurrency.
    let preparePixelQueue = DispatchQueue(label: "app.PianoVisualizer.VideoWriter.preparePixelQueue")
    
    let counter = Mutex(0)
    
    
    /// Starts writing to destination.
    ///
    /// - Parameters:
    ///   - yield: The yield function, see discussion for more information.
    ///
    /// Parameters for `yield`:
    /// - term index: The index of the frame.
    /// - term returns: An image at the given index, or `nil`, indicating the end of video.
    ///
    /// - Precondition: The images produced from `yield` must match the `size` when initializing the writer.
    public func startWriting(yield: @escaping (_ index: Int) -> CGImage?) async throws {
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
        
        guard pixelBufferAdaptor.pixelBufferPool != nil else { throw ConvertImagesToVideoError.pixelBufferPoolNil }
        
//        nonisolated(unsafe)
//        let converter = MetalImageConverter()
        
        let drawCGRect = CGRect(x: 0, y: 0, width: Int(size.width), height: Int(size.height))
        let defaultColorSpace = CGColorSpaceCreateDeviceRGB()
        
        let _: Void = await withCheckedContinuation { continuation in
            assetWriterVideoInput.requestMediaDataWhenReady(on: mediaQueue) { [unowned self] in
                autoreleasepool {
                    guard assetWriterVideoInput.isReadyForMoreMediaData else { return } // go on waiting
                    
                    // prepare buffer
                    nonisolated(unsafe)
                    let pixelBufferPointer = UnsafeMutablePointer<CVPixelBuffer?>.allocate(capacity: 1)
                    
                    nonisolated(unsafe)
                    var pixelBuffer: CVPixelBuffer! = nil
                    
                    nonisolated(unsafe)
                    var presentationTime: CMTime! = nil
                    
                    preparePixelQueue.async {
                        let pixelBufferPool = pixelBufferAdaptor.pixelBufferPool!
                        
                        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, pixelBufferPointer)
                        pixelBuffer = pixelBufferPointer.pointee!
                        
                        presentationTime = self.counter.withLock { counter in
                            CMTime(value: CMTimeValue(counter), timescale: CMTimeScale(self.frameRate))
                        }
                    }
                    
                    let index = counter.withLock { counter in
                        counter
                    }
                    // Produce
                    
                    // Draw image into context
                    
                    preparePixelQueue.sync { } // wait for the queue
                    defer {
                        pixelBufferPointer.deallocate()
                    }
                    
                    guard let frame = yield(index) else {
                        assetWriterVideoInput.markAsFinished()
                        continuation.resume()
                        return
                    }
                    
                    CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
                    
                    let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)
                    
                    // Create CGBitmapContext
                    let context = CGContext(data: pixelData, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: defaultColorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
                    
                    context.draw(frame, in: drawCGRect)
                    CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
                    
                    pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                    pixelBufferPointer.deinitialize(count: 1)
                    
                    counter.withLock { $0 += 1 }
                }
            }
        }
        
        mediaQueue.sync { }
        await assetWriter.finishWriting()
        
        guard assetWriter.error == nil else { throw assetWriter.error! }
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
        self.size = size
        self.frameRate = frameRate
        
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
    
    private enum ConvertImagesToVideoError: LocalizedError, CustomStringConvertible {
        
        case pixelBufferPoolNil
        
        case cannotCreateCGContext
        
        
        var description: String {
            "\(errorDescription!): \(failureReason!)"
        }
        
        
        var errorDescription: String? { "Convert images to video error" }
        
        var failureReason: String? {
            switch self {
            case .pixelBufferPoolNil:
                return "Pixel buffer pool is nil after starting writing session, this typically means you do not have permission to write to the given file"
            case .cannotCreateCGContext:
                return "Cannot create CGContext for a frame"
            }
        }
        
    }
    
}
