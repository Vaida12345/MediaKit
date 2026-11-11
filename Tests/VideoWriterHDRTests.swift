//
//  VideoWriterHDRTests.swift
//  MediaKit
//
//  Created by Vaida on 2026-11-11.
//

import AVFoundation
import CoreMedia
import FinderItem
import Foundation
import Synchronization
import Testing
@testable import MediaKit


#if arch(arm64) // the HDR frames are half floats, which Intel Macs do not have in Swift
/// `HDR` writes 10-bit HLG in Rec. 2020 from half-float frames, and `SDR` stays as it was.
///
/// The videos are written to `$TMPDIR` and removed afterwards. Both write paths run on every system.
@Suite(.serialized)
struct VideoWriterHDRTests {

    private static let paths: [Path] = {
        if #available(iOS 26.0, macOS 26.0, visionOS 26, *) { [.pre26, .post26] } else { [.pre26] }
    }()

    enum Path: String, CustomTestStringConvertible, Sendable {
        case pre26, post26
        var testDescription: String { rawValue }
    }

    /// The HLG signal of each frame, as `R'G'B'` from 0 to 1. Flat frames, so that a lossy encoder is close to exact.
    private static let signals: [(Double, Double, Double)] = [
        (0, 0, 0), (0.25, 0.25, 0.25), (0.5, 0.5, 0.5), (0.75, 0.75, 0.75), (1, 1, 1),
        (0.2, 0.4, 0.8), (0.9, 0.3, 0.1), (0.1, 0.8, 0.3),
    ]


    // MARK: - The file

    @Test(arguments: paths)
    func anHDRClipIsTenBitHLGInRec2020(path: Path) async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("hdr.mov")
            let writer = try VideoWriter(size: CGSize(width: 256, height: 144), frameRate: 10, to: FinderItem(at: url), colorSpace: .HDR)
            try await write(writer, path: path) { index, pixelBuffer in
                guard index < Self.signals.count else { return false }
                fillHalf(pixelBuffer, with: Self.signals[index])
                return true
            }

