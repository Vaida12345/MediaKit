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
import Stratum
import ConcurrentStream


public extension PDFDocument {
    
    /// Initializes a `PDFDocument` object with the contents at the specified `FinderItem`.
    ///
    /// - Parameters:
    ///   - source: The `FinderItem` representing the location of the document.
    ///
    /// - Returns: A `PDFDocument` instance initialized with the data at the passed-in `source`.
    ///
    /// ## Topics
    /// ### Potential Error
    /// - ``ReadError``
    @inlinable
    convenience init(at source: FinderItem) throws {
        guard PDFDocument(url: source.url) != nil else { throw ReadError.cannotRead(source) }
        self.init(url: source.url)!
    }
    
    enum ReadError: GenericError {
        
        case cannotRead(FinderItem)
        
        public var title: String {
            "Cannot Read PDF Document"
        }
        
        public var message: String {
            switch self {
            case .cannotRead(let item):
                "The file at \(item) does not exist or is not a PDF document."
            }
        }
    }
    
    /// Creates a pdf containing all the `images`.
    ///
    /// A `quality` value of 1.0 specifies to use lossless compression if destination format supports it. A value of 0.0 implies to use maximum compression.
    ///
    /// - Parameters:
    ///   - images: The images to be included.
    ///   - quality: The quality of image compression.
    @inlinable
    convenience init<E>(from images: some ConcurrentStream<NativeImage, E>, quality: CGFloat = 1) async throws where E: Error {
        // create PDF
        self.init()
        
        let imageWidth: CGFloat = 1080
        
        let pages = await images.compactMap { (image: NativeImage) -> PDFPage? in
            guard let pixelSize = image.pixelSize else { return nil }
            guard pixelSize != .square(0) else { return nil } // cannot read, or a pdf file.
            let frame = pixelSize.aspectRatio(extend: .width, to: imageWidth)
#if os(macOS)
            image.size = frame
#endif
            
            let page = PDFPage(image: image, options: [.compressionQuality: quality, .mediaBox: CGRect(origin: .zero, size: frame), .upscaleIfSmaller: true])
            guard let page else { return nil }
            
            page.setBounds(CGRect(origin: .zero, size: frame), for: .mediaBox)
            return page
        }
        
        var pageCounter = 0
        while let page = try await pages.next() {
            self.insert(page, at: pageCounter)
            pageCounter += 1
        }
    }
    
    /// Adds the pages of a pdf document to the end of the document.
    ///
    /// - Parameters:
    ///   - document: The pages to append to the document.
    @inlinable
    func append(pagesOf document: PDFDocument) {
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { return }
            self.insert(page, at: self.pageCount)
        }
    }
    
    /// Renders the contents of pdf to images.
    ///
    /// This function now runs in parallel.
    @inlinable
    func rendered() async -> some ConcurrentStream<CGImage, Never> {
        nonisolated(unsafe)
        let document = self
        
        return await (0..<self.pageCount).stream.compactMap { i in
            guard let page = document.page(at: i) else { return nil }
            let size = page.bounds(for: .mediaBox).size
            return page.thumbnail(of: size, for: .mediaBox).cgImage
        }
    }
    
    /// Writes the current document to disk
    ///
    /// - Parameters:
    ///   - destination: The item indicating the place to persist document.
    ///
    /// ## Topics
    /// ### Potential Error
    /// - ``WriteError``
    @inlinable
    func write(to destination: FinderItem) throws {
        guard self.write(to: destination.url) else { throw WriteError.cannotWrite(destination) }
    }
    
    enum WriteError: GenericError {
        
        case cannotWrite(FinderItem)
        
        public var title: String {
            "Cannot write PDF Document"
        }
        
        public var message: String {
            switch self {
            case .cannotWrite(let item):
                "Cannot write a PDF document to \(item), either because cannot write, or the document is damaged."
            }
        }
    }
    
    /// Sets the attribute of the file document.
    ///
    /// - Parameters:
    ///   - key: The key for document attribute.
    ///   - value: The value of the key.
    @inlinable
    func setAttribute(_ key: PDFDocumentAttribute, _ value: Any) {
        self.documentAttributes?[key.rawValue] = value
    }
    
    /// The attribute of the file document.
    ///
    /// - Parameters:
    ///   - key: The key for document attribute.
    @inlinable
    func attribute(for key: PDFDocumentAttribute) -> Any? {
        self.documentAttributes?[key.rawValue]
    }
    
    
    /// Extract images from the given pdf.
    ///
    /// The operation is async.
    func extractImages() async throws -> some ConcurrentStream<CGImage, Never> {
        
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
        
        nonisolated(unsafe)
        let document = self
        return await (0..<self.pageCount).stream.compactMap { index in
            let page = document.page(at: index)!
            return await extractImage(from: page)?.stream
        }.flatten()
    }
    
}

#endif
