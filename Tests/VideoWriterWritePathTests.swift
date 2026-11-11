//
//  VideoWriterWritePathTests.swift
//  MediaKit
//
//  Created by Vaida on 2026-11-11.
//

import AVFoundation
import FinderItem
import Foundation
import Synchronization
import Testing
@testable import MediaKit


/// Runs both implementations behind `VideoWriter.startWriting`, the one used before iOS 26 / macOS 26 and the one using the receiver API introduced with them, for both the `CVPixelBuffer` and the `CGImage` overloads, on every system.
///
/// The videos are written to `$TMPDIR` and removed afterwards. Run with `swift test --filter VideoWriterWritePathTests`.
///
/// A writer that never finishes is the failure these tests are written to catch, so every wait is bounded, and a writer that does not finish in time is reported as hung instead of blocking the test run.
@Suite(.serialized)
struct VideoWriterWritePathTests {

    /// The two implementations behind `startWriting`.
    enum WritePath: String, CaseIterable, CustomTestStringConvertible, Sendable {
        /// The one used before iOS 26, macOS 26, and visionOS 26, built on `requestMediaDataWhenReady`.
        case pre26
        /// The one using the pixel buffer receiver of iOS 26, macOS 26, and visionOS 26.
        case post26

        /// The paths that can run on the current system.
        static var available: [WritePath] {
            if #available(iOS 26.0, macOS 26.0, visionOS 26, *) {
                [.pre26, .post26]
            } else {
                [.pre26]
            }
        }

