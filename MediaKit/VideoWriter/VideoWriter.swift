//
//  VideoWriter.swift
//
//
//  Created by Vaida on 11/23/24.
//

import AVFoundation
import VideoToolbox
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
    
    let colorSpace: ColorSpace
    
    static var hasShownConvertWarning: Bool = false

    /// Creates a video writer.
    ///
    /// Video write is in `Rec.709` colorspace, unless `colorSpace` says otherwise.
    ///
    /// Transparency is only recorded when codec is `ProRess4444`.
    ///
    /// - Parameters:
    ///   - size: The resulting video size.
    ///   - frameRate: The resulting video frame rate.
    ///   - destination: The resulting video location.
    ///   - container: The file format.
    ///   - codec: The codec used.
    ///   - colorSpace: The color space of the video. The default is `SDR`. `HDR` writes 10-bit HLG in `Rec.2020`, and needs the HEVC codec and the `CVPixelBuffer` pipeline, see ``ColorSpace``.
    ///
    /// - Throws: ``WriteError/hdrRequiresHEVC`` when `colorSpace` is `HDR` and `codec` is not HEVC. Nothing is written, or removed, then.
    public init(size: CGSize, frameRate: Int, to destination: FinderItem, container: AVFileType = .mov, codec: AVVideoCodecType = .hevc, colorSpace: ColorSpace = .SDR) throws {
        guard frameRate > 0 else { throw WriteError.invalidFrameRate(frameRate) }
        if colorSpace == .HDR { guard codec == .hevc else { throw WriteError.hdrRequiresHEVC } }
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

        var videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight,
            AVVideoColorPropertiesKey: colorSpace.colorProperties
        ]
        if let compressionProperties = colorSpace.compressionProperties {
            videoSettings[AVVideoCompressionPropertiesKey] = compressionProperties
        }

        self.assetWriterVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        self.colorSpace = colorSpace
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
        /// `HDR` is 10-bit, and only the HEVC codec writes it.
        case hdrRequiresHEVC
        /// `HDR` needs the half-float frames of the `CVPixelBuffer` pipeline, which a `CGImage` cannot be.
        case hdrNotSupportedForImages

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
            case .hdrRequiresHEVC:
                "HDR video is 10-bit, which only the HEVC codec writes here. Use `.hevc`, or write SDR."
            case .hdrNotSupportedForImages:
                "HDR video cannot be written from `CGImage`s, which are 8-bit. Use the `CVPixelBuffer` overload of `startWriting`."
            }
        }

    }
    
    
    /// The color space of the video, and with it the format of the frames the writer asks for.
    ///
    /// | | `SDR` | `HDR` |
    /// |---|---|---|
    /// | Video | 8-bit, `Rec.709` | 10-bit HEVC Main10, `Rec.2020` primaries, HLG |
    /// | Frame buffers | `kCVPixelFormatType_32BGRA`, sRGB | `kCVPixelFormatType_64RGBAHalf` |
    /// | Pipelines | `CVPixelBuffer` and `CGImage` | `CVPixelBuffer` only |
    ///
    /// An `HDR` frame is not light, it is the HLG *signal*: the non-linear `R'G'B'` of BT.2100, from `0` to `1`, in `Rec.2020` primaries, with an alpha of `1`. `1` is the top of the signal, 1000 nits of peak, and SDR white sits at about `0.75`. The writer tags every buffer it hands to `yield` as `Rec.2020`, HLG, with the `Rec.2020` matrix. It converts the buffer to 10-bit `YCbCr` on its own, and the tags tell it that the values are already encoded. A buffer that lost its tags is converted as the wrong color.
    public enum ColorSpace: Hashable, Sendable, BitwiseCopyable, CaseIterable {
        case SDR
        /// HDR with HLG, as 10-bit HEVC Main10. See the table above for what the frames are.
        case HDR
        
        
        var colorProperties: [String: Any] {
            switch self {
            case .SDR:
                [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
                ]
            case .HDR:
                [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020
                ]
            }
        }
        
        /// What the encoder is told beyond the color. `HDR` is 10-bit, so it needs the Main10 profile.
        var compressionProperties: [String: Any]? {
            switch self {
            case .SDR: nil
            case .HDR: [AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String]
            }
        }
        
        var pixelFormatType: OSType {
            switch self {
            case .SDR: kCVPixelFormatType_32BGRA
            case .HDR: kCVPixelFormatType_64RGBAHalf
            }
        }
        
        /// Tells the converter what the values in the buffer are. `SDR` buffers are left as they are.
        func tag(_ pixelBuffer: CVPixelBuffer) {
            switch self {
            case .SDR:
                break
            case .HDR:
                CVBufferSetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_2020, .shouldPropagate)
                CVBufferSetAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_2100_HLG, .shouldPropagate)
                CVBufferSetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_2020, .shouldPropagate)
            }
        }
    }

}
