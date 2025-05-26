//
//  AVAssetTrack Ex.swift
//  MediaKit
//
//  Created by Vaida on 2025-05-26.
//

import AVFoundation


extension AVAssetTrack {
    
    var formatDescription: CMFormatDescription? {
        get async throws {
            try await self.load(.formatDescriptions).first
        }
    }
    
}
