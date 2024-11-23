//
//  File.swift
//  
//
//  Created by Vaida on 5/28/24.
//

import Foundation
import MediaKit
import PDFKit
@testable
import DetailedDescription
import FinderItem

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
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    
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
    
    // 6. Generate a CGImage
    return context.makeImage()
}


if #available(macOS 15.0, *) {
    let writer = try VideoWriter(size: CGSize(width: 1920, height: 1080), frameRate: 120, to: FinderItem.desktopDirectory.appending(path: "test.m4v"))
    try await writer.startWriting { index in
        if index <= 231 {
            return createImageWithText("\(index)", size: CGSize(width: 1920, height: 1080))
        } else {
            return nil
        }
    }
}
#endif