        var testDescription: String { rawValue }
    }

    /// How a test image is laid out, which decides how the `CGImage` overload takes its pixels.
    enum ImageCase: String, CaseIterable, CustomTestStringConvertible, Sendable {
        /// The layout of the writer's own buffers, with the same row stride: the pixels are copied as is.
        case copiedAsIs
        /// The layout of the writer's own buffers, but with a different row stride: the pixels are converted.
        case differentStride
        /// Another layout, RGBA with premultiplied alpha last: the pixels are converted.
        case differentLayout

        /// The widths are chosen so that the row stride of a `CGContext` equals that of a pixel buffer at 320, and does not at 324.
        var width: Int {
            switch self {
            case .copiedAsIs, .differentLayout: 320
            case .differentStride: 324
            }
        }

        var bitmapInfo: UInt32 {
            switch self {
            case .copiedAsIs, .differentStride: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            case .differentLayout: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            }
        }

        var testDescription: String { rawValue }
    }


    // MARK: - CVPixelBuffer overload

    /// Verifies the stream ends when `yield` returns `false`, after every index was requested once, in order.
    @Test(arguments: WritePath.available)
    func pixelBufferStopsWhenYieldReturnsFalse(path: WritePath) async throws {
        try await withTemporaryDirectory { directory in
            let (writer, url) = try makeWriter("stops", in: directory)
            let requested = Mutex<[Int]>([])
            let task = Task {
                try await writePixelBuffers(writer, path: path) { index, pixelBuffer in
                    requested.withLock { $0.append(index) }
                    guard index < 12 else { return false }
                    fill(pixelBuffer, gray: 128)
                    return true
                }
            }
            guard expectReturned(await waitForOutcome(of: task)) else { return }

            #expect(requested.withLock { $0 } == Array(0...12))
            let frames = try await quadrantsOfEachFrame(of: url)
            #expect(frames.count == 12)
        }
    }

    /// Verifies what `yield` writes into the buffer is what ends up in the video, frame by frame, in order, in the right channels, and in the right place, which the row stride decides.
    @Test(arguments: WritePath.available)
    func pixelBufferContentReachesFile(path: WritePath) async throws {
        try await withTemporaryDirectory { directory in
            // The width is chosen so that the rows of the buffer are padded, and the stride matters.
            let (writer, url) = try makeWriter("content", in: directory, size: CGSize(width: 324, height: 180))
            let task = Task {
                try await writePixelBuffers(writer, path: path) { index, pixelBuffer in
                    guard index < Quadrants.sequence.count else { return false }
                    fill(pixelBuffer, with: Quadrants.sequence[index])
                    return true
                }
            }
            guard expectReturned(await waitForOutcome(of: task)) else { return }

            expectFrames(try await quadrantsOfEachFrame(of: url))
        }
    }

    /// Verifies the buffer handed to `yield` is what the documentation of `startWriting(yield:)` says it is.
    @Test(arguments: WritePath.available)
    func pixelBufferMatchesDocumentedContract(path: WritePath) async throws {
        let size = CGSize(width: 324, height: 180)
        try await withTemporaryDirectory { directory in
            let (writer, _) = try makeWriter("contract", in: directory, size: size)
            let problems = Mutex<[String]?>(nil)
            let task = Task {
                try await writePixelBuffers(writer, path: path) { index, pixelBuffer in
                    if index == 0 {
                        var found: [String] = []
                        if CVPixelBufferGetPixelFormatType(pixelBuffer) != kCVPixelFormatType_32BGRA { found.append("it is not 32BGRA") }
                        if CVPixelBufferGetWidth(pixelBuffer) != Int(size.width) || CVPixelBufferGetHeight(pixelBuffer) != Int(size.height) { found.append("its size differs from the writer's") }
                        if CVPixelBufferGetIOSurface(pixelBuffer) == nil { found.append("it is not IOSurface-backed") }
                        if CVPixelBufferGetBaseAddress(pixelBuffer) != nil { found.append("it is locked") }
                        if CVPixelBufferGetBytesPerRow(pixelBuffer) < Int(size.width) * 4 { found.append("its rows are shorter than the pixels in them") }
                        problems.withLock { $0 = found }
                    }
                    return index < 2
                }
            }
            guard expectReturned(await waitForOutcome(of: task)) else { return }

            let found = problems.withLock { $0 }
            #expect(found != nil, "yield was never called")
            #expect(found == [], "the buffer passed to yield differs from the documented one: \(found ?? [])")
        }
    }

    /// Verifies an error thrown by `yield` is the error thrown by `startWriting`, and that no partial file is left behind.
    @Test(arguments: WritePath.available)
    func pixelBufferErrorFromYieldPropagates(path: WritePath) async throws {
        try await withTemporaryDirectory { directory in
            let (writer, url) = try makeWriter("error", in: directory)
            let task = Task {
                try await writePixelBuffers(writer, path: path) { index, pixelBuffer in
                    fill(pixelBuffer, gray: 100)
                    if index == 5 { throw TestError(index: index) }
                    return true
                }
            }
            guard case .threw(let error) = await waitForOutcome(of: task) else {
                Issue.record("the writer should have thrown the error of yield")
                return
            }
            #expect(error as? TestError == TestError(index: 5), "threw \(error)")
            #expect(!fileExists(url), "the partially written file should be removed")
        }
    }

    /// Verifies a task that is already canceled when it starts writing ends with `CancellationError`, instead of hanging.
    @Test(arguments: WritePath.available)
    func pixelBufferCanceledBeforeStartThrowsCancellation(path: WritePath) async throws {
        try await withTemporaryDirectory { directory in
            let (writer, url) = try makeWriter("precanceled", in: directory)
            let task = Task {
                _ = try? await Task.sleep(for: .seconds(60)) // returns as soon as the task is canceled
                try await writePixelBuffers(writer, path: path) { index, pixelBuffer in
                    fill(pixelBuffer, gray: 100)
                    return index < 30
                }
            }
            try await Task.sleep(for: .milliseconds(100))
            task.cancel()

            expectCancellation(await waitForOutcome(of: task))
            #expect(!fileExists(url), "the partially written file should be removed")
        }
    }

    /// Verifies canceling at arbitrary moments always ends the writer with `CancellationError`, and never hangs.
    @Test(arguments: WritePath.available)
    func pixelBufferCanceledWhileRunningThrowsCancellation(path: WritePath) async throws {
        try await withTemporaryDirectory { directory in
            for iteration in 0..<12 {
                let (writer, url) = try makeWriter("canceled-\(iteration)", in: directory)
                let task = Task {
                    try await writePixelBuffers(writer, path: path) { index, pixelBuffer in
                        fill(pixelBuffer, gray: UInt8(truncatingIfNeeded: index))
                        return index < 100_000
                    }
                }
                try await Task.sleep(for: .microseconds(Int.random(in: 0...40_000)))
                task.cancel()

                let result = await waitForOutcome(of: task)
                expectCancellation(result, "iteration \(iteration)")
                #expect(!fileExists(url), "iteration \(iteration) left the partially written file behind")
                if case .hung = result { return } // no point in waiting for the remaining iterations
            }
        }
    }

    /// Verifies cancellation is visible inside `yield` where the documentation says it is, from iOS 26, macOS 26, and visionOS 26.
    @Test(arguments: WritePath.available.filter { $0 == .post26 })
    func pixelBufferCancellationIsVisibleInsideYield(path: WritePath) async throws {
        try await withTemporaryDirectory { directory in
            let (writer, _) = try makeWriter("visible", in: directory)
            let sawCancellation = Mutex(false)
            let insideSlowFrame = Mutex(false)
            let task = Task {
                try await writePixelBuffers(writer, path: path) { index, pixelBuffer in
                    fill(pixelBuffer, gray: 100)
                    if index == 3 {
                        insideSlowFrame.withLock { $0 = true }
                        Thread.sleep(forTimeInterval: 0.5) // a slow frame, the cancellation lands while inside it
                        if Task.isCancelled { sawCancellation.withLock { $0 = true } }
                    }
                    return index < 30
                }
            }
            guard await wait(until: { insideSlowFrame.withLock { $0 } }) else {
                task.cancel()
                Issue.record("the writer never reached the slow frame")
                return
            }
            task.cancel()

            expectCancellation(await waitForOutcome(of: task))
            #expect(sawCancellation.withLock { $0 }, "Task.isCancelled was false inside yield after the task was canceled")
        }
    }

    /// Verifies a writer cannot be started twice.
    @Test(arguments: WritePath.available)
    func pixelBufferSecondStartThrowsInvalidState(path: WritePath) async throws {
        try await withTemporaryDirectory { directory in
            let (writer, _) = try makeWriter("twice", in: directory)
            let first = Task {
                try await writePixelBuffers(writer, path: path) { index, pixelBuffer in
                    fill(pixelBuffer, gray: 90)
                    return index < 3
                }
            }
            guard expectReturned(await waitForOutcome(of: first)) else { return }

            let second = Task {
                try await writePixelBuffers(writer, path: path) { _, _ in false }
            }
            guard case .threw(let error) = await waitForOutcome(of: second) else {
                Issue.record("starting a writer twice should throw")
                return
            }
            guard case .invalidAssetWriterState = error as? VideoWriter.WriteError else {
                Issue.record("expected invalidAssetWriterState, got \(error)")
                return
            }
        }
    }


    // MARK: - CGImage overload

    /// Verifies the stream ends when `yield` returns `nil`, after every index was requested once, in order.
    @Test(arguments: WritePath.available)
    func imageStopsWhenYieldReturnsNil(path: WritePath) async throws {
        let size = CGSize(width: 320, height: 180)
        try await withTemporaryDirectory { directory in
            let (writer, url) = try makeWriter("image-stops", in: directory, size: size)
            let requested = Mutex<[Int]>([])
            let task = Task {
                try await writeImages(writer, path: path) { index in
                    requested.withLock { $0.append(index) }
                    return index < 12 ? makeImage(gray: 128, size: size, bitmapInfo: ImageCase.copiedAsIs.bitmapInfo) : nil
                }
            }
            guard expectReturned(await waitForOutcome(of: task)) else { return }

            #expect(requested.withLock { $0 } == Array(0...12))
            let frames = try await quadrantsOfEachFrame(of: url)
            #expect(frames.count == 12)
        }
    }

    /// Verifies what the images contain ends up in the video, frame by frame, in the right channels, and in the right place, whether the pixels are copied as is, or have to be converted.
    @Test(arguments: WritePath.available, ImageCase.allCases)
    func imageContentReachesFile(path: WritePath, imageCase: ImageCase) async throws {
        let size = CGSize(width: imageCase.width, height: 180)
        try await withTemporaryDirectory { directory in
            let (writer, url) = try makeWriter("image-content", in: directory, size: size)
            let task = Task {
                try await writeImages(writer, path: path) { index in
                    index < Quadrants.sequence.count ? makeImage(Quadrants.sequence[index], size: size, bitmapInfo: imageCase.bitmapInfo) : nil
                }
            }
            guard expectReturned(await waitForOutcome(of: task)) else { return }

            expectFrames(try await quadrantsOfEachFrame(of: url))
        }
    }

    /// Verifies an error thrown by `yield` is the error thrown by `startWriting`, and that no partial file is left behind.
    @Test(arguments: WritePath.available)
    func imageErrorFromYieldPropagates(path: WritePath) async throws {
        let size = CGSize(width: 320, height: 180)
        try await withTemporaryDirectory { directory in
            let (writer, url) = try makeWriter("image-error", in: directory, size: size)
            let task = Task {
                try await writeImages(writer, path: path) { index in
                    if index == 5 { throw TestError(index: index) }
                    return makeImage(gray: 100, size: size, bitmapInfo: ImageCase.copiedAsIs.bitmapInfo)
                }
            }
            guard case .threw(let error) = await waitForOutcome(of: task) else {
                Issue.record("the writer should have thrown the error of yield")
                return
            }
            #expect(error as? TestError == TestError(index: 5), "threw \(error)")
            #expect(!fileExists(url), "the partially written file should be removed")
        }
    }

    /// Verifies a task that is already canceled when it starts writing ends with `CancellationError`, instead of hanging.
    @Test(arguments: WritePath.available)
    func imageCanceledBeforeStartThrowsCancellation(path: WritePath) async throws {
        let size = CGSize(width: 320, height: 180)
        try await withTemporaryDirectory { directory in
            let (writer, url) = try makeWriter("image-precanceled", in: directory, size: size)
            let task = Task {
                _ = try? await Task.sleep(for: .seconds(60)) // returns as soon as the task is canceled
                try await writeImages(writer, path: path) { index in
                    index < 30 ? makeImage(gray: 100, size: size, bitmapInfo: ImageCase.copiedAsIs.bitmapInfo) : nil
                }
            }
            try await Task.sleep(for: .milliseconds(100))
            task.cancel()

            expectCancellation(await waitForOutcome(of: task))
            #expect(!fileExists(url), "the partially written file should be removed")
        }
    }

    /// Verifies canceling at arbitrary moments always ends the writer with `CancellationError`, and never hangs.
    @Test(arguments: WritePath.available)
    func imageCanceledWhileRunningThrowsCancellation(path: WritePath) async throws {
        let size = CGSize(width: 320, height: 180)
        try await withTemporaryDirectory { directory in
            for iteration in 0..<12 {
                let (writer, url) = try makeWriter("image-canceled-\(iteration)", in: directory, size: size)
                let task = Task {
                    try await writeImages(writer, path: path) { index in
                        index < 100_000 ? makeImage(gray: UInt8(truncatingIfNeeded: index), size: size, bitmapInfo: ImageCase.copiedAsIs.bitmapInfo) : nil
                    }
                }
                try await Task.sleep(for: .microseconds(Int.random(in: 0...60_000)))
                task.cancel()

                let result = await waitForOutcome(of: task)
                expectCancellation(result, "iteration \(iteration)")
                #expect(!fileExists(url), "iteration \(iteration) left the partially written file behind")
                if case .hung = result { return } // no point in waiting for the remaining iterations
            }
        }
    }

    /// Verifies cancellation is visible inside `yield`, which is asynchronous, on both paths.
    @Test(arguments: WritePath.available)
    func imageCancellationIsVisibleInsideYield(path: WritePath) async throws {
        let size = CGSize(width: 320, height: 180)
        try await withTemporaryDirectory { directory in
            let (writer, _) = try makeWriter("image-visible", in: directory, size: size)
            let sawCancellation = Mutex(false)
            let insideSlowFrame = Mutex(false)
            let task = Task {
                try await writeImages(writer, path: path) { index in
                    if index == 3 {
                        insideSlowFrame.withLock { $0 = true }
                        _ = try? await Task.sleep(for: .milliseconds(500)) // returns early when canceled
                        if Task.isCancelled { sawCancellation.withLock { $0 = true } }
                    }
                    return index < 30 ? makeImage(gray: 100, size: size, bitmapInfo: ImageCase.copiedAsIs.bitmapInfo) : nil
                }
            }
            guard await wait(until: { insideSlowFrame.withLock { $0 } }) else {
                task.cancel()
                Issue.record("the writer never reached the slow frame")
                return
            }
            task.cancel()

            expectCancellation(await waitForOutcome(of: task))
            #expect(sawCancellation.withLock { $0 }, "Task.isCancelled was false inside yield after the task was canceled")
        }
    }

}


