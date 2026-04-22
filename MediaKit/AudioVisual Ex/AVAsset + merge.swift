//
//  AVAsset + merge.swift
//  MediaKit
//
//  Created by Vaida on 2025-05-30.
//

import AVFoundation
import FinderItem
import Essentials


extension AVAsset {

    /// Merges multiple videos into a single output file.
    ///
    /// The method appends each source in order, preserves the preferred transform
    /// from the first video track, and includes audio when available.
    ///
    /// - Parameters:
    ///   - videos: Source videos to concatenate in order.
    ///   - destination: Output file path.
    ///   - container: Output file type. Defaults to `.mov`.
    /// - Throws: `MergeError` for invalid input, unreadable media, track creation,
    ///   or export failures.
    public static func merge(
        videos: [FinderItem],
        to destination: FinderItem,
        container: AVFileType = .mov
    ) async throws {
        guard !videos.isEmpty else { throw MergeError.fileEmpty(path: destination.url) }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw MergeError.cannotCreateVideoTrack
        }

        var audioTrack: AVMutableCompositionTrack?
        var currentTime: CMTime = .zero

        for video in videos {
            guard video.exists else { throw MergeError.cannotReadFile(path: video.url) }

            let asset = AVURLAsset(url: video.url)
            async let loadedVideoTrack = asset.loadTracks(withMediaType: .video).first
            async let loadedAudioTrack = asset.loadTracks(withMediaType: .audio).first

            guard let assetVideoTrack = try await loadedVideoTrack else {
                throw MergeError.cannotReadContentsOfFile(path: video.url)
            }

            let videoDuration = try await assetVideoTrack.load(.timeRange).duration
            guard videoDuration.isNumeric,
                  videoDuration.seconds > 0 else {
                throw MergeError.fileEmpty(path: video.url)
            }

            try videoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: videoDuration),
                of: assetVideoTrack,
                at: currentTime
            )

            if currentTime == .zero {
                videoTrack.preferredTransform = try await assetVideoTrack.load(.preferredTransform)
            }

            if let assetAudioTrack = try await loadedAudioTrack {
                let audioDuration = try await assetAudioTrack.load(.timeRange).duration
                let insertedDuration = min(videoDuration, audioDuration)

                if insertedDuration.isNumeric,
                   insertedDuration.seconds > 0 {
                    if audioTrack == nil {
                        guard let newAudioTrack = composition.addMutableTrack(
                            withMediaType: .audio,
                            preferredTrackID: kCMPersistentTrackID_Invalid
                        ) else {
                            throw MergeError.cannotCreateAudioTrack
                        }
                        audioTrack = newAudioTrack
                    }

                    try audioTrack?.insertTimeRange(
                        CMTimeRange(start: .zero, duration: insertedDuration),
                        of: assetAudioTrack,
                        at: currentTime
                    )
                }
            }

            currentTime = currentTime + videoDuration
        }

        guard currentTime.isNumeric,
              currentTime.seconds > 0 else {
            throw MergeError.fileEmpty(path: destination.url)
        }

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw MergeError.cannotCreateExportSession
        }

        try destination.removeIfExists()
        try await exporter.export(to: destination.url, as: container)
    }
    
    
    /// Merges a video with audio.
    ///
    /// - Note: The original video would be replaced.
    ///
    /// - Parameters:
    ///   - video: The `FinderItem` indicating the video.
    ///   - audio: The `FinderItem` indicating the audio.
    ///   - container: The filetype for the video.
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

}