            let format = try await videoFormat(of: url)
            #expect(format.transfer == "\(AVVideoTransferFunction_ITU_R_2100_HLG)", "transfer: \(format.transfer ?? "nil")")
            #expect(format.primaries == "\(AVVideoColorPrimaries_ITU_R_2020)", "primaries: \(format.primaries ?? "nil")")
            #expect(format.matrix == "\(AVVideoYCbCrMatrix_ITU_R_2020)", "matrix: \(format.matrix ?? "nil")")
            #expect(format.bitsPerComponent == 10, "bits: \(format.bitsPerComponent.map(String.init) ?? "nil")")
            #expect(format.hevcProfile == 2, "HEVC profile \(format.hevcProfile.map(String.init) ?? "nil"), where 2 is Main10")
        }
    }

    @Test(arguments: paths)
    func theFramesAreTheSignalThatWasGiven(path: Path) async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("signal.mov")
            let writer = try VideoWriter(size: CGSize(width: 256, height: 144), frameRate: 10, to: FinderItem(at: url), colorSpace: .HDR)
            try await write(writer, path: path) { index, pixelBuffer in
                guard index < Self.signals.count else { return false }
                fillHalf(pixelBuffer, with: Self.signals[index])
                return true
            }

            // The buffer holds a signal that is already encoded, so the writer only applies the Rec. 2020 matrix, and the video range.
            let decoded = try await decodedCodes(of: url)
            try #require(decoded.count == Self.signals.count)
            for (index, signal) in Self.signals.enumerated() {
                let expected = Self.codes(of: signal)
                let actual = decoded[index]
                #expect(abs(Double(actual.y) - expected.y) <= 3, "frame \(index), luma \(actual.y), expected \(expected.y)")
                #expect(abs(Double(actual.cb) - expected.cb) <= 3, "frame \(index), Cb \(actual.cb), expected \(expected.cb)")
                #expect(abs(Double(actual.cr) - expected.cr) <= 3, "frame \(index), Cr \(actual.cr), expected \(expected.cr)")
            }
        }
    }

    /// BT.2020, non-constant luminance, video range, 10-bit codes.
    private static func codes(of signal: (Double, Double, Double)) -> (y: Double, cb: Double, cr: Double) {
        let (r, g, b) = signal
        let y = 0.2627 * r + 0.6780 * g + 0.0593 * b
        return (64 + 876 * y, 512 + 896 * (b - y) / 1.8814, 512 + 896 * (r - y) / 1.4746)
    }

    @Test(arguments: paths)
    func anSDRClipIsStillEightBitRec709(path: Path) async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("sdr.mov")
            let writer = try VideoWriter(size: CGSize(width: 256, height: 144), frameRate: 10, to: FinderItem(at: url))
            try await write(writer, path: path) { index, pixelBuffer in
                guard index < 3 else { return false }
                fillBGRA(pixelBuffer, gray: UInt8(60 * (index + 1)))
                return true
            }

            let format = try await videoFormat(of: url)
            #expect(format.transfer == "\(AVVideoTransferFunction_ITU_R_709_2)", "transfer: \(format.transfer ?? "nil")")
            #expect(format.primaries == "\(AVVideoColorPrimaries_ITU_R_709_2)", "primaries: \(format.primaries ?? "nil")")
            #expect(format.matrix == "\(AVVideoYCbCrMatrix_ITU_R_709_2)", "matrix: \(format.matrix ?? "nil")")
            #expect(format.hevcProfile == 1, "HEVC profile \(format.hevcProfile.map(String.init) ?? "nil"), where 1 is Main")
        }
    }


    // MARK: - What the writer hands over

    @Test(arguments: paths)
    func anHDRBufferIsHalfFloatAndTaggedWhenItReachesYield(path: Path) async throws {
        try await withTemporaryDirectory { directory in
            let writer = try VideoWriter(size: CGSize(width: 324, height: 180), frameRate: 10, to: FinderItem(at: directory.appendingPathComponent("contract.mov")), colorSpace: .HDR)
            let found = Mutex<[String]?>(nil)
            try await write(writer, path: path) { index, pixelBuffer in
                if index == 0 {
                    var problems: [String] = []
                    if CVPixelBufferGetPixelFormatType(pixelBuffer) != kCVPixelFormatType_64RGBAHalf { problems.append("it is not 64RGBAHalf") }
                    if CVPixelBufferGetIOSurface(pixelBuffer) == nil { problems.append("it is not IOSurface-backed") }
                    if CVPixelBufferGetBytesPerRow(pixelBuffer) < 324 * 8 { problems.append("its rows are shorter than the pixels in them") }
                    func attachment(_ key: CFString) -> String? { CVBufferCopyAttachment(pixelBuffer, key, nil).map { "\($0)" } }
                    if attachment(kCVImageBufferTransferFunctionKey) != "\(kCVImageBufferTransferFunction_ITU_R_2100_HLG)" { problems.append("it is not tagged HLG") }
                    if attachment(kCVImageBufferColorPrimariesKey) != "\(kCVImageBufferColorPrimaries_ITU_R_2020)" { problems.append("it is not tagged Rec. 2020") }
                    if attachment(kCVImageBufferYCbCrMatrixKey) != "\(kCVImageBufferYCbCrMatrix_ITU_R_2020)" { problems.append("it has no Rec. 2020 matrix") }
                    found.withLock { $0 = problems }
                }
                fillHalf(pixelBuffer, with: (0.5, 0.5, 0.5))
                return index < 2
            }
            #expect(found.withLock { $0 } == [], "\(found.withLock { $0 } ?? ["yield was never called"])")
        }
    }


    // MARK: - What the writer refuses

    @Test(arguments: [AVVideoCodecType.h264, .proRes422])
    func anHDRWriterNeedsHEVC(codec: AVVideoCodecType) async throws {
        try await withTemporaryDirectory { directory in
            // It is refused before the old file is thrown away.
            let url = directory.appendingPathComponent("existing.mov")
            let original = Data("the previous render".utf8)
            try original.write(to: url)

            #expect(throws: VideoWriter.WriteError.hdrRequiresHEVC) {
                try VideoWriter(size: CGSize(width: 256, height: 144), frameRate: 10, to: FinderItem(at: url), codec: codec, colorSpace: .HDR)
            }
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test func anSDRWriterStillTakesAnyCodec() throws {
        try withTemporaryDirectoryNow { directory in
            _ = try VideoWriter(size: CGSize(width: 256, height: 144), frameRate: 10, to: FinderItem(at: directory.appendingPathComponent("h264.mov")), codec: .h264)
        }
    }

    @Test func anHDRWriterRefusesImages() async throws {
        try await withTemporaryDirectory { directory in
            let writer = try VideoWriter(size: CGSize(width: 256, height: 144), frameRate: 10, to: FinderItem(at: directory.appendingPathComponent("images.mov")), colorSpace: .HDR)
            let asked = Mutex(false)
            await #expect(throws: VideoWriter.WriteError.hdrNotSupportedForImages) {
                try await writer.startWriting { _ in
                    asked.withLock { $0 = true }
                    return nil
                }
            }
            #expect(!asked.withLock { $0 }, "no frame should have been asked for")
        }
    }

}


