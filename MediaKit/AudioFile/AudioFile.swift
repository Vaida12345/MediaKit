//
//  AudioFile.swift
//  MediaKit
//
//  Created by Vaida on 2025-05-26.
//

import AVFoundation
import FinderItem


public struct AudioFile: Sendable {
    
    public let asset: AVURLAsset
    
    @inlinable
    public var source: FinderItem {
        FinderItem(at: self.asset.url)
    }
    
    @inlinable
    public init(at source: FinderItem) {
        self.asset = AVURLAsset(url: source.url)
    }
    
}

