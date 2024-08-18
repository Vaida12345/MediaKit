//
//  Dictionary.swift
//  MediaKit
//
//  Created by Vaida on 8/18/24.
//

import Foundation
import DetailedDescription
import CoreGraphics


extension CGPDFPageWrapper {
    
    public struct Dictionary: Sequence, CustomStringConvertible, CustomDetailedStringConvertible {
        
        let children: Swift.Dictionary<String, CGPDFPageWrapper.Object>
        
        public func makeIterator() -> Iterator {
            children.makeIterator()
        }
        
        init(ref: CGPDFDictionaryRef) throws {
            var children: Swift.Dictionary<String, CGPDFPageWrapper.Object> = [:]
            
            try Dictionary.apply(ref) { key, object in
                try children[key] = CGPDFPageWrapper.Object(key: key, ref: object)
                return true
            }
            
            self.children = children
        }
        
        /// Applies a function to each entry in a dictionary.
        ///
        /// This function enumerates all of the entries in the dictionary, calling the function once for each. The current key, its associated value, and the contextual information are passed to the function.
        ///
        /// - Note: The `info` parameter of `CGPDFDictionaryApplyFunction` is ignored, as it can be handled via Swift auto capture.
        ///
        /// - Parameters:
        ///   - function: The function to apply to each entry in the dictionary. The parameters are the current key and value in the dictionary.
        private static func apply(_ ref: CGPDFDictionaryRef, function: @escaping (_ key: String, _ object: CGPDFObjectRef) throws -> Bool) throws {
            func handler(key: UnsafePointer<Int8>, object: CGPDFObjectRef, info: UnsafeMutableRawPointer?) -> Bool {
                do {
                    return try function(String(cString: key), object)
                } catch {
                    info?.initializeMemory(as: NSError?.self, to: error as NSError)
                    return false
                }
            }
            
            var error: NSError? = nil
            CGPDFDictionaryApplyBlock(ref, handler, &error)
            
            if let error {
                throw error
            }
        }
        
        public typealias Element = (key: String, value: CGPDFPageWrapper.Object)
        
        public typealias Iterator = Swift.Dictionary<String, CGPDFPageWrapper.Object>.Iterator
        
        public subscript(_ key: String) -> CGPDFPageWrapper.Object? {
            self.children[key]
        }
        
        public func detailedDescription(using descriptor: DetailedDescription.Descriptor<Self>) -> any DescriptionBlockProtocol {
            descriptor.container("Dictionary") {
                descriptor.forEach(self.children) { (key, value) in
                    descriptor.value(key, of: value)
                }
            }
        }
        
        public var description: String {
            self.detailedDescription
        }
        
    }
    
}
