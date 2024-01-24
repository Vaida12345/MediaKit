//
//  PDFKit Extensions.swift
//  The Nucleus Module
//
//  Created by Vaida on 5/15/22.
//  Copyright © 2019 - 2024 Vaida. All rights reserved.
//


#if canImport(PDFKit)
import PDFKit
import UniformTypeIdentifiers
import Nucleus


public extension PDFDocument {
    
    /// Extract images from the given pdf.
    ///
    /// The operation is async.
    func extractImages() async throws -> some ConcurrentStream<CGImage> {
        
        @Sendable
        func _obtainStream(dictionary: OpaquePointer) -> [OpaquePointer]? {
            guard let resource = dictionary.getDictionary(for: "Resources") else { return nil }
            guard let object = resource.getDictionary(for: "XObject") else { return nil }
            
            var result: [OpaquePointer] = []
            
            object.apply { key, object in
                guard let stream = object.getValue(type: .stream, for: CGPDFStreamRef.self) else { return true }
                guard let dictionary = stream.dictionary else { return true }
                guard let name = dictionary.getName(for: "Subtype") else { return true }
                if name == "Image" {
                    result.append(stream)
                } else if name == "Form" {
                    result.append(contentsOf: _obtainStream(dictionary: dictionary) ?? [])
                }
                
                return true
            }
            
            return result.isEmpty ? nil : result
        }
        
        @Sendable
        func extractImage(from page: PDFPage) async -> [CGImage]? {
            
            guard let pageRef = page.pageRef else { return nil }
            guard let dictionary = pageRef.dictionary else { return nil }
            
            guard let streams = _obtainStream(dictionary: dictionary) else { return nil }
            
            return streams.compactMap { object -> CGImage? in
                let stream = object
                guard let dictionary = object.dictionary,
                      let (format, data) = stream.data else { return nil }
                
                let colorSpace = {
                    if let colorSpace = dictionary.getName(for: "ColorSpace") {
                        switch colorSpace {
                        case "DeviceGray":
                            return CGColorSpaceCreateDeviceGray()
                        case "DeviceRGB":
                            return CGColorSpaceCreateDeviceRGB()
                        case "DeviceCMYK":
                            return CGColorSpaceCreateDeviceCMYK()
                        default:
                            break
                        }
                    }
                    return CGColorSpaceCreateDeviceRGB()
                }()
                
                if format == .JPEG2000 || format == .jpegEncoded {
                    guard let provider = CGDataProvider(data: data),
                          var image = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
                    
                    if colorSpace != image.colorSpace! {
                        image = image.copy(colorSpace: colorSpace) ?? image
                    }
                    
                    _applyImageBitmap(from: dictionary, image: &image)
                    
                    return image
                } else if format == .raw {
                    
                    guard let width = dictionary.getInteger(for: "Width"),
                          let height = dictionary.getInteger(for: "Height"),
                          let bpc = dictionary.getInteger(for: "BitsPerComponent") else { return nil }
                    
                    let decode: [CGFloat]?
                    if let decodeArray = dictionary.getArray(for: "Decode") {
                        let count = CGPDFArrayGetCount(decodeArray)
                        decode = (0..<count).map {
                            var result: CGFloat = 0
                            CGPDFArrayGetNumber(decodeArray, $0, &result)
                            return result
                        }
                    } else {
                        decode = nil
                    }
                    
                    let intent: CGColorRenderingIntent = {
                        if let _intent = dictionary.getName(for: "Intent") {
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
                                break
                            }
                        }
                        
                        return .defaultIntent
                    }()
                    
                    guard let provider = CGDataProvider(data: data) else { return nil }
                    let dataCount = (data as Data).count
                    
                    guard var image = CGImage(width: width, height: height, bitsPerComponent: bpc, bitsPerPixel: dataCount / width / height * 8, bytesPerRow: dataCount / height, space: colorSpace, bitmapInfo: CGBitmapInfo(), provider: provider, decode: decode, shouldInterpolate: false, intent: intent) else { return nil }
                    _applyImageBitmap(from: dictionary, image: &image)
                    
                    return image
                } else {
                    return nil
                }
            }
        }
        
        @Sendable
        func _applyImageBitmap(from dictionary: CGPDFDictionaryRef, image: inout CGImage) {
            if let maskStream = dictionary.getStream(for: "SMask"),
               let maskDictionary = maskStream.dictionary,
               let (_, data) = maskStream.data,
               let height = maskDictionary.getInteger(for: "Height"),
               let width = maskDictionary.getInteger(for: "Width"),
               let _bpc = maskDictionary.getInteger(for: "BitsPerComponent"),
               let provider = CGDataProvider(data: data) {
                
                let decode: [CGFloat]?
                if let decodeArray = maskDictionary.getArray(for: "Decode") {
                    let count = CGPDFArrayGetCount(decodeArray)
                    decode = (0..<count).map {
                        var result: CGFloat = 0
                        CGPDFArrayGetNumber(decodeArray, $0, &result)
                        return result
                    }
                } else {
                    decode = nil
                }
                
                let _dataCount = (data as Data).count
                
                if let mask = CGImage(width: width, height: height, bitsPerComponent: _bpc, bitsPerPixel: _dataCount / width / height * 8, bytesPerRow: _dataCount / height, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(), provider: provider, decode: decode, shouldInterpolate: false, intent: .defaultIntent) {
                    
                    let context = CGContext.createContext(size: image.size, bitsPerComponent: image.bitsPerComponent, space: image.colorSpace!, withAlpha: true)
                    context.clip(to: CGRect(origin: .zero, size: image.size), mask: mask)
                    context.draw(image, in: CGRect(origin: .zero, size: image.size))
                    
                    if let applied = context.makeImage() {
                        image = applied
                    }
                }
            }
        }
        
        return await (0..<self.pageCount).stream.flatMap { index in
            let page = self.page(at: index)!
            return await extractImage(from: page)?.stream
        }
    }
    
}

#endif