// MARK: - Machinery

private func withTemporaryDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
    let base = ProcessInfo.processInfo.environment["TMPDIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
    let directory = base.appendingPathComponent("MediaKitHDRTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try await body(directory)
}

private func withTemporaryDirectoryNow<T>(_ body: (URL) throws -> T) throws -> T {
    let base = ProcessInfo.processInfo.environment["TMPDIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
    let directory = base.appendingPathComponent("MediaKitHDRTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
}

/// Runs the `CVPixelBuffer` overload on the given path.
private func write(_ writer: VideoWriter, path: VideoWriterHDRTests.Path, yield: @escaping VideoWriter.CVPixelBufferYield) async throws {
    switch path {
    case .pre26:
        try await writer.startWriting_pre26(yield: yield)
    case .post26:
        guard #available(iOS 26.0, macOS 26.0, visionOS 26, *) else { preconditionFailure("The post-26 path cannot run on this system.") }
        try await writer.startWriting_post26(yield: yield)
    }
}

/// Fills a `64RGBAHalf` buffer with one color and an alpha of 1, row by row, so that the stride is honored.
private func fillHalf(_ pixelBuffer: CVPixelBuffer, with color: (Double, Double, Double)) {
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let pixel: [Float16] = [Float16(color.0), Float16(color.1), Float16(color.2), Float16(1)]
    for row in 0 ..< height {
        let values = (base + row * stride).assumingMemoryBound(to: Float16.self)
        for column in 0 ..< width {
            for channel in 0 ..< 4 { values[column * 4 + channel] = pixel[channel] }
        }
    }
}

/// Fills a `32BGRA` buffer with one gray.
private func fillBGRA(_ pixelBuffer: CVPixelBuffer, gray: UInt8) {
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

    let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
    for row in 0 ..< CVPixelBufferGetHeight(pixelBuffer) {
        let bytes = (base + row * stride).assumingMemoryBound(to: UInt8.self)
        for column in 0 ..< CVPixelBufferGetWidth(pixelBuffer) {
            bytes[column * 4] = gray; bytes[column * 4 + 1] = gray; bytes[column * 4 + 2] = gray; bytes[column * 4 + 3] = 255
        }
    }
}

/// What the file says about its video.
private struct VideoFormat {
    var transfer: String?
    var primaries: String?
    var matrix: String?
    var bitsPerComponent: Int?
    /// The `general_profile_idc` of the HEVC parameters, 1 for Main and 2 for Main10.
    var hevcProfile: Int?
}

private func videoFormat(of url: URL) async throws -> VideoFormat {
    let asset = AVURLAsset(url: url)
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first, "the file has no video track")
    let description = try #require(try await track.load(.formatDescriptions).first)
    let extensions = CMFormatDescriptionGetExtensions(description) as? [String: Any] ?? [:]

    var format = VideoFormat()
    format.transfer = extensions[kCMFormatDescriptionExtension_TransferFunction as String].map { "\($0)" }
    format.primaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries as String].map { "\($0)" }
    format.matrix = extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String].map { "\($0)" }
    format.bitsPerComponent = (extensions[kCMFormatDescriptionExtension_BitsPerComponent as String] as? NSNumber)?.intValue
    if let atoms = extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String] as? [String: Any],
       let hvcC = atoms["hvcC"] as? Data, hvcC.count > 1 {
        format.hevcProfile = Int(hvcC[1] & 0x1F)
    }
    return format
}

/// The luma and chroma codes at the center of every frame, decoded as 10-bit video range, in presentation order.
private func decodedCodes(of url: URL) async throws -> [(y: Int, cb: Int, cr: Int)] {
    let asset = AVURLAsset(url: url)
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange])
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadUnknown) }

    var codes: [(y: Int, cb: Int, cr: Int)] = []
    while let sample = output.copyNextSampleBuffer() {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let lumaRow = (CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)! + (height / 2) * CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)).assumingMemoryBound(to: UInt16.self)
        let chromaRow = (CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)! + (height / 4) * CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)).assumingMemoryBound(to: UInt16.self)
        // The codes are in the top 10 bits of each 16-bit word.
        codes.append((Int(lumaRow[width / 2] >> 6), Int(chromaRow[(width / 4) * 2] >> 6), Int(chromaRow[(width / 4) * 2 + 1] >> 6)))
    }
    return codes
}
#endif
