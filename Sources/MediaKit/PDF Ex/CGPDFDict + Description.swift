//
//  CGPDFDictionary + Description.swift
//  The Nucleus Module
//
//  Created by Vaida on 1/6/23.
//  Copyright © 2019 - 2024 Vaida. All rights reserved.
//

import Compression
import Foundation
import CoreGraphics
import DetailedDescription


/// A bridge from obj-c to Swift.
extension CGPDFDictionaryRef {
    
    /// Returns the number of entries in a PDF dictionary.
    var count: Int {
        CGPDFDictionaryGetCount(self)
    }
    
    /// Applies a function to each entry in a dictionary.
    ///
    /// This function enumerates all of the entries in the dictionary, calling the function once for each. The current key, its associated value, and the contextual information are passed to the function.
    ///
    /// - Note: The `info` parameter of `CGPDFDictionaryApplyFunction` is ignored, as it can be handled via Swift auto capture.
    ///
    /// - Parameters:
    ///   - function: The function to apply to each entry in the dictionary. The parameters are the current key and value in the dictionary.
    func apply(function: @escaping (_ key: String, _ object: CGPDFObjectRef) -> Bool) {
        func handler(key: UnsafePointer<Int8>, object: CGPDFObjectRef, info: UnsafeMutableRawPointer?) -> Bool {
            function(String(cString: key), object)
        }
        CGPDFDictionaryApplyBlock(self, handler, nil)
    }
    
    
    /// Returns the PDF array associated with a specified key in a PDF dictionary.
    ///
    /// - parameters:
    ///   - key: The key for the value to retrieve.
    func getArray(for key: String) -> CGPDFArrayRef? {
        var result: CGPDFObjectRef?
        guard CGPDFDictionaryGetArray(self, key, &result) else { return nil }
        return result
    }
    
    
    /// Returns the boolean value associated with a specified key in a PDF dictionary.
    ///
    /// - parameters:
    ///   - key: The key for the value to retrieve.
    func getBoolean(for key: String) -> Bool? {
        var result: CGPDFBoolean = 0
        guard CGPDFDictionaryGetBoolean(self, key, &result) else { return nil }
        return result != 0
    }
    
    /// Returns the dictionary value associated with a specified key in a PDF dictionary.
    ///
    /// - parameters:
    ///   - key: The key for the value to retrieve.
    func getDictionary(for key: String) -> CGPDFDictionaryRef? {
        var result: CGPDFDictionaryRef? = nil
        guard CGPDFDictionaryGetDictionary(self, key, &result) else { return nil }
        return result
    }
    
    /// Returns the PDF name reference with a specified key in a PDF dictionary.
    ///
    /// - parameters:
    ///   - key: The key for the value to retrieve.
    func getName(for key: String) -> String? {
        var result: UnsafePointer<CChar>? = nil
        guard CGPDFDictionaryGetName(self, key, &result) else { return nil }
        guard let result else { return nil }
        return String(cString: result)
    }
    
    /// Returns the float with a specified key in a PDF dictionary.
    ///
    /// - parameters:
    ///   - key: The key for the value to retrieve.
    func getFloat(for key: String) -> CGFloat? {
        var result: CGFloat = 0
        guard CGPDFDictionaryGetNumber(self, key, &result) else { return nil }
        return result
    }
    
    /// Returns the object with a specified key in a PDF dictionary.
    ///
    /// - parameters:
    ///   - key: The key for the value to retrieve.
    func getObject(for key: String) -> CGPDFObjectRef? {
        var result: CGPDFObjectRef? = nil
        guard CGPDFDictionaryGetObject(self, key, &result) else { return nil }
        return result
    }
    
    /// Returns the PDF stream with a specified key in a PDF dictionary.
    ///
    /// - parameters:
    ///   - key: The key for the value to retrieve.
    func getStream(for key: String) -> CGPDFStreamRef? {
        var result: CGPDFStreamRef? = nil
        guard CGPDFDictionaryGetStream(self, key, &result) else { return nil }
        return result
    }
    
    /// Returns the Int with a specified key in a PDF dictionary.
    ///
    /// - parameters:
    ///   - key: The key for the value to retrieve.
    func getInteger(for key: String) -> Int? {
        var result: Int = 0
        guard CGPDFDictionaryGetInteger(self, key, &result) else { return nil }
        return result
    }
    
    /// Returns the PDF string with a specified key in a PDF dictionary.
    ///
    /// - parameters:
    ///   - key: The key for the value to retrieve.
    func getString(for key: String) -> CGPDFStringRef? {
        var result = UnsafeMutablePointer<CGPDFStringRef?>.allocate(capacity: 1)
        defer { result.deallocate() }
        guard CGPDFDictionaryGetString(self, key, result) else { return nil }
        return result.pointee
    }
    
    func _arrayGetValue<R>(using function: (CGPDFArrayRef, Int, UnsafeMutablePointer<R?>?) -> Bool, index: Int) -> R? {
        var result: R? = nil
        guard function(self, index, &result) else { return nil }
        return result
    }
}


extension CGPDFDictionaryRef: @retroactive CustomDetailedStringConvertible {
    
    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<CGPDFDictionaryRef>) -> any DescriptionBlockProtocol {
        var children: [CGPDFObjectWrapper] = []
        
        self.apply { key, object in
            children.append(CGPDFObjectWrapper(key: key, source: object))
            return true
        }
        
        return descriptor.container("PDFDictionary") {
            descriptor.sequence("", of: children)
        }
    }
    
}


