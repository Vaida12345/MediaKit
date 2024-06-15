//
//  CGPDFPage Extensions.swift
//  The Nucleus Module
//
//  Created by Vaida on 1/6/23.
//  Copyright © 2019 - 2024 Vaida. All rights reserved.
//


import CoreGraphics


extension CGPDFPage: @retroactive CustomReflectable {
    
    public var customMirror: Mirror {
        self.dictionary?.customMirror ?? Mirror("Some CGPDFPage", children: [])
    }
    
}
