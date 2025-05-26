//
//  AudioFile + load.swift
//  MediaKit
//
//  Created by Vaida on 2025-05-26.
//

import FinderItem


extension FinderItem.LoadableContent {
    
    @inlinable
    public static var audioFile: FinderItem.LoadableContent<AudioFile, any Error> {
        .init { source in
            AudioFile(at: source)
        }
    }
    
}
