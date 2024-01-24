//
//  CGPDFObject Extensions.swift
//  The Nucleus Module
//
//  Created by Vaida on 1/6/23.
//  Copyright © 2019 - 2024 Vaida. All rights reserved.
//


import CoreGraphics


/// A bridge from obj-c to Swift.
internal extension CGPDFObjectRef {
    
    /// Returns the PDF type identifier of an object.
    var type: CGPDFObjectType {
        CGPDFObjectGetType(self)
    }
    
    /// Returns the value of the given object.
    ///
    /// - Parameters:
    ///   - type: A PDF object type.
    ///   - swiftType: The expected type in Swift.
    func getValue<SwiftType>(type: CGPDFObjectType, for swiftType: SwiftType.Type) -> SwiftType? {
        var result = UnsafeMutablePointer<SwiftType>.allocate(capacity: 1)
        defer { result.deallocate() }
        
        guard CGPDFObjectGetValue(self, type, &result) else { return nil }
        return result.pointee
    }
    
}
