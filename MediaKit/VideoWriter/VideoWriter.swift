//
//  VideoWriter.swift
//
//
//  Created by Vaida on 11/23/24.
//

import AVFoundation
import Foundation
import FinderItem
import Essentials


/// A video writer for writing a stream of images.
///
/// - Experiment: It is best not to have writers run in parallel.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, *)
public final class VideoWriter: @unchecked Sendable {

    let assetWriter: AVAssetWriter

    let assetWriterVideoInput: AVAssetWriterInput

    let size: CGSize

    let destination: FinderItem

    let frameRate: Int

    let queue = DispatchQueue(label: "dev.vaida.mediakit.VideoWriter-mediaQueue")
    
    static var hasShownConvertWarning: Bool = false

    /// Creates a video writer.
    ///
    /// Video write is in `Rec.709` colorspace.
    ///
    /// Transparency is only recorded when codec is `ProRess4444`.
    ///
    /// - Parameters:
    ///   - size: The resulting video size.
    ///   - frameRate: The resulting video frame rate.
    ///   - destination: The resulting video location.
    ///   - container: The file format.
    ///   - codec: The codec used.
    public init(size: CGSize, frameRate: Int, to destination: FinderItem, container: AVFileType = .mov, codec: AVVideoCodecType = .hevc) throws {
        guard frameRate > 0 else { throw WriteError.invalidFrameRate(frameRate) }
        if codec == .hevc {
            guard size.width <= 8192 && size.height <= 4320 else { throw WriteError.videoSizeTooLarge(size) }
        }

        self.size = size
        self.frameRate = frameRate
        self.destination = destination

        let videoWidth = size.width
        let videoHeight = size.height

        try destination.removeIfExists()

        self.assetWriter = try AVAssetWriter(outputURL: destination.url, fileType: container)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        ]

        self.assetWriterVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    }

    public enum WriteError: GenericError, Equatable {

        case pixelBufferPoolNil
        case pixelBufferBaseAddressNil
        case failedToCreatePixelBuffer(CVReturn)
        case failedToAppendFrame(Int)
        case failedToStartWriting(Int)
        case invalidAssetWriterState(Int)
        case invalidFrameRate(Int)
        case videoSizeTooLarge(CGSize)

        public var message: String {
            switch self {
            case .pixelBufferPoolNil:
                "Pixel buffer pool is nil after starting writing session, this typically means you do not have permission to write to the given file, or a file with the same name already exists."
            case .pixelBufferBaseAddressNil:
                "Failed to access the pixel buffer base address."
            case .failedToCreatePixelBuffer(let status):
                "Failed to create a pixel buffer from the pool. Status: \(status)."
            case .failedToAppendFrame(let index):
                "Failed to append frame at index \(index) to the asset writer input."
            case .failedToStartWriting(let status):
                "AVAssetWriter failed to start writing. Status: \(status)."
            case .invalidAssetWriterState(let state):
                "VideoWriter is in an invalid state for startWriting. AVAssetWriter status: \(state)."
            case .invalidFrameRate(let frameRate):
                "Frame rate must be greater than zero. Received \(frameRate)."
            case .videoSizeTooLarge(let size):
                "HEVC codec supports the resolutions up to 8192×4320, the given size, \(Int(size.width))×\(Int(size.height)), is too large"
            }
        }

    }

}