// MARK: - Helpers

private struct TestError: Error, Equatable {
    let index: Int
}

/// A color with 8 bits per channel.
private struct Pixel: Equatable, CustomStringConvertible, Sendable {

    var red: UInt8
    var green: UInt8
    var blue: UInt8

    static func gray(_ level: UInt8) -> Pixel {
        Pixel(red: level, green: level, blue: level)
    }

    var description: String { "rgb(\(red), \(green), \(blue))" }
}

/// A frame made of four colored quadrants.
///
/// Every quadrant has its own hue, and the brightness differs per frame, so that a swapped channel, a flipped image, a skewed row, or a mixed up frame shows.
private struct Quadrants: Equatable, CustomStringConvertible, Sendable {

    var topLeft: Pixel
    var topRight: Pixel
    var bottomLeft: Pixel
    var bottomRight: Pixel

    /// All four quadrants have the same color.
    init(uniform color: Pixel) {
        self.init(topLeft: color, topRight: color, bottomLeft: color, bottomRight: color)
    }

    init(topLeft: Pixel, topRight: Pixel, bottomLeft: Pixel, bottomRight: Pixel) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
    }

    /// The frames of the content tests, with brightness 90, 105, ..., 195.
    static let sequence: [Quadrants] = (0..<8).map { index in
        let level = UInt8(90 + 15 * index)
        return Quadrants(
            topLeft: Pixel(red: level, green: 20, blue: 20),
            topRight: Pixel(red: 20, green: level, blue: 20),
            bottomLeft: Pixel(red: 20, green: 20, blue: level),
            bottomRight: Pixel(red: level, green: level, blue: 20)
        )
    }

    var all: [Pixel] { [topLeft, topRight, bottomLeft, bottomRight] }

    var description: String { "[\(topLeft), \(topRight), \(bottomLeft), \(bottomRight)]" }
}

