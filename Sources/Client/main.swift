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


let document = try PDFDocument(at: "/Users/vaida/Library/Mobile Documents/com~apple~CloudDocs/DataBase/Study/Digital Tech/Files/Assignmt 3/Info.pdf")
let dictionary = document.page(at: 0)!.pageRef!.dictionary!
let blocks = dictionary.descriptionBlocks()
print(blocks.string)

//let _target = dictionary.descriptionBlocks()
//    .as(ContainerBlock.self).lines
//    .as(FlattenLinesBlock.self).lines[0]
//    .as(LineBlock.self).childBlock()
//    .as(SequenceBlock.self).blocks[3]
//    .as(LineBlock.self).childBlock()
//    .as(LineBlock.self).childBlock()
//    .as(ContainerBlock.self).lines
//    .as(FlattenLinesBlock.self).lines[0]
//    .as(LineBlock.self).childBlock()
//    .as(ContainerBlock.self).lines
//    .as(FlattenLinesBlock.self).lines[0]
//    .as(LineBlock.self).childBlock()
//    .as(SequenceBlock.self).blocks[0]
//    .as(LineBlock.self).childBlock()
//
//dump(_target)
//print(_target.string)
