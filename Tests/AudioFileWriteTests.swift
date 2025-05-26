//
//  AudioFileWriteTests.swift
//  MediaKit
//
//  Created by Vaida on 2025-05-26.
//

import AVFoundation
import Testing
import MediaKit
import FinderItem


@Suite(.serialized)
struct AudioFileWriteTests {
    
    let source = AudioFile(at: "/Users/vaida/DataBase/Swift Package/Test Reference/MediaKit/The City in the Night.m4a")
    
    
    func write(codec: AudioFile.Codec, fileType: AVFileType) async throws {
        let destFolder: FinderItem = "/Users/vaida/DataBase/Swift Package/Test Reference/MediaKit"
        let destination = destFolder/"\(codec.rawValue).\(fileType.extension)"
        try destination.removeIfExists()
        try await source.export(to: destination, codec: codec, fileType: fileType)
    }
    
    @Test(arguments: AudioFile.Codec.allCases)
    func write(codec: AudioFile.Codec) async throws {
        for fileType in codec.fileTypes {
            try await self.write(codec: codec, fileType: fileType)
        }
    }
    
}
