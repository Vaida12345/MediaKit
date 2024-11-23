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
import FinderItem
import ConcurrentStream
import Essentials
import NativeImage


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
    func extractImages() async -> some ConcurrentStream<CGImage, any Error> {
        await (0..<self.pageCount).stream.flatMap { i in
            var queue = Queue<CGPDFPageWrapper.Object>()
            try queue.enqueue(.dictionary(self[i].wrapper.dictionary))
            
            var streams: [CGPDFPageWrapper.Stream] = []
            
            while let next = queue.next() {
                switch next {
                case .array(let array):
                    for i in array {
                        queue.enqueue(i)
                    }
                case .stream(let stream):
                    streams.append(stream)
                case .dictionary(let dictionary):
                    for (_, value) in dictionary {
                        queue.enqueue(value)
                    }
                default:
                    continue
                }
            }
            
            return await streams.stream.compactMap({ try? $0.load(.image) })
        }
    }
    
    subscript(_ index: Int) -> PDFPage {
        self.page(at: index)!
    }
    
}

#endif
