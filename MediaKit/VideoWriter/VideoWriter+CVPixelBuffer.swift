//
//  VideoWriter+CVPixelBuffer.swift
//  MediaKit
//
//  Created by Vaida on 2026-11-11.
//

import AVFoundation
import Synchronization


extension VideoWriter {
    
    /// Fills the pixel buffer of one frame.
    ///
    /// - term index: The index of the frame.
    /// - term pixelBuffer: The pixel buffer for you to fill, see `startWriting(yield:)` for its format and the rules for accessing it.
    /// - term returns: `false` for when the frames are exhausted and the current `pixelBuffer` is never read back.
    public typealias CVPixelBufferYield = (_ index: Int, _ pixelBuffer: CVPixelBuffer) throws -> Bool
    
    /// Starts writing to destination.
    ///
    /// - Parameters:
    ///   - yield: Fills the pixel buffer of each frame, see `CVPixelBufferYield`.
    ///
    /// To cancel the video writer, cancel the parent task. The writer requests no more frames once it observes the cancellation, removes the partially written file, and throws `CancellationError`. A call to `yield` that is already running is not interrupted, and a call that was just about to start may still run right after the cancellation was requested.
    ///
    /// On systems earlier than iOS 26, macOS 26, and visionOS 26, `Task.isCancelled` is not set inside `yield`, so a long-running `yield` cannot stop early.
    ///
    /// Returns after the video is finalized.
    ///
    /// - Note: the `pixelBuffer` is explicitly metal-compatible.
    ///
    /// > Precondition:
    /// > With `SDR`, the `pixelBuffer` is in `kCVPixelFormatType_32BGRA`, which is `CGImageAlphaInfo.premultipliedFirst | CGBitmapInfo.byteOrder32Little`, with `bitsPerComponent = 8`, and `bitsPerPixel = 32`.
    /// >
    /// > With `HDR`, it is in `kCVPixelFormatType_64RGBAHalf`: four half floats a pixel, in the order R, G, B, A, holding the HLG signal, see ``ColorSpace``. It is already tagged, so do not remove the tags. In Metal, that is `MTLPixelFormat.rgba16Float`.
    /// >
    /// > It already has the `size` the writer was created with, and is IOSurface-backed, so it can be a render target for Core Image or Metal.
    /// >
    /// > To access its bytes on the CPU:
    /// > - Lock it with `CVPixelBufferLockBaseAddress` first, as it is not locked when passed to `yield`.
    /// > - Use `CVPixelBufferGetBytesPerRow` as the row stride, as rows can be padded beyond `width * 4` (`width * 8` for `HDR`).
    /// > - Overwrite every pixel, as the buffer comes from a pool and its initial contents are unspecified.
    /// >
    /// > Do not keep the `pixelBuffer`, or modify it, after `yield` returns.
    ///
    /// - Warning: This function does not check these rules. Writing outside the bounds of the `pixelBuffer`, or modifying it after `yield` returns, is undefined behavior.
    public consuming func startWriting(yield: @escaping CVPixelBufferYield) async throws {
        if #available(iOS 26.0, macOS 26.0, visionOS 26, *) {
            return try await self.startWriting_post26(yield: yield)
        } else {
            return try await self.startWriting_pre26(yield: yield)
        }
    }
    
    
    /// Writes frames using AVFoundation's iOS 26+ async pixel-buffer receiver API.
    ///
    /// Not private, so that tests can run both write paths on any system.
    @available(iOS 26.0, macOS 26.0, visionOS 26, *)
    func startWriting_post26(yield: CVPixelBufferYield) async throws {
        nonisolated(unsafe) let writer = assetWriter
        guard writer.status == .unknown else { throw WriteError.invalidAssetWriterState(writer.status.rawValue) }
        
        let attributes = CVPixelBufferCreationAttributes(
            pixelFormatType: .init(rawValue: colorSpace.pixelFormatType),
            size: CVImageSize(size),
            compatibility: [.metalTexture]
        )
        let inputReceiver = writer.inputPixelBufferReceiver(for: assetWriterVideoInput, pixelBufferAttributes: attributes)
        
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        
        guard let pixelBufferPool = inputReceiver.pixelBufferPool else { writer.cancelWriting(); throw WriteError.pixelBufferPoolNil }
        
        let timescale = CMTimeScale(frameRate)
        
        do {
            var frameIndex = 0
            while true {
                // dispatch next frame
                try Task.checkCancellation() // we put check cancellation here based on the assumption that generating frame is the heaviest stack.
                
                let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: timescale)
                
                let mutablePixelBuffer = try pixelBufferPool.makeMutablePixelBuffer()
                let isValid = try mutablePixelBuffer.withUnsafeBuffer { pixelBuffer in
                    self.colorSpace.tag(pixelBuffer)
                    return try yield(frameIndex, pixelBuffer)
                }
                guard isValid else { break }
                
                try await inputReceiver.append(.init(mutablePixelBuffer), with: presentationTime)
                frameIndex += 1
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
    func startWriting_pre26(yield: @escaping CVPixelBufferYield) async throws {
        nonisolated(unsafe) let writer = assetWriter
        guard writer.status == .unknown else { throw WriteError.invalidAssetWriterState(writer.status.rawValue) }
        
        writer.add(assetWriterVideoInput)
        
        let sourceBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: colorSpace.pixelFormatType,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
        
        nonisolated(unsafe)
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterVideoInput, sourcePixelBufferAttributes: sourceBufferAttributes)
        
        guard writer.startWriting() else {
            throw writer.error ?? WriteError.failedToStartWriting(writer.status.rawValue)
        }
        writer.startSession(atSourceTime: .zero)
        
        guard let _pixelBufferPool = pixelBufferAdaptor.pixelBufferPool else { writer.cancelWriting(); throw WriteError.pixelBufferPoolNil }
        nonisolated(unsafe) let pixelBufferPool = _pixelBufferPool
        
        var frameIndex = 0
        let videoState = Mutex<VideoState>(.rendering)
        let frameRate = frameRate
        
        try await withTaskCancellationHandler {
            let _: Void = await withCheckedContinuation { continuation in
                assetWriterVideoInput.requestMediaDataWhenReady(on: self.queue) { [weak self] in
                    while (self?.assetWriterVideoInput.isReadyForMoreMediaData ?? false) && videoState.withLock({ $0 == .rendering }) {
                        let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(frameRate))
                        
                        do {
                            // prepare buffer
                            var pixelBuffer: CVPixelBuffer? = nil
                            let pixelBufferCreationStatus = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBuffer)
                            guard pixelBufferCreationStatus == kCVReturnSuccess, let pixelBuffer else {
                                throw WriteError.failedToCreatePixelBuffer(pixelBufferCreationStatus)
                            }
                            
                            self?.colorSpace.tag(pixelBuffer)
                            guard try yield(frameIndex, pixelBuffer) else {
                                videoState.withLock { state in
                                    if state == .rendering {
                                        state = .willFinish
                                    }
                                }
                                break
                            }
                            guard pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                                throw writer.error ?? WriteError.failedToAppendFrame(frameIndex)
                            }
                            
                            frameIndex += 1
                        } catch {
                            videoState.withLock { state in
                                if state == .rendering {
                                    state = .errored(error as NSError)
                                }
                            }
                        }
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