private struct CGPDFArrayWrapper: CustomDetailedStringConvertible {
    
    let source: CGPDFArrayRef
    
    func detailedDescription(using descriptor: DetailedDescription.Descriptor<CGPDFArrayWrapper>) -> any DescriptionBlockProtocol {
        let count = CGPDFArrayGetCount(source)
        
        return descriptor.container("CGPDFArray") {
            descriptor.forEach(0..<count) { index in
                if let innerArray = source._arrayGetValue(using: CGPDFArrayGetArray, index: index) {
                    descriptor.value("", of: CGPDFArrayWrapper(source: innerArray))
                } else if let name = source._arrayGetValue(using: CGPDFArrayGetName, index: index) {
                    descriptor.value("", of: String(cString: name))
                } else if let stream = source._arrayGetValue(using: CGPDFArrayGetStream, index: index) {
                    descriptor.value("", of: CGPDFStreamWrapper(source: stream))
                } else if let dictionary = source._arrayGetValue(using: CGPDFArrayGetDictionary, index: index) {
                    descriptor.value("", of: dictionary)
                } else if let string = source._arrayGetValue(using: CGPDFArrayGetString, index: index) {
                    if let value = CGPDFStringCopyDate(string) {
                        descriptor.value("", of: value)
                    } else {
                        let value = CGPDFStringCopyTextString(string) as? String ?? "(unknown String)"
                        descriptor.value("", of: value)
                    }
                } else if let object = source._arrayGetValue(using: CGPDFArrayGetObject, index: index) {
                    descriptor.value("", of: CGPDFObjectWrapper(key: "", source: object))
                } else {
                    descriptor.string("(unknown)")
                }
            }
        }
    }
}

private struct CGPDFObjectWrapper: CustomDetailedStringConvertible {
    
    let key: String
    
    let source: CGPDFObjectRef
    
    func detailedDescription(using descriptor: DetailedDescription.Descriptor<CGPDFObjectWrapper>) -> any DescriptionBlockProtocol {
        let type = source.type
        
        let value: Any
        switch type {
        case .boolean:
            value = source.getValue(type: type, for: CGPDFBoolean.self) as Any
        case .integer:
            value = source.getValue(type: type, for: CGPDFInteger.self) as Any
        case .real:
            value = source.getValue(type: type, for: CGPDFReal.self) as Any
        case .name:
            let name = source.getValue(type: .name, for: UnsafePointer<CChar>.self)
            value = name.map { String(cString: $0) } ?? "(unknown name)"
        case .string:
            if let object = source.getValue(type: .string, for: CGPDFStringRef.self) {
                if let _value = CGPDFStringCopyDate(object) {
                    value = _value
                    break
                } else if let _value = CGPDFStringCopyTextString(object) {
                    value = _value
                    break
                }
            }
            fallthrough
        case .array:
            let array = source.getValue(type: .array, for: CGPDFArrayRef.self)
            value = array.map { CGPDFArrayWrapper(source: $0) } as Any
        case .stream:
            let stream = source.getValue(type: .stream, for: CGPDFStreamRef.self)
            value = stream.map { CGPDFStreamWrapper(source: $0) } as Any
        case .dictionary:
            let dictionary = source.getValue(type: .dictionary, for: CGPDFDictionaryRef.self)
            if key == "Parent" {
                value = "(dictionary)"
            } else {
                value = dictionary as Any
            }
        case .null:
            value = "(null)"
        default:
            value = "(unknown)"
        }
        
        return descriptor.value(key, of: value)
    }
}


private struct CGPDFStreamWrapper: CustomDetailedStringConvertible {
    
    let source: CGPDFStreamRef
    
    
    func detailedDescription(using descriptor: DetailedDescription.Descriptor<CGPDFStreamWrapper>) -> any DescriptionBlockProtocol {
        descriptor.container("CGPDFStream") {
            descriptor.value("dictionary", of: source.dictionary)
            
            let data = source.data
            if data?.0 == .JPEG2000 || data?.0 == .jpegEncoded {
                descriptor.string("JPEG encoded image")
            } else if let data = data?.value as? Data {
                if let filter = source.dictionary?.getObject(for: "Filter")?.getValue(type: .name, for: UnsafePointer<CChar>.self).map({ String(cString: $0) }),
                   filter == "FlateDecode",
                   let data = decompressFlateData(data) {
                    if let string = String(data: data, encoding: .utf8) {
                        descriptor.value("content", of: string)
                    } else {
                        descriptor.value("content", of: data)
                    }
                } else {
                    descriptor.value("content", of: data)
                }
            } else {
                descriptor.string("Broken Data")
            }
        }
    }
    
}


func decompressFlateData(_ compressed: Data) -> Data? {
    compressed.withUnsafeBytes { compressed in
        // Define the algorithm used.
        let algorithm = COMPRESSION_ZLIB
        
        // Allocate a buffer to hold the decompressed data.
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: compressed.count * 4) // A typical size guess
        defer {
            destinationBuffer.deallocate()
        }
        
        // Perform the decompression
        let decompressedCount = compression_decode_buffer(destinationBuffer, compressed.count * 4,
                                                          compressed.assumingMemoryBound(to: UInt8.self).baseAddress!,
                                                          compressed.count, nil, algorithm)
        
        // Check if decompression was successful
        if decompressedCount == 0 {
            return nil // Decompression failed
        }
        
        // Create a Data object from the buffer
        return Data(bytes: destinationBuffer, count: decompressedCount)
    }
}
