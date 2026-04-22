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
    
    
    /// Merges a video file with an audio file.
    ///
    /// The result is written to a temporary file and then atomically moved to
    /// replace `video`. The merged output duration is capped to the shorter of
    /// the source video and source audio durations.
    ///
    /// - Parameters:
    ///   - video: The `FinderItem` indicating the destination video file.
    ///   - audio: The `FinderItem` indicating the source audio file.
    ///   - container: The file type for the merged output.
    static func merge(video: FinderItem, withAudio audio: FinderItem, container: AVFileType = .mov) async throws {
        guard video.exists else { throw MergeError.cannotReadFile(path: video.url) }
        guard audio.exists else { throw MergeError.cannotReadFile(path: audio.url) }

        guard let videoAsset = await AVAsset(at: video) else { throw MergeError.cannotReadContentsOfFile(path: video.url) }
        guard let audioAsset = await AVAsset(at: audio) else { throw MergeError.cannotReadContentsOfFile(path: audio.url) }

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw MergeError.cannotCreateVideoTrack }
        
        guard let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw MergeError.cannotCreateAudioTrack }

        async let loadedVideoTrack = videoAsset.loadTracks(withMediaType: .video).first
        async let loadedAudioTrack = audioAsset.loadTracks(withMediaType: .audio).first

        guard let sourceVideoTrack = try await loadedVideoTrack else { throw MergeError.fileEmpty(path: video.url) }
        guard let sourceAudioTrack = try await loadedAudioTrack else { throw MergeError.fileEmpty(path: audio.url) }

        let videoDuration = try await sourceVideoTrack.load(.timeRange).duration
        let audioDuration = try await sourceAudioTrack.load(.timeRange).duration
        let mergedDuration = min(videoDuration, audioDuration)

        guard mergedDuration.isNumeric,
              mergedDuration.seconds > 0 else { throw MergeError.fileEmpty(path: video.url) }

        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: mergedDuration),
            of: sourceVideoTrack,
            at: .zero
        )
        try compositionAudioTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: mergedDuration),
            of: sourceAudioTrack,
            at: .zero
        )
        compositionVideoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else { throw MergeError.cannotCreateExportSession }

        let temp = try (FinderItem.temporaryDirectory(intent: .discardable) / (UUID().uuidString + "." + video.extension)).generateUniquePath()
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
