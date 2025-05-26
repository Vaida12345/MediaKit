//
//  VideoTests.swift
//  MediaKit
//
//  Created by Vaida on 12/26/24.
//

import Testing
import Foundation
import MediaKit
import PDFKit
import DetailedDescription
import FinderItem
import Essentials
import NativeImage
import Synchronization


@Suite(.serialized)
final class VideoTests: @unchecked Sendable {
    
    let image: CGImage
    
    let destination = FinderItem(at: "/Users/vaida/DataBase/Swift Package/Test Reference/Temp/MediaKit")
    
    let reference = FinderItem(at: "/Users/vaida/DataBase/Swift Package/Test Reference/MediaKit")
    
    
    nonisolated func createImageWithText(_ text: String, size: CGSize, font: NSFont = NSFont.systemFont(ofSize: 24), textColor: NSColor = .black, backgroundColor: NSColor = .white) -> sending CGImage? {
        // 1. Create a bitmap graphics context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil,
                                width: Int(size.width),
                                height: Int(size.height),
                                bitsPerComponent: 8,
                                bytesPerRow: 0,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        
        guard let context = context else {
            print("Failed to create graphics context.")
            return nil
        }
        
        // 2. Fill the background
        context.setFillColor(backgroundColor.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        // 3. Configure the text
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        
        // 4. Create a Core Text frame
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let framePath = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attributedText.length), framePath, nil)
        
        // 5. Draw the text into the context
        //                context.translateBy(x: 0, y: size.height) // Flip context vertically
        //                context.scaleBy(x: 1.0, y: -1.0)
        CTFrameDraw(frame, context)
        
        context.draw(image, in: CGRect(origin: .zero, size: size))
        
        // 6. Generate a CGImage
        return context.makeImage()
    }
    
    @discardableResult
    func render(size: CGSize) async throws -> FinderItem {
        let dest = destination/"\(size).mov"
        let writer = try VideoWriter(size: size, frameRate: 25, to: dest)
        
        try await writer.startWriting { index in
            guard index < 100 else { return nil }
            
            return self.createImageWithText("\(index)", size: size)
        }
        
        return dest
    }
    
    init() throws {
        self.image = try FinderItem(at: "/Users/vaida/DataBase/Swift Package/Test Reference/reference.heic").load(.cgImage)
        try destination.makeDirectory()
    }
    
    func getdata(_ data: CFData) -> Data {
        let size = CFDataGetLength(data)
        let bytes = CFDataGetBytePtr(data)!
        return Data(bytesNoCopy: .init(mutating: bytes), count: size, deallocator: .none)
    }
    
    @Test(arguments: [.square(1), .square(10), .square(100), .square(1000), CGSize(width: 8192, height: 4320)])
    func renderTest(size: CGSize) async throws {
        let dest = try await render(size: size)
        #expect(dest.exists)
        try await #expect(dest.load(.avAsset).frameCount == 100)
        try dest.remove()
    }
    
    @Test
    func renderLargeSize() async throws {
        await #expect(throws: VideoWriter.WriteError.videoSizeTooLarge(.square(8192))) {
            try await render(size: .square(8192))
        }
    }
    
    @Test
    func renderWithTimedCancel() async throws {
        let dest = destination/"renderWithTimedCancel.mov"
        let writer = try VideoWriter(size: CGSize(width: 1920, height: 1080), frameRate: 120, to: dest)
        
        await #expect(throws: TimeoutError.self) {
            try await Task.withTimeLimit(for: .seconds(2)) {
                try await writer.startWriting { index in
                    self.createImageWithText("\(index)", size: CGSize(width: 1920, height: 1080))
                }
            }
        }
        #expect(!dest.exists)
    }
    
    @Test(arguments: [Int](0..<20))
    func renderWithCancel(i: Int) async throws {
        let dest = destination/"renderWithCancel \(i).mov"
        let writer = try VideoWriter(size: CGSize(width: 1920, height: 1080), frameRate: 120, to: dest)
        
        let isTaskCanceled = Atomic<Bool>(false)
        let task = Task.detached {
            try await writer.startWriting { index in
                if isTaskCanceled.load(ordering: .sequentiallyConsistent) {
                    #expect(Bool(false), "Writing handler called after cancellation!")
                }
                return self.createImageWithText("\(index)", size: CGSize(width: 1920, height: 1080))
            }
        }
        let duration = Double.random(in: 0...0.5)
        try await Task.sleep(for: .seconds(duration))
        task.cancel()
        isTaskCanceled.store(true, ordering: .sequentiallyConsistent)
        try await Task.sleep(for: .seconds(0.1))
        #expect(!dest.exists)
    }
    
    @Test
    func renderWithError() async throws {
        let dest = destination/"renderWithError.mov"
        let writer = try VideoWriter(size: CGSize(width: 1920, height: 1080), frameRate: 120, to: dest)
        
        await #expect(throws: self.dummyError) {
            try await writer.startWriting { index in
                throw self.dummyError
            }
        }
        #expect(!dest.exists)
    }
    
    
    let dummyError = NSError(domain: "", code: 0)

}
