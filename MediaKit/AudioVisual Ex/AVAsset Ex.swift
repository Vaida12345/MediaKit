//
//  AudioVisual Extensions.swift
//  The Stratum Module
//
//  Created by Vaida on 7/19/22.
//  Copyright © 2019 - 2024 Vaida. All rights reserved.
//


#if !os(watchOS)
@preconcurrency import AVFoundation
import OSLog
import FinderItem
import ConcurrentStream
import Synchronization
import NativeImage
import Essentials


public extension AVAsset {
    
    /// The first frame of the video.
    @available(visionOS, unavailable)
    @inlinable
    var firstFrame: CGImage {
        get async throws {
            let imageGenerator = AVAssetImageGenerator(asset: self)
            imageGenerator.maximumSize = .square(512)
            let time = try await CMTime(value: 0, timescale: self.load(.duration).timescale)
            return try await withCheckedThrowingContinuation { continuation in
                imageGenerator.generateCGImageAsynchronously(for: time) { image, _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: image!)
                    }
                }
            }
        }
    }
    
    /// Initializes an `AVAsset` with the contents at the specified `FinderItem`.
    ///
    /// - Parameters:
    ///   - source: The `FinderItem` representing the location of the asset.
    ///
    /// Returns an `AVAsset` instance initialized with the data at the passed-in `source` or `nil` if the object is not readable.
    @inlinable
    convenience init?(at source: FinderItem) async {
        self.init(url: source.url)
        guard await (try? self.load(.isReadable)) ?? false else { return nil }
    }
    
    var frameCount: Int {
        get async throws {
            let vidLength: CMTime = try await self.load(.duration)
            guard let video = try await self.loadTracks(withMediaType: .video).first else { throw GenerateFramesStreamError.assetNotVideo }
            let seconds = vidLength.seconds
            let frameRate = try await video.load(.nominalFrameRate)
            return Int(seconds * Double(frameRate))
        }
    }
    
    
    /// Returns the iterator of all the frames of the video.
    func generateFramesStream() async throws -> AsyncStream<(image: CGImage, actualTime: CMTime)> {
        let vidLength: CMTime = try await self.load(.duration)
        
        guard let video = try await self.loadTracks(withMediaType: .video).first else { throw GenerateFramesStreamError.assetNotVideo }
        
        let seconds = vidLength.seconds
        let frameRate = try await video.load(.nominalFrameRate)
        
        var requiredFramesCount = Int(seconds * Double(frameRate))
        if requiredFramesCount == 0 { requiredFramesCount = 1 }
        
        let step = Int(vidLength.value / Int64(requiredFramesCount))
        
        let imageGenerator = AVAssetImageGenerator(asset: self)
        imageGenerator.requestedTimeToleranceAfter = CMTime(value: CMTimeValue(step / 2), timescale: vidLength.timescale)
        imageGenerator.requestedTimeToleranceBefore = CMTime(value: CMTimeValue(step / 2), timescale: vidLength.timescale)
        
        let requestedTimes = (0..<requiredFramesCount).map { CMTime(value: Int64(step * $0), timescale: vidLength.timescale) }
        
        return AsyncStream { continuation in
            Task {
                for time in requestedTimes {
                    guard let result = try? await imageGenerator.image(at: time) else { return }
                    continuation.yield(result)
                }
                
                continuation.finish()
            }
        }
    }
    
    private enum GenerateFramesStreamError: LocalizedError {
        case assetNotVideo
        
        var errorDescription: String? { "Generate frames for video error" }
        
        var failureReason: String? {
            switch self {
            case .assetNotVideo:
                return "The given asset is not a video"
            }
        }
    }
    
    /// Returns all the frames of the video.
    ///
    /// - Important: Only non-`nil` images of requested times are kept.
    @inlinable
    func generateFrames() async throws -> [CGImage] {
        var iterator = try await self.generateFramesStream().makeAsyncIterator()
        
        var result: [CGImage] = []
        
        while let next = await iterator.next() {
            result.append(next.image)
        }
        
        return result
    }
    
    /// Merges a video with audio.
    ///
    /// - Note: The original video would be replaced.
    ///
    /// - Parameters:
    ///   - video: The `FinderItem` indicating the video.
    ///   - audio: The `FinderItem` indicating the audio.
    ///   - container: The filetype for the video.
    ///
    /// Source: [stack overflow](https://stackOverflow.com/questions/31984474/swift-merge-audio-and-video-files-into-one-video)
    static func merge(video: FinderItem, withAudio audio: FinderItem, container: AVFileType = .mov) async throws {
        guard video.exists else { throw MergeError.cannotReadFile(path: video.url) }
        guard audio.exists else { throw MergeError.cannotReadFile(path: audio.url) }
        
        let mixComposition: AVMutableComposition = AVMutableComposition()
        var mutableCompositionVideoTrack: [AVMutableCompositionTrack] = []
        var mutableCompositionAudioTrack: [AVMutableCompositionTrack] = []
        let totalVideoCompositionInstruction : AVMutableVideoCompositionInstruction = AVMutableVideoCompositionInstruction()
        
        guard let aVideoAsset = await AVAsset(at: video) else { throw MergeError.cannotReadContentsOfFile(path: video.url) }
        guard let aAudioAsset = await AVAsset(at: audio) else { throw MergeError.cannotReadContentsOfFile(path: audio.url) }
        
        guard let videoTrack = mixComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw MergeError.cannotCreateVideoTrack }
        guard let audioTrack = mixComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw MergeError.cannotCreateAudioTrack }
        
        mutableCompositionVideoTrack.append(videoTrack)
        mutableCompositionAudioTrack.append(audioTrack)
        
        guard let aVideoAssetTrack = try await aVideoAsset.loadTracks(withMediaType: .video).first else { throw MergeError.fileEmpty(path: video.url) }
        guard let aAudioAssetTrack = try await aAudioAsset.loadTracks(withMediaType: .audio).first else { throw MergeError.fileEmpty(path: audio.url) }
        
        try await mutableCompositionVideoTrack.first?.insertTimeRange(CMTimeRange(start: .zero, duration: aVideoAssetTrack.load(.timeRange).duration), of: aVideoAssetTrack, at: .zero)
        try await mutableCompositionAudioTrack.first?.insertTimeRange(CMTimeRange(start: .zero, duration: aAudioAssetTrack.load(.timeRange).duration), of: aAudioAssetTrack, at: .zero)
        videoTrack.preferredTransform = try await aVideoAssetTrack.load(.preferredTransform)
        
        try await totalVideoCompositionInstruction.timeRange = CMTimeRange(start: .zero, duration: aVideoAssetTrack.load(.timeRange).duration)
        
        let mutableVideoComposition: AVMutableVideoComposition = AVMutableVideoComposition()
        let frame = try await Fraction(aVideoAssetTrack.load(.nominalFrameRate))
        mutableVideoComposition.frameDuration = CMTime(value: Int64(frame.denominator), timescale: Int32(frame.numerator))
        mutableVideoComposition.renderSize = try await aVideoAssetTrack.load(.naturalSize)
        
        guard let exportSession = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetPassthrough) else { throw MergeError.cannotCreateExportSession }
        
        let temp = try (FinderItem.temporaryDirectory(intent: .discardable)/video.name).generateUniquePath()
        try temp.removeIfExists()
        try await exportSession.export(to: temp.url, as: container)
        try video.remove()
        try temp.move(to: video.url)
    }
    
    /// A set of errors as defined in the extensions for AVAsset.
    enum MergeError: GenericError {
        
        case cannotReadFile(path: URL)
        case cannotReadContentsOfFile(path: URL)
        case fileEmpty(path: URL)
        
        case cannotCreateAudioTrack
        case cannotCreateVideoTrack
        case cannotCreateExportSession
        
        
        public var message: String {
            switch self {
            case .cannotReadFile(let path):
                return "Cannot read file at \(path)."
            case .cannotReadContentsOfFile(let path):
                return "Cannot read contents of file at \(path)."
            case .cannotCreateAudioTrack:
                return "Cannot create audio track"
            case .cannotCreateVideoTrack:
                return "Cannot create video track"
            case .fileEmpty(let path):
                return "The file at \(path) does not contain the desired content"
            case .cannotCreateExportSession:
                return "Cannot create export session"
            }
        }
    }
    
    /// Convert image sequence to video.
    ///
    /// - Note: All the `images` are expected to be of the same size.
    ///
    /// - Important: if the video already exists, it would be overwritten.
    ///
    /// - Parameters:
    ///   - images: The source containing an array of elements which can be inferred as image.
    ///   - video: The `FinderItem` indicating the destination for video. The path **will** be mutated if file exists.
    ///   - videoFPS: The frameRate for the resulting video.
    ///   - colorSpace: The colorSpace for the resulting video. If `nil` is passed, the colorSpace for the cgImage would be used instead.
    ///   - container: The video container for the resulting video.
    ///   - codec: The video codec for the resulting video.
    ///   - getImage: The function to extract image from an element of `images`.
    ///   - getTime: The function to extract time from an element of `image`. Note that when this is not `nil`, the `videoFPS` parameter will not be used.
    ///
    /// Source: [stack overflow](https://stackOverflow.com/questions/3741323/how-do-i-export-UIImage-array-as-a-movie/3742212#36297656)
    static func convert<Element: Sendable, E>(images: some ConcurrentStream<Element, E>, toVideo video: FinderItem, videoFPS: Float, colorSpace: CGColorSpace? = nil, container: AVFileType = .mov, codec: AVVideoCodecType = .hevc, getImage: @escaping @Sendable (_ item: Element) -> CGImage, getTime: (@Sendable (_ item: Element) -> CMTime)? = nil) async throws where E: Error {
        
        let video = video.generateUniquePath()
        
        let logger = Logger(subsystem: "The Support Framework", category: "AVAsset Extension")
        
        guard let first = try await images.next() else { throw ConvertImagesToVideoError.imagesEmpty }
        
        let iterator = [first].stream + images
        
        let _frame: CGImage? = getImage(first)
        let videoWidth  = _frame!.width
        let videoHeight = _frame!.height
        
        try video.enclosingFolder.makeDirectory()
        
        let assetWriter = try AVAssetWriter(outputURL: video.url, fileType: container)
        
        // Define settings for video input
        let videoSettings: [String : AnyObject] = [
            AVVideoCodecKey : codec       as AnyObject,
            AVVideoWidthKey : videoWidth  as AnyObject,
            AVVideoHeightKey: videoHeight as AnyObject
        ]
        
        // Add video input to writer
        nonisolated(unsafe)
        let assetWriterVideoInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
        assetWriter.add(assetWriterVideoInput)
        
        // If here, AVAssetWriter exists so create AVAssetWriterInputPixelBufferAdaptor
        let sourceBufferAttributes : [String : AnyObject] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB) as AnyObject,
            kCVPixelBufferWidthKey           as String: videoWidth                     as AnyObject,
            kCVPixelBufferHeightKey          as String: videoHeight                    as AnyObject
        ]
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterVideoInput, sourcePixelBufferAttributes: sourceBufferAttributes)
        
        // Start writing session
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: CMTime.zero)
        guard pixelBufferAdaptor.pixelBufferPool != nil else { throw ConvertImagesToVideoError.pixelBufferPoolNil }
        
        // -- Create queue for <requestMediaDataWhenReadyOnQueue>
        let mediaQueue = DispatchQueue(label: "Media Queue")
        
        // -- Set video parameters
        let frameRate = Fraction(videoFPS)
        let frameDuration = CMTime(value: Int64(frameRate.denominator), timescale: Int32(frameRate.numerator))
        let frameCounter = Atomic(0)
        
        logger.info("Start to create video from the given stream")
        
        // -- Add images to video
        let _: Void = try await withCheckedThrowingContinuation { continuation in
            let drawCGRect = CGRect(x: 0, y: 0, width: videoWidth, height: videoHeight)
            let defaultColorSpace = CGColorSpaceCreateDeviceRGB()
            
            assetWriterVideoInput.requestMediaDataWhenReady(on: mediaQueue) {
                let semaphore = DispatchSemaphore(value: 0)
                
                Task(priority: .high) {
                    defer { semaphore.signal() }
                    
                    do {
                        guard assetWriterVideoInput.isReadyForMoreMediaData else { return } // go on waiting
                        
                        let frameCount = frameCounter.add(1, ordering: .sequentiallyConsistent).oldValue
                        
                        // Draw image into context
                        logger.debug("Enquiring next frame")
                        guard let frame = try await iterator.next() else {
                            logger.info("The given stream is f-zero, start to encode")
                            assetWriterVideoInput.markAsFinished()
                            
                            continuation.resume()
                            return
                        }
                        
                        logger.debug("Started a frame")
                        
                        let presentationTime: CMTime
                        
                        if let getTime {
                            presentationTime = getTime(frame)
                        } else {
                            let lastFrameTime = CMTimeMake(value: Int64(frameCount) * Int64(frameRate.denominator), timescale: Int32(frameRate.numerator))
                            presentationTime = frameCount == 0 ? lastFrameTime : CMTimeAdd(lastFrameTime, frameDuration)
                        }
                        
                        let pixelBufferPool = pixelBufferAdaptor.pixelBufferPool!
                        let pixelBufferPointer = UnsafeMutablePointer<CVPixelBuffer?>.allocate(capacity: 1)
                        
                        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, pixelBufferPointer)
                        let pixelBuffer = pixelBufferPointer.pointee!
                        
                        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
                        
                        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)
                        
                        // Create CGBitmapContext
                        guard let context = CGContext(data: pixelData, width: videoWidth, height: videoHeight, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: colorSpace ?? defaultColorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else {
                            throw ConvertImagesToVideoError.cannotCreateCGContext
                        }
                        
                        context.draw(getImage(frame), in: drawCGRect)
                        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))

						// let drawCGRect = CGRect(center: CGPoint(x: size.width / 2, y: size.height / 2), size: frame.size)
                		// let context = CIContext()
                		// context.render(CIImage(cgImage: frame), to: pixelBuffer, bounds: drawCGRect, colorSpace: frame.colorSpace)
                        
                        pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                        pixelBufferPointer.deinitialize(count: 1)
                        pixelBufferPointer.deallocate()
                        
                        logger.debug("Ended a frame")
                    } catch {
                        assetWriterVideoInput.markAsFinished()
                        continuation.resume(throwing: error)
                    }
                }
                
                semaphore.wait()
            }
        }
        
        logger.info("Waiting for additional encoding tasks")
        mediaQueue.sync { }
        await assetWriter.finishWriting()
        logger.info("Encoding completes")
        
        guard assetWriter.error == nil else { throw assetWriter.error! }
    }
    
    private enum ConvertImagesToVideoError: LocalizedError {
        
        case imagesEmpty
        
        case pixelBufferPoolNil
        
        case cannotCreateCGContext
        
        
        var errorDescription: String? { "Convert images to video error" }
        
        var failureReason: String? {
            switch self {
            case .imagesEmpty:
                return "The images sequence from which the video is formed is empty"
            case .pixelBufferPoolNil:
                return "Pixel buffer pool is nil after starting writing session, this typically means you do not have permission to write to the given file"
            case .cannotCreateCGContext:
                return "Cannot create CGContext for a frame"
            }
        }
        
    }
}
#endif
