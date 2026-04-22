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
    ///
    /// - Parameter maximumSize: The default value is zero, which generates images at the asset’s unscaled dimensions.
    @available(visionOS, unavailable)
    @inlinable
    func firstFrame(maximumSize: CGSize = .zero) async throws -> CGImage {
        let imageGenerator = AVAssetImageGenerator(asset: self)
        imageGenerator.maximumSize = maximumSize
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
    
    /// Returns the estimated frame count for the primary video track.
    ///
    /// This uses track timing and nominal frame rate metadata without decoding frames.
    /// For variable-frame-rate sources, this value may still be an estimate.
    var frameCount: Int {
        get async throws {
            guard let video = try await self.loadTracks(withMediaType: .video).first else { throw GenerateFramesStreamError.assetNotVideo }

            let duration = try await video.load(.timeRange).duration
            guard duration.isNumeric,
                  duration.timescale != 0,
                  duration.value > 0 else { return 0 }

            let nominalFrameRate = try await video.load(.nominalFrameRate)

            if nominalFrameRate > 0 {
                // Compute using CMTime components to avoid floating-point precision loss.
                let rawCount = Double(duration.value) * Double(nominalFrameRate) / Double(duration.timescale)
                return max(Int(rawCount.rounded(.toNearestOrAwayFromZero)), 0)
            }

            let minFrameDuration = try await video.load(.minFrameDuration)
            guard minFrameDuration.isNumeric,
                  minFrameDuration.timescale != 0,
                  minFrameDuration.value > 0 else { return 0 }

            let frameDurationSeconds = Double(minFrameDuration.value) / Double(minFrameDuration.timescale)
            guard frameDurationSeconds > 0 else { return 0 }

            let rawCount = duration.seconds / frameDurationSeconds
            return max(Int(rawCount.rounded(.toNearestOrAwayFromZero)), 0)
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
}
#endif
