//
//  Object.swift
//  MediaKit
//
//  Created by Vaida on 8/18/24.
//

import Foundation
import CoreGraphics
import Stratum
import DetailedDescription


extension CGPDFPageWrapper {
    
    public enum Object: CustomStringConvertible, CustomDetailedStringConvertible {
        
        case boolean(Bool)
        case integer(Int)
        case real(CGFloat)
        case name(String)
        case string(String)
        case unknownString(CGPDFStreamRef)
        case date(Date)
        case array(CGPDFPageWrapper.Array)
        case stream(CGPDFPageWrapper.Stream)
        /// A unmapped dictionary.
        ///
        /// This occurs as I do not want circular reference.
        case unmappedDictionary(CGPDFDictionaryRef)
        case dictionary(CGPDFPageWrapper.Dictionary)
        case null
        
        
        init(key: String, ref: CGPDFObjectRef) throws {
            let type = CGPDFObjectGetType(ref)
            
            switch type {
            case .boolean:
                self = try .boolean(Object.getValue(ref, type: type, for: CGPDFBoolean.self) != 0)
            case .integer:
                self = try .integer(Object.getValue(ref, type: type, for: CGPDFInteger.self))
            case .real:
                self = try .real(Object.getValue(ref, type: type, for: CGPDFReal.self))
            case .name:
                self = try .name(String(cString: Object.getValue(ref, type: type, for: UnsafePointer<CChar>.self)))
            case .string:
                let ref = try Object.getValue(ref, type: type, for: CGPDFStringRef.self)
                
                if let _value = CGPDFStringCopyDate(ref) {
                    self = .date(_value as Date)
                } else if let _value = CGPDFStringCopyTextString(ref) {
                    self = .string(_value as String)
                } else {
                    self = .unknownString(ref)
                }
            case .array:
                self = try .array(CGPDFPageWrapper.Array(ref: Object.getValue(ref, type: type, for: CGPDFArrayRef.self)))
            case .stream:
                self = try .stream(CGPDFPageWrapper.Stream(ref: Object.getValue(ref, type: type, for: CGPDFStreamRef.self)))
            case .dictionary:
                let dictionary = try Object.getValue(ref, type: type, for: CGPDFDictionaryRef.self)
                if key == "Parent" {
                    self = .unmappedDictionary(dictionary)
                } else {
                    self = try .dictionary(CGPDFPageWrapper.Dictionary(ref: dictionary))
                }
            case .null:
                self = .null
            default:
                fatalError("Unknown type \(type)")
            }
        }
        
        
        /// Returns the value of the given object.
        ///
        /// - Parameters:
        ///   - type: A PDF object type.
        ///   - swiftType: The expected type in Swift.
        private static func getValue<SwiftType>(_ object: CGPDFObjectRef, type: CGPDFObjectType, for swiftType: SwiftType.Type) throws(LoadError) -> SwiftType {
            let pointer = UnsafeMutablePointer<SwiftType>.allocate(capacity: 1)
            defer { pointer.deallocate() }
            
            guard CGPDFObjectGetValue(object, type, pointer) else { throw LoadError.load(object: object, type: type, swiftType: "\(swiftType)") }
            return pointer.pointee
        }
        
        
        enum LoadError: GenericError {
            
            case load(object: CGPDFObjectRef, type: CGPDFObjectType, swiftType: String)
            
            var title: String {
                "Load CGPDFObjectRef error"
            }
            
            var message: String {
                switch self {
                case .load(let object, let type, let swiftType):
                    "Load \(object)<\(type)> as \(swiftType) failed."
                }
            }
        }
        
        public func detailedDescription(using descriptor: DetailedDescription.Descriptor<Self>) -> any DescriptionBlockProtocol {
            switch self {
            case .boolean(let bool):
                descriptor.value("boolean", of: bool)
            case .integer(let int):
                descriptor.value("integer", of: int)
            case .real(let cgFloat):
                descriptor.value("real", of: cgFloat)
            case .name(let string):
                descriptor.value("name", of: string)
            case .string(let string):
                descriptor.value("string", of: string)
            case .unknownString(let ref):
                descriptor.value("unknown string", of: ref)
            case .date(let date):
                descriptor.value("date", of: date)
            case .array(let array):
                descriptor.value("", of: array)
            case .stream(let stream):
                descriptor.value("", of: stream)
            case .unmappedDictionary(let ref):
                descriptor.value("dictionary ref", of: ref)
            case .dictionary(let dictionary):
                descriptor.value("", of: dictionary)
            case .null:
                descriptor.constant("null")
            }
        }
        
        public var description: String {
            self.detailedDescription
        }
        
        /// Returns the value if matches, otherwise `nil`
        public var boolean: Bool? {
            switch self {
            case let .boolean(val): val
            default: nil
            }
        }
        
        /// Returns the value if matches, otherwise `nil`
        public var integer: Int? {
            switch self {
            case let .integer(val): val
            default: nil
            }
        }
        
        /// Returns the value if matches, otherwise `nil`
        public var real: CGFloat? {
            switch self {
            case let .real(val): val
            default: nil
            }
        }
        
        /// Returns the value if matches, otherwise `nil`
        public var name: String? {
            switch self {
            case let .name(val): val
            default: nil
            }
        }
        
        /// Returns the value if matches, otherwise `nil`
        public var string: String? {
            switch self {
            case let .string(val): val
            default: nil
            }
        }
        
        /// Returns the value if matches, otherwise `nil`
        public var unknownString: CGPDFStringRef? {
            switch self {
            case let .unknownString(val): val
            default: nil
            }
        }
        
        /// Returns the value if matches, otherwise `nil`
        public var date: Date? {
            switch self {
            case let .date(val): val
            default: nil
            }
        }
        
        /// Returns the value if matches, otherwise `nil`
        public var array: CGPDFPageWrapper.Array? {
            switch self {
            case let .array(val): val
            default: nil
            }
        }
        
        /// Returns the value if matches, otherwise `nil`
        public var stream: CGPDFPageWrapper.Stream? {
            switch self {
            case let .stream(val): val
            default: nil
            }
        }
        
        /// Returns the value if matches, otherwise `nil`
        public var unmappedDictionary: CGPDFDictionaryRef? {
            switch self {
            case let .unmappedDictionary(val): val
            default: nil
            }
        }
        
        /// Returns the value if matches, otherwise `nil`
        public var dictionary: CGPDFPageWrapper.Dictionary? {
            switch self {
            case let .dictionary(val): val
            default: nil
            }
        }
        
        public var isNull: Bool {
            switch self {
            case .null: true
            default: false
            }
        }
        
    }
    
}
