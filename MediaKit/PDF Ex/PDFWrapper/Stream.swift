//
//  Stream.swift
//  MediaKit
//
//  Created by Vaida on 8/18/24.
//

import Foundation
import Essentials
import CoreGraphics
import DetailedDescription
import OSLog


extension CGPDFPageWrapper {
    
    public struct Stream: CustomStringConvertible, DetailedStringConvertible {
        
        public let dictionary: CGPDFPageWrapper.Dictionary
        
        public let content: Data
        
        public let format: CGPDFDataFormat
        
        
        init(ref: CGPDFStreamRef) throws {
            guard let _dictionary = CGPDFStreamGetDictionary(ref) else { throw LoadError.noAssociatedDictionary(object: ref) }
            self.dictionary = try Dictionary(ref: _dictionary)
            
            var format = CGPDFDataFormat.raw
            guard let data = CGPDFStreamCopyData(ref, &format) else {
                throw LoadError.noAssociatedData(object: ref)
            }
            
            self.content = data as Data
            self.format = format
        }
        
        enum LoadError: GenericError {
            
            case noAssociatedDictionary(object: CGPDFStreamRef)
            case noAssociatedData(object: CGPDFStreamRef)
            
            var title: String {
                "Load CGPDFStreamRef error"
            }
            
            var message: String {
                switch self {
                case .noAssociatedDictionary(let object):
                    "No associated dictionary for \(object)<CGPDFStreamRef>"
                case .noAssociatedData(let object):
                    "No associated data for \(object)<CGPDFStreamRef>"
                }
            }
        }
        
        
        private func getContentDescription(descriptor: DetailedDescription.Descriptor<Self>) -> any DescriptionBlockProtocol {
            guard self.format == .raw else { return descriptor.constant("content: Image") }
            if (try? self.load(.image)) != nil {
                return descriptor.constant("content: Image")
            } else if let string = String(data: content, encoding: .utf8) {
                return descriptor.value("content (decoded)", of: string)
            }
            
            return descriptor.value(for: \.content)
        }
        
        public func detailedDescription(using descriptor: DetailedDescription.Descriptor<Self>) -> any DescriptionBlockProtocol {
            descriptor.container("Stream") {
                descriptor.value(for: \.dictionary)
                switch self.format {
                case .raw:
                    descriptor.constant("format: raw")
                case .jpegEncoded:
                    descriptor.constant("format: jpegEncoded")
                case .JPEG2000:
                    descriptor.constant("format: JPEG2000")
                @unknown default:
                    descriptor.constant("Unknown format \(format)")
                }
                
                getContentDescription(descriptor: descriptor)
            }
        }
        
        public var description: String {
            self.detailedDescription
        }
        
        
        public func load<Content>(_ content: Content) throws(Content.Failure) -> Content.Result? where Content: LoadableContent {
            try content.load(self)
        }
        
        public protocol LoadableContent {
            
            func load(_ stream: CGPDFPageWrapper.Stream) throws(Failure) -> Result?
            
            associatedtype Result
            
            associatedtype Failure: Error
            
        }
        
        public struct LoadableImage: LoadableContent {
            
            func loadColorSpaceFromName(_ name: String?) -> CGColorSpace? {
                switch name {
                case "DeviceGray":
                    CGColorSpaceCreateDeviceGray()
                case "DeviceRGB":
                    CGColorSpaceCreateDeviceRGB()
                case "DeviceCMYK":
                    CGColorSpaceCreateDeviceCMYK()
                default:
                    nil
                }
            }
            
            func loadColorSpace(_ stream: CGPDFPageWrapper.Stream, logger: Logger) -> CGColorSpace? {
                guard let colorSpaceObject = stream.dictionary["ColorSpace"] else { return nil }
                
                if let colorSpaceArray = colorSpaceObject.array {
                    if colorSpaceArray.count == 2,
                       let stream = colorSpaceArray[1].stream,
                       let name = stream.dictionary["Alternate"]?.name {
                        return loadColorSpaceFromName(name)
                    }
                } else if let name = colorSpaceObject.name {
                    return loadColorSpaceFromName(name)
                }
                
                logger.error("Cannot parse color space from \(stream.dictionary)")
                
                return nil
            }
            