/// How a writer task ended.
private enum Outcome: CustomStringConvertible, Sendable {
    case returned
    case threw(any Error)
    /// It did not end within the time limit.
    case hung

    var description: String {
        switch self {
        case .returned: "returned normally"
        case .threw(let error): "threw \(type(of: error)): \(error)"
        case .hung: "did not finish in time"
        }
    }
}

private final class Once: @unchecked Sendable {

    private let claimed = Mutex(false)

    /// Returns `true` the first time it is called, and `false` afterwards.
    func claim() -> Bool {
        claimed.withLock { claimed in
            if claimed { return false }
            claimed = true
            return true
        }
    }
}

/// Waits for `task` to end, or reports it as hung after `seconds`, so that a writer that never finishes cannot block the test run.
private func waitForOutcome(of task: Task<Void, any Error>, within seconds: Double = 20) async -> Outcome {
    await withCheckedContinuation { continuation in
        let once = Once()
        Task {
            let result = await task.result
            guard once.claim() else { return }
            switch result {
            case .success: continuation.resume(returning: .returned)
            case .failure(let error): continuation.resume(returning: .threw(error))
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            if once.claim() { continuation.resume(returning: .hung) }
        }
    }
}

/// Polls `condition` until it holds, and returns whether it did within `seconds`.
private func wait(until condition: () -> Bool, within seconds: Double = 10) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// Records an issue unless the writer ended by returning normally.
private func expectReturned(_ outcome: Outcome, sourceLocation: SourceLocation = #_sourceLocation) -> Bool {
    if case .returned = outcome { return true }
    Issue.record("the writer \(outcome), expected it to finish", sourceLocation: sourceLocation)
    return false
}

/// Records an issue unless the writer ended by throwing `CancellationError`.
private func expectCancellation(_ outcome: Outcome, _ context: String = "the writer", sourceLocation: SourceLocation = #_sourceLocation) {
    switch outcome {
    case .threw(let error):
        #expect(error is CancellationError, "\(context) threw \(type(of: error)), expected CancellationError", sourceLocation: sourceLocation)
    case .returned, .hung:
        Issue.record("\(context) \(outcome), expected it to throw CancellationError", sourceLocation: sourceLocation)
    }
}

/// Records an issue unless the decoded frames show every quadrant where it was drawn, in the channels it was drawn in, and the frames in the order they were written.
///
/// The colors are not compared by value: the codec shifts saturated colors by up to 30 levels, the same on every path, which says nothing about the writer. What the writer decides is where the pixels are, which channel they are in, and in which frame.
private func expectFrames(_ decoded: [Quadrants], sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(decoded.count == Quadrants.sequence.count, "the video has \(decoded.count) frames, expected \(Quadrants.sequence.count)", sourceLocation: sourceLocation)

    let margin = 60 // how much stronger the dominant channels are than the rest, in the frames written
    var previous: [Int]?
    for (index, frame) in decoded.enumerated() {
        let topLeft = frame.topLeft, topRight = frame.topRight, bottomLeft = frame.bottomLeft, bottomRight = frame.bottomRight
        #expect(Int(topLeft.red) - max(Int(topLeft.green), Int(topLeft.blue)) > margin, "frame \(index): the top left quadrant should be red, it is \(topLeft)", sourceLocation: sourceLocation)
        #expect(Int(topRight.green) - max(Int(topRight.red), Int(topRight.blue)) > margin, "frame \(index): the top right quadrant should be green, it is \(topRight)", sourceLocation: sourceLocation)
        #expect(Int(bottomLeft.blue) - max(Int(bottomLeft.red), Int(bottomLeft.green)) > margin, "frame \(index): the bottom left quadrant should be blue, it is \(bottomLeft)", sourceLocation: sourceLocation)
        #expect(min(Int(bottomRight.red), Int(bottomRight.green)) - Int(bottomRight.blue) > margin, "frame \(index): the bottom right quadrant should be yellow, it is \(bottomRight)", sourceLocation: sourceLocation)

        let levels = [Int(topLeft.red), Int(topRight.green), Int(bottomLeft.blue), (Int(bottomRight.red) + Int(bottomRight.green)) / 2]
        if let previous {
            for (quadrant, (now, before)) in zip(levels, previous).enumerated() {
                #expect(now > before, "frame \(index): quadrant \(quadrant) is not brighter than in the frame before, so the frames are out of order", sourceLocation: sourceLocation)
            }
        }
        previous = levels
    }
}

private func fileExists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
}

