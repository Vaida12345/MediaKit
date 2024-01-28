//
//  CGPDFStream Extensions.swift
//  The Nucleus Module
//
//  Created by Vaida on 1/6/23.
//  Copyright © 2019 - 2024 Vaida. All rights reserved.
//


import CoreGraphics
import Foundation


/// A bridge from obj-c to Swift.
internal extension CGPDFStreamRef {
    
    /// Returns the dictionary associated with a PDF stream.
    var dictionary: CGPDFDictionaryRef? {
        CGPDFStreamGetDictionary(self)
    }
    
    /// Returns the data associated with a PDF stream.
    var data: (format: CGPDFDataFormat, value: CFData)? {
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(self, &format) else { return nil }
        return (format, data)
    }
    
}
