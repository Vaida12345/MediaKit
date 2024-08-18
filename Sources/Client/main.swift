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
import Stratum


let document = try PDFDocument(at: "/Users/vaida/Desktop/image.png.pdf")

try await document.extractImages().forEach { index, element in
    try element.write(to: FinderItem.desktopDirectory.appending(path: "file \(index).png"))
}
