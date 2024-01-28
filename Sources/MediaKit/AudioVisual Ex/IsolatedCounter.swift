//
//  IsolatedCounter.swift
//  The Stratum Module
//
//  Created by Vaida on 3/2/23.
//  Copyright © 2019 - 2024 Vaida. All rights reserved.
//


/// A counter that works in async context without breaking isolation.
///
/// The only method ``advance()`` should be called at the beginning of the closure.
///
/// ```swift
/// let counter = IsolatedCounter()
///
/// let work = {
///     let current = await counter.advance()
///
///     // code goes here.
/// }
/// ```
///
/// Please note the existence of ``ConcurrentStream/enumerate(_:)``.
public actor IsolatedCounter {
    
    private var counter: Int
    
    
    /// Creates the counter.
    public init() {
        self.counter = -1
    }
    
    
    /// Increase the counter and returns the counter.
    public func advance() -> Int {
        counter += 1
        return counter
    }
    
    
}
