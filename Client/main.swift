//
//  File.swift
//  
//
//  Created by Vaida on 5/28/24.
//

import Foundation
import MediaKit
@preconcurrency import PDFKit
import DetailedDescription
import FinderItem
import Essentials
import NativeImage


let image = try FinderItem(at: "/Users/vaida/Library/Mobile Documents/com~apple~CloudDocs/DataBase/Others/Anime/Pictures/Mirai Kuriyama.heic").load(.image)

#if os(macOS)
func createImageWithText(_ text: String, size: CGSize, font: NSFont = NSFont.systemFont(ofSize: 24), textColor: NSColor = .black, backgroundColor: NSColor = .white) -> CGImage? {
    // 1. Create a bitmap graphics context
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil,
                            width: Int(size.width),
                            height: Int(size.height),
                            bitsPerComponent: 8,
                            bytesPerRow: 0,
                            space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
    
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
    
//    context.draw(image, in: CGRect(origin: .zero, size: size))
    
    // 6. Generate a CGImage
    return context.makeImage()
}

let destination: FinderItem = .desktopDirectory/"test"
try destination.makeDirectory()

func render(size: CGSize) async throws {
    let writer = try VideoWriter(size: size, frameRate: 25, to: destination/"\(size).mov")
    
    try await writer.startWriting { index in
        guard index < 10000 else { return nil }
        
        return createImageWithText("\(index)", size: size)
    }
}

try await render(size: .square(500))
#endif