/// Runs `body` with an empty scratch directory, which is removed afterwards. It lives in `$TMPDIR`, which `Foundation` does not always honor, so it is read from the environment first.
private func withTemporaryDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
    let base = ProcessInfo.processInfo.environment["TMPDIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
    let directory = base.appendingPathComponent("MediaKitVideoWriterTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try await body(directory)
}

private func makeWriter(_ name: String, in directory: URL, size: CGSize = CGSize(width: 320, height: 180)) throws -> (writer: VideoWriter, url: URL) {
    let url = directory.appendingPathComponent("\(name).mov")
    return (try VideoWriter(size: size, frameRate: 30, to: FinderItem(at: url)), url)
}

/// Starts the `CVPixelBuffer` overload on the given path.
private func writePixelBuffers(_ writer: VideoWriter, path: VideoWriterWritePathTests.WritePath, yield: @escaping VideoWriter.CVPixelBufferYield) async throws {
    switch path {
    case .pre26:
        try await writer.startWriting_pre26(yield: yield)
    case .post26:
        guard #available(iOS 26.0, macOS 26.0, visionOS 26, *) else { preconditionFailure("The post-26 path cannot run on this system.") }
        try await writer.startWriting_post26(yield: yield)
    }
}

/// Starts the `CGImage` overload on the given path.
private func writeImages(_ writer: VideoWriter, path: VideoWriterWritePathTests.WritePath, yield: @escaping (_ index: Int) async throws -> sending CGImage?) async throws {
    switch path {
    case .pre26:
        try await writer.startWriting_pre26(yield: yield)
    case .post26:
        guard #available(iOS 26.0, macOS 26.0, visionOS 26, *) else { preconditionFailure("The post-26 path cannot run on this system.") }
        try await writer.startWriting_post26(yield: yield)
    }
}

/// Fills the whole buffer, row by row, so that the row stride is honored.
private func fill(_ pixelBuffer: CVPixelBuffer, with quadrants: Quadrants) {
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

    func bgra(_ color: Pixel) -> UInt32 { // little endian
        UInt32(0xFF00_0000) | UInt32(color.red) << 16 | UInt32(color.green) << 8 | UInt32(color.blue)
    }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
    for row in 0..<height {
        let pixels = (base + row * stride).assumingMemoryBound(to: UInt32.self)
        let left = bgra(row < height / 2 ? quadrants.topLeft : quadrants.bottomLeft)
        let right = bgra(row < height / 2 ? quadrants.topRight : quadrants.bottomRight)
        for column in 0..<width {
            pixels[column] = column < width / 2 ? left : right
        }
    }
}

private func fill(_ pixelBuffer: CVPixelBuffer, gray: UInt8) {
    fill(pixelBuffer, with: Quadrants(uniform: .gray(gray)))
}

/// An image made of the quadrants.
private func makeImage(_ quadrants: Quadrants, size: CGSize, bitmapInfo: UInt32) -> sending CGImage? {
    guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo) else { return nil }
    let halfWidth = size.width / 2
    let halfHeight = size.height / 2
    // The origin of the coordinate system is the bottom left corner.
    for (color, origin) in [
        (quadrants.topLeft, CGPoint(x: 0, y: halfHeight)),
        (quadrants.topRight, CGPoint(x: halfWidth, y: halfHeight)),
        (quadrants.bottomLeft, CGPoint(x: 0, y: 0)),
        (quadrants.bottomRight, CGPoint(x: halfWidth, y: 0)),
    ] {
        context.setFillColor(red: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255, alpha: 1)
        context.fill(CGRect(origin: origin, size: CGSize(width: halfWidth, height: halfHeight)))
    }
    return context.makeImage()
}

private func makeImage(gray: UInt8, size: CGSize, bitmapInfo: UInt32) -> sending CGImage? {
    makeImage(Quadrants(uniform: .gray(gray)), size: size, bitmapInfo: bitmapInfo)
}

/// The colors at the centers of the four quadrants of every frame of the video, in presentation order.
private func quadrantsOfEachFrame(of url: URL) async throws -> [Quadrants] {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { return [] }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadUnknown) }

    var frames: [Quadrants] = []
    while let sample = output.copyNextSampleBuffer() {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { continue }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        func pixel(x: Int, y: Int) -> Pixel {
            let bytes = (base + y * stride + x * 4).assumingMemoryBound(to: UInt8.self) // B, G, R, A
            return Pixel(red: bytes[2], green: bytes[1], blue: bytes[0])
        }
        frames.append(Quadrants(
            topLeft: pixel(x: width / 4, y: height / 4),
            topRight: pixel(x: width * 3 / 4, y: height / 4),
            bottomLeft: pixel(x: width / 4, y: height * 3 / 4),
            bottomRight: pixel(x: width * 3 / 4, y: height * 3 / 4)
        ))
    }
    return frames
}
