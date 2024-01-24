//
//  CGPDFDictionary Extensions.swift
//  The Nucleus Module
//
//  Created by Vaida on 1/6/23.
//  Copyright © 2019 - 2024 Vaida. All rights reserved.
//


import CoreGraphics


/// A bridge from obj-c to Swift.
extension CGPDFDictionaryRef: CustomReflectable {
    
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
        var result: CGPDFStringRef? = nil
        guard CGPDFDictionaryGetString(self, key, &result) else { return nil }
        return result
    }
    
    public var customMirror: Mirror {
        var children: [(String, Any)] = []
        
        self.apply { key, object in
            
            switch object.type {
            case .boolean:
                children.append((key, object.getValue(type: .boolean, for: CGPDFBoolean.self) as Any))
            case .integer:
                children.append((key, object.getValue(type: .integer, for: CGPDFInteger.self) as Any))
            case .real:
                children.append((key, object.getValue(type: .real, for: CGFloat.self)!))
            case .name:
                children.append((key, String(cString: object.getValue(type: .name, for: UnsafePointer<CChar>.self)!)))
            case .string:
                let object = object.getValue(type: .string, for: CGPDFStringRef.self)!
                if let value = CGPDFStringCopyDate(object) {
                    children.append((key, value))
                } else if let value = CGPDFStringCopyTextString(object) {
                    children.append((key, value))
                } else {
                    fallthrough
                }
            case .array:
                children.append((key + " (array)", CGPDFDictionaryRef._mirror(for: object.getValue(type: .array, for: CGPDFArrayRef.self)!).children))
            case .stream:
                let value = object.getValue(type: .stream, for: CGPDFStreamRef.self)
                children.append((key, value!.dictionary!.customMirror.children))
            case .dictionary:
                let value = object.getValue(type: .dictionary, for: CGPDFDictionaryRef.self)
                children.append((key, value!.customMirror.children))
            default:
                children.append((key + " (unknown type)", object))
            }
            
            return true
        }
        
        return Mirror("CGPDFDictionary", children: children)
    }
    
    private static func _mirror(for array: CGPDFArrayRef) -> Mirror {
        var children: [(String, Any)] = []
        let count = CGPDFArrayGetCount(array)
        children.reserveCapacity(count)
        
        for i in 0..<count {
            if let result = array._arrayGetValue(using: CGPDFArrayGetArray, index: i) {
                children.append((i.description, CGPDFDictionaryRef._mirror(for: result)))
            } else if let result = array._arrayGetValue(using: CGPDFArrayGetName, index: i) {
                children.append((i.description, String(cString: result)))
            } else if let object = array._arrayGetValue(using: CGPDFArrayGetObject, index: i) {
                let key = i.description
                switch object.type {
                case .boolean:
                    children.append((key, object.getValue(type: .boolean, for: CGPDFBoolean.self)!))
                case .integer:
                    children.append((key, object.getValue(type: .integer, for: CGPDFInteger.self) as Any))
                case .real:
                    children.append((key, object.getValue(type: .real, for: CGFloat.self) as Any))
                case .name:
                    children.append((key, String(cString: object.getValue(type: .name, for: UnsafePointer<CChar>.self)!)))
                case .string:
                    let object = object.getValue(type: .string, for: CGPDFStringRef.self)!
                    if let value = CGPDFStringCopyDate(object) {
                        children.append((key, value))
                    } else if let value = CGPDFStringCopyTextString(object) {
                        children.append((key, value))
                    } else {
                        fallthrough
                    }
                case .array:
                    children.append((key + " (array)", object.getValue(type: .array, for: CGPDFArrayRef.self)!))
                case .dictionary:
                    children.append((key, "some dictionary"))
                case .stream:
                    let value = object.getValue(type: .stream, for: CGPDFStreamRef.self)
                    children.append((key, value!.dictionary!.customMirror.children))
                default:
                    children.append((key + " (unknown type)", object))
                }
            } else if let result = array._arrayGetValue(using: CGPDFArrayGetStream, index: i) {
                children.append((i.description, result.dictionary!.customMirror.children))
            } else if let object = array._arrayGetValue(using: CGPDFArrayGetString, index: i) {
                if let value = CGPDFStringCopyDate(object) {
                    children.append((i.description, value))
                } else if let value = CGPDFStringCopyTextString(object) {
                    children.append((i.description, value))
                }
            } else if let result = array._arrayGetValue(using: CGPDFArrayGetDictionary, index: i) {
                children.append((i.description, result.customMirror.children))
            } else {
                children.append((i.description, "unknown value at index"))
            } 
        }
        
        return Mirror("CGPDFArray", children: children)
    }
    
    private func _arrayGetValue<R>(using function: (CGPDFArrayRef, Int, UnsafeMutablePointer<R?>?) -> Bool, index: Int) -> R? {
        var result: R? = nil
        guard function(self, index, &result) else { return nil }
        return result
    }
}
