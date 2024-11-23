//
//  PDFWrapper.swift
//  MediaKit
//
//  Created by Vaida on 8/18/24.
//

import PDFKit
import DetailedDescription
import CoreGraphics


public struct CGPDFPageWrapper: CustomStringConvertible, CustomDetailedStringConvertible {
    
    let source: CGPDFPage
    
    public let dictionary: CGPDFPageWrapper.Dictionary
    
    public init(source: CGPDFPage) throws {
        self.source = source
        self.dictionary = try CGPDFPageWrapper.Dictionary(ref: source.dictionary!)
    }
    
    public init?(page: PDFPage) throws {
        guard let ref = page.pageRef else { return nil }
        try self.init(source: ref)
    }
    
    
    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<CGPDFPageWrapper>) -> any DescriptionBlockProtocol {
        descriptor.container {
            descriptor.value(for: \.dictionary)
        }
    }
    
    public var description: String {
        self.detailedDescription
    }
    
}


public extension PDFPage {
    
    var wrapper: CGPDFPageWrapper {
        get throws {
            try CGPDFPageWrapper(page: self)!
        }
    }
    
}
