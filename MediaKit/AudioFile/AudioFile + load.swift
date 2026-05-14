//
//  AudioFile + load.swift
//  MediaKit
//
//  Created by Vaida on 2025-05-26.
//

import FinderItem
import AVFoundation


extension FinderItem.LoadableContent {
    
    @inlinable
    public static var audioFile: FinderItem.LoadableContent<AudioFile, any Error> {
        .init { source in
            AudioFile(at: source)
        }
    }
    
}

extension FinderItem.AsyncLoadableContent {
    
    @inlinable
    public static var avAsset: FinderItem.AsyncLoadableContent<AVURLAsset, any Error> {
        .init { source in
            guard let asset = await AVURLAsset(at: source) else { throw FinderItem.FileError(code: .cannotRead(reason: .corruptFile), source: source) }
            return asset
        }
    }
    
}