            func loadIntent(_ stream: Stream, logger: Logger) -> CGColorRenderingIntent? {
                if let _intent = stream.dictionary["Intent"]?.name {
                    switch _intent {
                    case "absoluteColorimetric":
                        return .absoluteColorimetric
                    case "relativeColorimetric":
                        return .relativeColorimetric
                    case "perceptual":
                        return .perceptual
                    case "saturation":
                        return .saturation
                    default:
                        return nil
                    }
                }
                
                return nil
            }
            
            func applyImageBitmapMask(_ stream: Stream, image: CGImage) -> CGImage {
                guard let mask = stream.dictionary["SMask"]?.stream else { return image }
                let width = mask.dictionary["Width"]!.integer!
                let height = mask.dictionary["Height"]!.integer!
                let bpc = mask.dictionary["BitsPerComponent"]!.integer!
                
                let provider = CGDataProvider(data: mask.content as CFData)!
                let decode = mask.dictionary["Decode"]?.array?.map({ $0.real! }) ?? nil
                
                let interpolate = mask.dictionary["Interpolate"]?.boolean ?? false
                assert(mask.dictionary["ColorSpace"]?.name == "DeviceGray")
                
                let cgmask = CGImage(
                    width: width,
                    height: height,
                    bitsPerComponent: bpc,
                    bitsPerPixel: mask.content.count / width / height * 8,
                    bytesPerRow: mask.content.count / height,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGBitmapInfo(),
                    provider: provider,
                    decode: decode,
                    shouldInterpolate: interpolate,
                    intent: .defaultIntent
                )!
                
                let context = CGContext.createContext(size: image.size, bitsPerComponent: image.bitsPerComponent, space: image.colorSpace!, withAlpha: true)
                context.clip(to: CGRect(origin: .zero, size: image.size), mask: cgmask)
                context.draw(image, in: CGRect(origin: .zero, size: image.size))
                
                return context.makeImage()!
            }
            
            public func load(_ stream: CGPDFPageWrapper.Stream) throws(Failure) -> Result? {
                let logger = Logger(subsystem: "MediaKit", category: "CGPDFWrapper.Stream.LoadableImage.load(_:)")
                
                let colorSpace = loadColorSpace(stream, logger: logger) ?? CGColorSpaceCreateDeviceRGB()
                let interpolate = stream.dictionary["Interpolate"]?.boolean ?? false
                let intent = loadIntent(stream, logger: logger) ?? .defaultIntent
                
                if stream.format == .JPEG2000 || stream.format == .jpegEncoded { // surely it is an image on this branch
                    let provider = CGDataProvider(data: stream.content as CFData)!
                    var image = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: interpolate, intent: intent)!

                    if colorSpace != image.colorSpace! {
                        image = image.copy(colorSpace: colorSpace) ?? image
                    }

                    return applyImageBitmapMask(stream, image: image)
                } else if let width = stream.dictionary["Width"]?.integer, // may not be an image, if all the way
                          let height = stream.dictionary["Height"]?.integer,
                          let bpc = stream.dictionary["BitsPerComponent"]?.integer,
                          let provider = CGDataProvider(data: stream.content as CFData),
                          let image = CGImage(
                            width: width,
                            height: height,
                            bitsPerComponent: bpc,
                            bitsPerPixel: stream.content.count / width / height * 8,
                            bytesPerRow: stream.content.count / height,
                            space: colorSpace,
                            bitmapInfo: CGBitmapInfo(),
                            provider: provider,
                            decode: stream.dictionary["Decode"]?.array?.compactMap({ $0.real }) ?? nil,
                            shouldInterpolate: interpolate,
                            intent: intent
                          ) {
                    return applyImageBitmapMask(stream, image: image)
                }
                
                return nil
            }
            
            public typealias Failure = any Error
            
            public typealias Result = CGImage
            
        }
        
    }
    
}


extension CGPDFPageWrapper.Stream.LoadableContent where Self == CGPDFPageWrapper.Stream.LoadableImage {
    
    public static var image: CGPDFPageWrapper.Stream.LoadableImage {
        CGPDFPageWrapper.Stream.LoadableImage()
    }
    
}
