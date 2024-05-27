//
//  File.swift
//  
//
//  Created by Vaida on 5/28/24.
//

import Foundation
import MediaKit
import PDFKit


let document = try PDFDocument(at: "/Users/vaida/Desktop/私に天使が舞い降りた!.pdf")
dump(document.page(at: 1)!.pageRef!)
