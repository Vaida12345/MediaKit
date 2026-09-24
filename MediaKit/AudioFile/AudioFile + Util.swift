//
//  AudioFile + Util.swift
//  MediaKit
//
//  Created by Vaida on 2025-05-26.
//

import Essentials
import AVFoundation


extension AudioFile {
    
    /// Converts an Audio File Services error into a descriptive read error.
    public static func parseReadError(_ error: NSError) -> ParsedReadError? {
        guard error.domain == NSOSStatusErrorDomain || error.domain == "com.apple.coreaudio.avaudio" else { return nil }
        
        switch Int32(error.code) {
        case kAudioFileUnspecifiedError:
            return .unspecified
        case kAudioFileUnsupportedFileTypeError:
            return .unsupportedFileType
        case kAudioFileUnsupportedDataFormatError:
            return .unsupportedDataFormat
        case kAudioFileUnsupportedPropertyError:
            return .unsupportedProperty
        case kAudioFileBadPropertySizeError:
            return .invalidPropertySize
        case kAudioFilePermissionsError:
            return .permissionDenied
        case kAudioFileNotOptimizedError:
            return .notOptimized
        case kAudioFileInvalidChunkError:
            return .invalidChunk
        case kAudioFileDoesNotAllow64BitDataSizeError:
            return .fileSizeLimitExceeded
        case kAudioFileInvalidPacketOffsetError:
            return .invalidPacketOffset
        case kAudioFileInvalidPacketDependencyError:
            return .invalidPacketDependency
        case kAudioFileInvalidFileError:
            return .invalidFile
        case kAudioFileOperationNotSupportedError:
            return .unsupportedOperation
        case kAudioFileNotOpenError:
            return .fileNotOpen
        case kAudioFileEndOfFileError:
            return .endOfFile
        case kAudioFilePositionError:
            return .invalidFilePosition
        case kAudioFileFileNotFoundError:
            return .fileNotFound
        default:
            return nil
        }
    }
    
    public enum ParsedReadError: GenericError {
        case unspecified
        case unsupportedFileType
        case unsupportedDataFormat
        case unsupportedProperty
        case invalidPropertySize
        case permissionDenied
        case notOptimized
        case invalidChunk
        case fileSizeLimitExceeded
        case invalidPacketOffset
        case invalidPacketDependency
        case invalidFile
        case unsupportedOperation
        case fileNotOpen
        case endOfFile
        case invalidFilePosition
        case fileNotFound
        
        
        private var messageResource: LocalizedStringResource {
            switch self {
            case .unspecified:
                "The audio file couldn’t be read because an unexpected error occurred."
            case .unsupportedFileType:
                "The audio file couldn’t be read because its file type isn’t supported."
            case .unsupportedDataFormat:
                "The audio file couldn’t be read because its audio format isn’t supported by this file type."
            case .unsupportedProperty:
                "The audio file couldn’t be read because it contains an unsupported property."
            case .invalidPropertySize:
                "The audio file couldn’t be read because a property has an invalid size."
            case .permissionDenied:
                "The audio file couldn’t be read because access wasn’t permitted."
            case .notOptimized:
                "The audio file couldn’t be read because its audio data isn’t arranged for this operation."
            case .invalidChunk:
                "The audio file couldn’t be read because a required data chunk is missing or unsupported."
            case .fileSizeLimitExceeded:
                "The audio file couldn’t be read because it exceeds the size limit for its file type."
            case .invalidPacketOffset:
                "The audio file couldn’t be read because its packet positions are invalid or corrupted."
            case .invalidPacketDependency:
                "The audio file couldn’t be read because its packet dependency information is invalid."
            case .invalidFile:
                "The audio file couldn’t be read because it is malformed or doesn’t match its file type."
            case .unsupportedOperation:
                "The audio file couldn’t be read because the requested operation isn’t supported."
            case .fileNotOpen:
                "The audio file couldn’t be read because it isn’t open."
            case .endOfFile:
                "The audio file couldn’t be read because the end of the file was reached."
            case .invalidFilePosition:
                "The audio file couldn’t be read because the requested file position is invalid."
            case .fileNotFound:
                "The audio file couldn’t be read because it couldn’t be found."
            }
        }
        
        public var message: String {
            self.messageResource.packageLocalized()
        }
    }
    
}


extension LocalizedStringResource {
    
    /// Creates the localized String.
    func packageLocalized() -> String {
        let localizedResource = LocalizedStringResource(
            self.defaultValue,
            table: self.table,
            locale: self.locale,
            bundle: .module
        )
        return String(localized: localizedResource)
    }
    
}


