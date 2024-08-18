//
//  Array.swift
//  MediaKit
//
//  Created by Vaida on 8/18/24.
//

import Foundation
import DetailedDescription
import Stratum
import CoreGraphics


extension CGPDFPageWrapper {
    
    public struct Array: RandomAccessCollection, CustomStringConvertible, CustomDetailedStringConvertible {
        
        public let count: Int
        
        let array: [CGPDFPageWrapper.Object]
        
        
        init(ref: CGPDFArrayRef) throws {
            self.count = CGPDFArrayGetCount(ref)
            var array: [CGPDFPageWrapper.Object] = []
            array.reserveCapacity(self.count)
            for index in 0..<count {
                let object: CGPDFPageWrapper.Object
                
                if let boolean = Array.arrayGetValue(ref, using: CGPDFArrayGetBoolean, index: index) {
                    object = .boolean(boolean != 0)
                } else if let integer = Array.arrayGetValue(ref, using: CGPDFArrayGetInteger, index: index) {
                    object = .integer(integer)
                } else if let real = Array.arrayGetValue(ref, using: CGPDFArrayGetNumber, index: index) {
                    object = .real(real)
                } else if let char = Array.arrayGetValue(ref, using: CGPDFArrayGetName, index: index) {
                    object = .name(String(cString: char))
                } else if let string = Array.arrayGetValue(ref, using: CGPDFArrayGetString, index: index) {
                    if let date = CGPDFStringCopyDate(string) {
                        object = .date(date as Date)
                    } else if let string = CGPDFStringCopyTextString(string) {
                        object = .string(string as String)
                    } else {
                        object = .unknownString(string)
                    }
                } else if let ref = Array.arrayGetValue(ref, using: CGPDFArrayGetArray, index: index) {
                    object = try .array(CGPDFPageWrapper.Array(ref: ref))
                } else if let ref = Array.arrayGetValue(ref, using: CGPDFArrayGetStream, index: index) {
                    object = try .stream(CGPDFPageWrapper.Stream(ref: ref))
                } else if let ref = Array.arrayGetValue(ref, using: CGPDFArrayGetDictionary, index: index) {
                    object = try .dictionary(CGPDFPageWrapper.Dictionary(ref: ref))
                } else if CGPDFArrayGetNull(ref, index) {
                    object = .null
                } else {
                    fatalError("Unknown object at \(index)")
                }
                
                array.append(object)
            }
            
            self.array = array
        }
        
        private static func arrayGetValue<R>(_ ref: CGPDFArrayRef, using function: (CGPDFArrayRef, Int, UnsafeMutablePointer<R?>?) -> Bool, index: Int) -> R? {
            var result: R? = nil
            guard function(ref, index, &result) else { return nil }
            return result
        }
        
        private static func arrayGetValue<R>(_ ref: CGPDFArrayRef, using function: (CGPDFArrayRef, Int, UnsafeMutablePointer<R>?) -> Bool, index: Int) -> R? {
            let pointer = UnsafeMutablePointer<R>.allocate(capacity: 1)
            defer { pointer.deallocate() }
            guard function(ref, index, pointer) else { return nil }
            return pointer.pointee
        }
        
        public typealias Element = CGPDFPageWrapper.Object
        public typealias Index = Int
        
        public subscript(position: Int) -> CGPDFPageWrapper.Object {
            self.array[position]
        }
        
        public var startIndex: Int { 0 }
        
        public var endIndex: Int { self.count }
        
        
        public func detailedDescription(using descriptor: DetailedDescription.Descriptor<Self>) -> any DescriptionBlockProtocol {
            descriptor.container("Array (\(self.count) element)") {
                descriptor.forEach(self.array) { element in
                    descriptor.value("", of: element)
                }
            }
        }
        
        public var description: String {
            self.detailedDescription
        }
        
    }
    
}
