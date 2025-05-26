//
//  AudioFile + Metadata.swift
//  MediaKit
//
//  Created by Vaida on 2025-05-26.
//

import NativeImage
import SwiftFLAC
import AVFoundation


extension AudioFile {
    
    /// A set of common meta data for UI frameworks.
    public struct Metadata: @unchecked Sendable {
        
        public var title: String?
        
        public var artist: String?
        
        public var cover: NativeImage?
        
        @inlinable
        public init(title: String? = nil, artist: String? = nil, cover: NativeImage? = nil) {
            self.title = title
            self.artist = artist
            self.cover = cover
        }
    }
    
    
    public func metadata() async throws -> sending Metadata {
        if self.source.extension == "flac" {
            let container = try FLACContainer(at: self.source.url, options: .decodeMetadataOnly)
            let metadata = container.metadata

            let title = metadata.vorbisComment?.title
            let artist = metadata.vorbisComment?.artist ?? metadata.vorbisComment?.albumArtist
            let image = metadata.pictures.compactMap({ NativeImage(data: $0.data) }).first
            
            return Metadata(title: title, artist: artist, cover: image)
        } else {
            guard let metadata = try? await asset.load(.metadata) else { return Metadata() }
            
            let title = try? await AVMetadataItem.metadataItems(from: metadata, withKey: AVMetadataKey.commonKeyTitle, keySpace: .common).first?.load(.stringValue)
            let artist = try? await AVMetadataItem.metadataItems(from: metadata, withKey: AVMetadataKey.commonKeyArtist, keySpace: .common).first?.load(.stringValue)
            let imageData = try? await AVMetadataItem.metadataItems(from: metadata, withKey: AVMetadataKey.commonKeyArtwork, keySpace: .common).first?.load(.dataValue)
            let image = imageData.flatMap({ NativeImage(data: $0) })
            
            return Metadata(title: title, artist: artist, cover: image)
        }
    }
    
}
