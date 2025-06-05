//
//  AVAsset + merge.swift
//  MediaKit
//
//  Created by Vaida on 2025-05-30.
//

import AVFoundation
import FinderItem


extension AVAsset {
    
    /// Merge the given videos.
    public static func merge(
        videos: [FinderItem],
        to destination: FinderItem,
        container: AVFileType = .mov
    ) async throws {
        let composition = AVMutableComposition()
        guard let trackVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let trackAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw MergeError.cannotCreateVideoTrack
        }
        
        var currentTime = CMTime.zero
        for video in videos {
            let asset = AVURLAsset(url: video.url)
            let duration = try await asset.load(.duration)
            
            guard let assetVideoTrack = try await asset.loadTracks(withMediaType: .video).first else { throw MergeError.cannotReadContentsOfFile(path: video.url) }
            try trackVideo.insertTimeRange(
                CMTimeRange(start: CMTime.zero, duration: duration),
                of: assetVideoTrack,
                at: currentTime
            )
            
            
            if let assetAudioTrack = try await asset.loadTracks(withMediaType: .audio).first {
                let timeRange = CMTimeRange(start: .zero, duration: duration)
                try trackAudio.insertTimeRange(
                    timeRange,
                    of: assetAudioTrack,
                    at: currentTime
                )
            }
            
            currentTime = currentTime + duration
        }
        
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else { throw MergeError.cannotCreateExportSession }
        try destination.removeIfExists()
        try await exporter.export(to: destination.url, as: container)
    }
    
}
