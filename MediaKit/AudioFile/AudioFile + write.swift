//
//  AudioFile + write.swift
//  MediaKit
//
//  Created by Vaida on 2025-05-26.
//

import Essentials
import AVFoundation
import FinderItem


extension AudioFile {
    
    public enum Codec: String, Identifiable, CaseIterable, Sendable, Equatable, Hashable, Codable {
        case appleLossless
        case aac
        case linearPCM
        
        @inlinable
        public var id: AudioFormatID {
            switch self {
            case .appleLossless: kAudioFormatAppleLossless
            case .aac: kAudioFormatMPEG4AAC
            case .linearPCM: kAudioFormatLinearPCM
            }
        }
        
        @inlinable
        public var fileTypes: [AVFileType] {
            switch self {
            case .appleLossless: [.m4a, .caf]
            case .aac: [.m4a, .caf, .mp4]
            case .linearPCM: [.wav, .aiff, .aifc, .caf]
            }
        }
    }
    
    
    public enum ExportError: LocalizableError {
        case sourceNoAudioTrack
        
        @inlinable
        public var titleResource: LocalizedStringResource? {
            "Audio Export Error"
        }
        
        @inlinable
        public var messageResource: LocalizedStringResource {
            switch self {
            case .sourceNoAudioTrack:
                "The source file does not have an audio track."
            }
        }
    }
    
    
    public func export(
        to destination: FinderItem,
        codec: Codec,
        fileType: AVFileType,
        metadata: [AVMetadataItem] = []
    ) async throws {
        precondition(codec.fileTypes.contains(fileType), "Invalid codec and fileType combination")
        guard !destination.exists else { throw FinderItem.FileError(code: .cannotWrite(reason: .fileExists), source: destination) }
        
        // 1. Load the asset
        let asset = self.asset
        
        // 2. Make sure there’s at least one audio track
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ExportError.sourceNoAudioTrack
        }
        
        // 3. Set up AVAssetReader
        nonisolated(unsafe)
        let reader = try AVAssetReader(asset: asset)
        let formatDescriptions = try await audioTrack.load(.formatDescriptions).first!
        
        let bitDepth = formatDescriptions.audioStreamBasicDescription!.mBitsPerChannel
        
        // 4. Configure reader output to give us uncompressed PCM
        //    (so the writer can re-encode it to ALAC)
        let pcmOutputSettings: [String: Any] = [
            AVFormatIDKey:            kAudioFormatLinearPCM,
            AVSampleRateKey:          formatDescriptions.audioStreamBasicDescription!.mSampleRate,
            AVNumberOfChannelsKey:    formatDescriptions.audioChannelLayout!.numberOfChannels,
            AVLinearPCMBitDepthKey:   bitDepth == 0 ? 32 : bitDepth,
            AVLinearPCMIsFloatKey:    false,
            AVLinearPCMIsBigEndianKey:false,
            AVLinearPCMIsNonInterleaved: false
        ]
        nonisolated(unsafe)
        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: pcmOutputSettings)
        reader.add(trackOutput)
        
        
        // 5. Set up AVAssetWriter
        //    We'll wrap ALAC in an .m4a container
        nonisolated(unsafe)
        let writer = try AVAssetWriter(outputURL: destination.url, fileType: fileType)
        writer.metadata = metadata.isEmpty ? try await self.asset.load(.metadata) : metadata
        
        // 6. Configure writer input to produce ALAC
        var outputSettings: [String: Any] = [
            AVFormatIDKey:               codec.id,
            AVSampleRateKey:             formatDescriptions.audioStreamBasicDescription!.mSampleRate,
            AVNumberOfChannelsKey:       formatDescriptions.audioChannelLayout!.numberOfChannels,
        ]
        
        switch codec {
        case .appleLossless:
            outputSettings[AVEncoderBitDepthHintKey] = bitDepth == 0 ? 32 : bitDepth
        case .linearPCM:
            outputSettings[AVLinearPCMIsBigEndianKey] = fileType != .wav
            outputSettings[AVLinearPCMIsFloatKey] = false
            outputSettings[AVLinearPCMBitDepthKey] = bitDepth == 0 ? 32 : bitDepth
            outputSettings[AVLinearPCMIsNonInterleaved] = false
        default:
            break
        }
        
        nonisolated(unsafe)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)
        
        
        // 7. Start reading / writing
        writer.startWriting()
        reader.startReading()
        writer.startSession(atSourceTime: .zero)
        
        // 8. Pump samples from reader to writer
        let queue = DispatchQueue(label: "package.MediaKit.AudioFile.export")
        return try await withCheckedThrowingContinuation { continuation in
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    if let sampleBuffer = trackOutput.copyNextSampleBuffer() {
                        writerInput.append(sampleBuffer)
                    } else {
                        // no more samples
                        writerInput.markAsFinished()
                        writer.finishWriting {
                            if writer.status == .completed {
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: writer.error!)
                            }
                        }
                        reader.cancelReading()
                        break
                    }
                }
            }
        }
    }
    
}


extension AVFileType {
    
    /// Preferred extension name for the given file type.
    @inlinable
    public var `extension`: String {
        switch self {
        case .AHAP: "ahap"
        case .SCC: "scc"
        case .ac3: "ac3"
        case .aifc: "aifc"
        case .aiff: "aiff"
        case .appleiTT: "itt"
        case .au: "au"
        case .avci: "avci"
        case .caf: "caf"
        case .dng: "dng"
        case .eac3: "eac3"
        case .heic: "heic"
        case .heif: "heif"
        case .jpg: "jpg"
        case .m4a: "m4a"
        case .m4v: "m4v"
        case .mobile3GPP: "3gp"
        case .mobile3GPP2: "3g2"
        case .mov: "mov"
        case .mp3: "mp3"
        case .mp4: "mp4"
        case .tif: "tif"
        case .wav: "wav"
        default:
            fatalError()
        }
    }
    
}
