//
//  Fractional.swift
//  The Stratum Module - Arithmetic
//
//  Created by Vaida on 10/4/21.
//  Copyright © 2019 - 2024 Vaida. All rights reserved.
//

import Foundation


/// The fraction in the form of `a / b` where `a`, `b` in `R`.
public struct Fraction: Codable, LosslessStringConvertible, Sendable, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral, SignedNumeric, Comparable {

    // MARK: - Type Alias

    /// The FloatingPoint type used in ``Fractional``.
    ///
    /// The type is used in the instances such as ``sqrt(_:)`` and ``pow(_:_:)``.
    public typealias FloatingPoint = Double
    
    public typealias Integer = UInt


    // MARK: - Basic Instance Properties
    
    /// A boolean value indicating whether the value is positive.
    public let isPositive: Bool

    /// The numerator of the fraction.
    public let numerator: Integer

    /// The non-negative denominator of the fraction.
    public let denominator: Integer
    
    
    /// Initialize with the given numerator and denominator.
    ///
    /// Rules to be applied:
    /// - Divide the ``numerator`` and ``denominator`` with the greatest common factor.
    fileprivate init(isPositive: Bool, numerator: Integer, denominator: Integer) {
        let result = Fractional.reduce(numerator: numerator, denominator: denominator)
        
        self.isPositive = isPositive
        self.numerator = result.numerator
        self.denominator = result.denominator
    }
    
    /// Initialize with the given numerator and denominator.
    ///
    /// No preprocessing will be applied.
    fileprivate init(__isPositive: Bool, numerator: Integer, denominator: Integer) {
        self.isPositive = __isPositive
        self.numerator = numerator
        self.denominator = denominator
    }
    
    
    // MARK: - Instance Properties
    
    /// The description of this value.
    @inlinable
    public var description: String {
        let sign = self.isPositive ? "" : "-"
        
        if self.isNaN { return sign + "nan" }
        if self.isInfinite { return sign + "inf" }
        
        if self.denominator == 1 { return self.numerator.description }
        
        return "\(self.numerator)/\(self.denominator)"
    }
    
    /// The absolute value.
    public var magnitude: Fractional {
        Fractional(isPositive: true, numerator: self.numerator, denominator: self.denominator)
    }
    
    /// Determine whether the `Fractional` is finite.
    @inline(__always)
    public var isFinite: Bool {
        self.denominator != 0
    }
    
    /// Determine whether the `Fractional` is infinite.
    ///
    /// negative infinite is also infinite.
    @inline(__always)
    public var isInfinite: Bool {
        self.denominator == 0
    }
    
    /// Determine whether the `Fractional` is *not a number*.
    ///
    /// This is defined as the same as `undefined`.
    @inline(__always)
    public var isNaN: Bool {
        self.numerator == 0 && self.denominator == 0
    }
    
    /// Determine whether the `Fractional` is `0`.
    @inline(__always)
    public var isZero: Bool {
        self.numerator == 0
    }
    
    
    // MARK: - Type Properties
    
    /// `e`.
    @inline(__always)
    public static var e: Fractional {
        let numerator: Integer = 27_182_818_284_590_452
        return Fractional(isPositive: true, numerator: numerator, denominator: .init(10e16))
    }
    
    /// The (positive) infinity value, which is `1 / 0`.
    ///
    /// However, please note that it is `infinity` for `n / 0` where `n ≠ 0`.
    @inline(__always)
    public static var infinity: Fractional {
        Fractional(isPositive: true, numerator: 1, denominator: 0)
    }
    
    /// The *not a number* value, which is `0 / 0`.
    ///
    /// This is defined as the same as `undefined`.
    @inline(__always)
    public static var nan: Fractional {
        Fractional(isPositive: true, numerator: 0, denominator: 0)
    }
    
    /// The `pi` value.
    @inline(__always)
    public static var pi: Fractional {
        let numerator: Integer = 31_415_926_535_897_932
        return Fractional(isPositive: true, numerator: numerator, denominator: .init(10e16))
    }
    
    /// The `0` value.
    ///
    /// The value was set to `0 / 1`.
    @inline(__always)
    public static var zero: Fractional {
        Fractional(isPositive: true, numerator: 0, denominator: 1)
    }
    
    
    // MARK: - Initializers
    
    /// Initialize with the given numerator and denominator, both in `FloatingPoint`.
    ///
    /// Exact results may be obtained.
    public init(floatNumerator: FloatingPoint, floatDenominator: FloatingPoint) {
        let powerExp = Fractional.leastCommonMultiple(.init(floatNumerator.significandBitPattern), .init(floatNumerator.significandBitPattern))
        let power = pow(2, Fractional.FloatingPoint(powerExp))
        self.init(isPositive: (floatNumerator >= 0) == (floatDenominator >= 0), numerator: .init(floatNumerator * power), denominator: .init(floatDenominator * power))
    }
    
    /// Initialize with a `BinaryInteger`.
    @inline(__always)
    public init(_ value: some BinaryInteger) {
        self.init(__isPositive: value >= 0, numerator: Integer(value.magnitude), denominator: 1)
    }
    
    /// Initialize with a `BinaryFloatingPoint`.
    ///
    /// - Parameters:
    ///   - value: The input value.
    @inlinable
    public init(_ value: some BinaryFloatingPoint) {
        self.init(value, approximate: false)
    }
    
    /// Initialize with a `BinaryFloatingPoint`.
    ///
    /// - Parameters:
    ///   - value: The input value.
    ///   - approximate: A boolean value determining whether approximation was forced to be used.
    ///   - precision: The maximum number of elements in dList.
    @inline(__always)
    public init(_ value: some BinaryFloatingPoint, approximate: Bool = false, to precision: Int = 20) {
        self = FloatingPoint(value).fraction(approximate: approximate, to: precision)
    }
    
    /// Initialize with a `BinaryFloatingPoint`.
    ///
    /// Exact results can be obtained.
    public init<T>(exactly value: T) where T: BinaryFloatingPoint {
        if let fixedValue = value as? (any FixedWidthInteger) {
            var power = pow(2, Self.FloatingPoint(value.significandWidth))
            let maxValue = type(of: fixedValue).max
            let max = FloatingPoint(maxValue)
            while Self.FloatingPoint(value) * power > max {
                power /= 2
            }
            
            self.init(isPositive: value.sign == .plus, numerator: .init(Self.FloatingPoint(value) * power), denominator: .init(power))
        } else {
            let power = pow(2, Self.FloatingPoint(value.significandWidth))
            self.init(isPositive: value.sign == .plus, numerator: .init(Self.FloatingPoint(value) * power), denominator: .init(power))
        }
    }
    
    /// Initialize and make it `0`.
    @inline(__always)
    public init() {
        self.init(__isPositive: true, numerator: 0, denominator: 1)
    }
    
    /// Initialize with a `String`.
    public init?(_ value: String) {
        let isPositive = !value.hasPrefix("-")
        let value = (value.hasPrefix("-") || value.hasPrefix("+")) ? String(value.dropFirst()) : value
        
        if value.contains(".") {
            // initialize with standard floating point instance.
            guard let intPart = Integer(String(value[value.startIndex..<value.firstIndex(of: ".")!])) else { return nil }
            let decimalPartString = value[value.index(after: value.firstIndex(of: ".")!)..<value.endIndex]
            guard let decimalPart = Integer(String(decimalPartString)) else { return nil }
            
            self = Fractional(isPositive: isPositive, numerator: intPart, denominator: 1) + Fractional(isPositive: isPositive, numerator: decimalPart, denominator: .init(pow(10, Fractional.FloatingPoint(decimalPartString.count))))
        } else if value.contains("/") {
            guard let numerator = Integer(String(value[value.startIndex..<value.firstIndex(of: "/")!])) else { return nil }
            guard let denominator = Integer(String(value[value.index(after: value.firstIndex(of: "/")!)..<value.endIndex])) else { return nil }
            
            self.init(isPositive: isPositive, numerator: numerator, denominator: denominator)
        } else {
            guard let value = Integer(value) else { return nil }
            
            self.init(isPositive: isPositive, numerator: value, denominator: 1)
        }
    }
    
    /// Initialize with itself. Sometimes useful.
    ///
    /// Rules to be applied:
    /// - `denominator` would be made positive
    /// - Divide the `numerator` and `denominator` with the greatest common factor.
    public init(_ value: Fraction) {
        self.init(__isPositive: value.isPositive, numerator: value.numerator, denominator: value.denominator)
    }
    
    /// Conforming to `ExpressibleByIntegerLiteral`.
    ///
    /// This is not the designed initializer. Use `init(_ value: Integer)` instead.
    public init(integerLiteral value: Int) {
        self.init(__isPositive: value.signum() == 1, numerator: Integer(value.magnitude), denominator: 1)
    }
    
    /// Conforming to `ExpressibleByFloatLiteral`.
    ///
    /// This is not the designed initializer. Use `init(_ value: PreciseFloat)` instead.
    @inlinable
    public init(floatLiteral value: FloatLiteralType) {
        self.init(FloatingPoint(value))
    }
    
    /// Creates an instance that exactly represents the given binary integer.
    public init?(exactly source: some BinaryInteger) {
        guard let exactNumerator = Integer(exactly: source.magnitude) else { return nil }
        self.init(__isPositive: source.signum() != -1, numerator: exactNumerator, denominator: 1)
    }
    
    /// Creates an instance given the numerator and denominator.
    public init(numerator: some BinaryInteger, denominator: some BinaryInteger) {
        self.init(isPositive: (numerator >= 0) == (denominator >= 0), numerator: Integer(numerator), denominator: Integer(denominator))
    }
    
    
    // MARK: - Instance Methods
    
    /// Reduce (round) the `Fractional`.
    ///
    ///     1000000 / 3000001 -> 1 / 3
    ///
    /// - Warning: Precision may be lost.
    ///
    /// - Remark: It was turned into `FloatingPoint` and turned back into `Fractional`.
    ///
    /// - Experiment: Sample with 10,000 candidates, results in a loss of precision of maximum of 8.6788e-5.
    public func approximated() -> Fractional {
        FloatingPoint(self).fraction(approximate: true)
    }
    
    /// Replaces this value with its additive inverse.
    @inlinable
    public mutating func negate() {
        self = self.opposite()
    }
    
    /// Returns the square root of the value, rounded to a representable value.
    @inlinable
    public func squareRoot() -> Fractional {
        Fractional(floatNumerator: FloatingPoint(self.numerator).squareRoot() * (self.isPositive ? 1 : -1), floatDenominator: FloatingPoint(self.denominator).squareRoot())
    }
    
    /// The reciprocal.
    public func reciprocal() -> Fractional {
        Fractional(isPositive: self.isPositive, numerator: self.denominator, denominator: self.numerator)
    }
    
    /// Returns the remainder of this value divided by the given value.
    public func remainder(dividingBy other: Fractional) -> Fractional {
        let (lhsNumerator, rhsNumerator, denominator) = Fractional.commonDenominator(self, other)
        return Fractional(isPositive: self.isPositive == other.isPositive, numerator: lhsNumerator % rhsNumerator, denominator: denominator)
    }
    
    /// The value with same magnitude, but different sign.
    public func opposite() -> Fractional {
        Fractional(isPositive: !self.isPositive, numerator: self.numerator, denominator: self.denominator)
    }
    
    
    // MARK: - Type Methods
    
    /// Reduce the ``numerator`` and ``denominator`` set to make it look better.
    ///
    /// Rules applied:
    /// - Divide the ``numerator`` and ``denominator`` with the greatest common factor.
    @inlinable
    public static func reduce(numerator: Integer, denominator: Integer) -> (numerator: Integer, denominator: Integer) {
        if denominator == 0 { return (numerator, denominator) }
        if numerator == denominator { return (1, 1) }
        let divisor = greatestCommonDivisor(numerator, denominator)
        guard divisor != 0 else { return (numerator, 0) }
        
        return (numerator / divisor, denominator / divisor)
    }
    
    /// Calculate the greatest common factor of two values.
    @inlinable
    public static func greatestCommonDivisor(_ lhs: Integer, _ rhs: Integer) -> Integer {
//        var lhs = lhs
//        var rhs = rhs
//        while rhs != 0 { (lhs, rhs) = (rhs, lhs % rhs) }
//        return lhs
        
        // source: [Swift Numerics](https://github.com/apple/swift-numerics/blob/main/Sources/IntegerUtilities/GCD.swift)
        guard lhs != 0 else { return rhs }
        guard rhs != 0 else { return lhs }
        
        var x = lhs
        var y = rhs
        
        let xtz = x.trailingZeroBitCount
        let ytz = y.trailingZeroBitCount
        
        y >>= ytz
        
        // The binary GCD algorithm
        //
        // After the right-shift in the loop, both x and y are odd. Each pass removes
        // at least one low-order bit from the larger of the two, so the number of
        // iterations is bounded by the sum of the bit-widths of the inputs.
        //
        // A tighter bound is the maximum bit-width of the inputs, which is achieved
        // by odd numbers that sum to a power of 2, though the proof is more involved.
        repeat {
            x >>= x.trailingZeroBitCount
            if x < y { swap(&x, &y) }
            x -= y
        } while x != 0
        
        return y << min(xtz, ytz)
    }
    
    /// Calculate the least common multiple of two values.
    @inlinable
    public static func leastCommonMultiple(_ lhs: Integer, _ rhs: Integer) -> Integer {
        if lhs == rhs { return lhs }
        
        let gcd = greatestCommonDivisor(lhs, rhs)
        if lhs < rhs {
            return (lhs / gcd) * rhs
        } else {
            return (rhs / gcd) * lhs
        }
    }
    
    /// Calculate the common denominator of two fractions.
    @inlinable
    public static func commonDenominator(_ lhs: Fractional, _ rhs: Fractional) -> (lhsNumerator: Integer, rhsNumerator: Integer, denominator: Integer) {
        if lhs == 0 { return (0, rhs.numerator, rhs.denominator) }
        if rhs == 0 { return (0, lhs.numerator, lhs.denominator) }
        if lhs.denominator == rhs.denominator { return (lhs.numerator, rhs.numerator, lhs.denominator) }
        
        let denominator = leastCommonMultiple(lhs.denominator, rhs.denominator)
        
        let lhsNumerator = lhs.numerator * denominator / lhs.denominator
        let rhsNumerator = rhs.numerator * denominator / rhs.denominator
        
        return (lhsNumerator, rhsNumerator, denominator)
    }
    
    
    // MARK: - Operator Functions
    
    /// Addition of two `Fractional`.
    public static func + (lhs: Fraction, rhs: Fraction) -> Fractional {
        if lhs.isNaN || rhs.isNaN { return Fractional.nan }
        if lhs.isInfinite || rhs.isInfinite { return Fractional.infinity }
        
        switch (lhs.isPositive, rhs.isPositive) {
        case (true, false):
            return lhs - rhs.magnitude
        case (false, true):
            return rhs - lhs.magnitude
        default:
            let (lhsNumerator, rhsNumerator, denominator) = Fractional.commonDenominator(lhs, rhs)
            return Fractional(isPositive: lhs.isPositive, numerator: lhsNumerator + rhsNumerator, denominator: denominator)
        }
    }
    
    /// Addition of two `Fractional`, and stores in `lhs`.
    @inlinable
    public static func += (lhs: inout Fractional, rhs: Fractional) {
        lhs = lhs + rhs
    }
    
    /// Subtraction of two `Fractions`.
    public static func - (lhs: Fractional, rhs: Fractional) -> Fractional {
        if lhs.isNaN || rhs.isNaN { return Fractional.nan }
        if lhs == rhs { return 0 }
        if lhs.isInfinite || rhs.isInfinite {
            switch (lhs.isInfinite, rhs.isInfinite) {
            case (true, true):
                return Fractional.nan
            case (true, false):
                return Fractional.infinity
            case (false, true):
                return -Fractional.infinity
            case (false, false):
                fatalError("unexpected")
            }
        }
        
        switch (lhs.isPositive, rhs.isPositive) {
        case (true, false):
            return lhs.magnitude + rhs.magnitude
        case (false, true):
            return (rhs.magnitude + lhs.magnitude).opposite()
        default:
            let (lhsNumerator, rhsNumerator, denominator) = Fractional.commonDenominator(lhs, rhs)
            if lhsNumerator >= rhsNumerator {
                return Fractional(isPositive: lhs.isPositive, numerator: lhsNumerator - rhsNumerator, denominator: denominator)
            } else {
                return Fractional(isPositive: !lhs.isPositive, numerator: rhsNumerator - lhsNumerator, denominator: denominator)
            }
        }
    }
    
    /// Subtraction of two `Fractional`, and stores in `lhs`.
    @inlinable
    public static func -= (lhs: inout Fractional, rhs: Fractional) {
        lhs = lhs - rhs
    }
    
    /// Multiplication of two `Fractions`.
    public static func * (lhs: Fractional, rhs: Fractional) -> Fractional {
        if lhs.isNaN || rhs.isNaN { return Fractional.nan }
        
        // Multiplication of two positive values.
        if lhs.isInfinite || rhs.isInfinite { return Fractional.infinity }
        if lhs == 0 || rhs == 0 { return Fractional.zero }
        
        return Fractional(isPositive: lhs.isPositive == rhs.isPositive, numerator: lhs.numerator * rhs.numerator, denominator: lhs.denominator * rhs.denominator)
    }
    
    /// Multiplication of two `Fractions`, and stores in `lhs`.
    @inlinable
    public static func *= (lhs: inout Fractional, rhs: Fractional) {
        lhs = lhs * rhs
    }
    
    /// Division of two `Fractions`.
    @inlinable
    public static func / (lhs: Fractional, rhs: Fractional) -> Fractional {
        if lhs.isNaN || rhs.isNaN { return Fractional.nan }
        if lhs == 0 { return 0 }
        if lhs.isInfinite || rhs.isInfinite {
            switch (lhs.isInfinite, rhs.isInfinite) {
            case (true, true):
                return Fractional.nan
            case (true, false):
                return Fractional.infinity
            case (false, true):
                return Fractional.zero
            case (false, false):
                fatalError("unexpected")
            }
        }
        
        return lhs * rhs.reciprocal()
    }
    
    /// Division of two `Fractional`, and stores in `lhs`.
    @inlinable
    public static func /= (lhs: inout Fractional, rhs: Fractional) {
        lhs = lhs / rhs
    }
    
    
    // MARK: - Comparing two instances
    
    @inlinable
    public static func < (lhs: Fractional, rhs: Fractional) -> Bool {
        switch (lhs.isPositive, rhs.isPositive) {
        case (true, false):
            false
        case (false, true):
            true
        default:
            FloatingPoint(lhs.numerator) / FloatingPoint(lhs.denominator) < FloatingPoint(rhs.numerator) / FloatingPoint(rhs.denominator)
        }
    }
    
    @inlinable
    public static func == (lhs: Fractional, rhs: Fractional) -> Bool {
        lhs.isPositive == rhs.isPositive && lhs.numerator == rhs.numerator && lhs.denominator == rhs.denominator
    }
}


// MARK: - Supporting Extensions

public extension BinaryFloatingPoint {

    /// Create an instance initialized to `Fractional`.
    init(_ value: Fractional) {
        self.init(signOf: value.isPositive ? 1 : -1, magnitudeOf: Self(value.numerator) / Self(value.denominator))
    }

    /// Returns the Fractional form of a float, in the form of Fractional.
    ///
    /// > Example:
    /// >
    /// > ```swift
    /// > 0.5.fraction()!
    /// > // 1/2
    /// > ```
    ///
    /// If the length of decimal part the float is less or equal to 10 or it is a recruiting decimal, a precise fraction would be produced.
    ///
    /// Otherwise, approximate x by
    ///
    ///                       1
    ///        d1 + ----------------------
    ///                        1
    ///           d2 + -------------------
    ///                          1
    ///              d3 + ----------------
    ///                            1
    ///                 d4 + -------------
    ///                             1
    ///                    d5 + ----------
    ///                               1
    ///                        d6 + ------
    ///                                 1
    ///                           d7 + ---
    ///                                 d8
    ///
    /// - Parameters:
    ///   - approximate: A boolean value determining whether approximation was forced to be used.
    ///   - precision: The maximum number of elements in dList.
    ///   - container: The type of container for the resulting `Fractional`.
    ///
    /// - Returns: `Fractional`
    internal func fraction(approximate: Bool = false, to precision: Int = 20) -> Fractional where Self: LosslessStringConvertible {
        guard self.isFinite else {
            guard !self.isNaN else { fatalError() }
            if self.sign == .plus {
                return Fractional.infinity
            } else {
                return -Fractional.infinity
            }
        }
        
        guard Self(UInt(self.magnitude)) != self.magnitude else {
            if self >= 0 {
                return Fractional(UInt(self.magnitude))
            } else {
                return Fractional(UInt(self.magnitude)).opposite()
            }
        }

        // if simple
        if !approximate && self < 10e10 {
            return Fractional(exactly: self)
        }

        // Approximate x
        var content = Fractional.FloatingPoint(self)
        var dList: [UInt] = []

        while content != 0 && content.isFinite && dList.count <= precision {
            dList.append(UInt(content))
            content = (1 / (content - Fractional.FloatingPoint(dList.last!)))

            guard dList.last! < 10000 else {
                dList.removeLast()
                break
            }
        }

        var numerator: UInt = 1
        var denominator: UInt = dList.last!

        var i = 0
        while i + 1 < dList.count {
            i += 1
            let index = dList.count - 1 - i

            // add content
            numerator += denominator * dList[index]

            // reciprocal
            swap(&numerator, &denominator)
        }

        // take reciprocal, as once more was done in loop
        swap(&numerator, &denominator)

        // self check
        return Fractional(isPositive: self >= 0, numerator: numerator, denominator: denominator)
    }
}


fileprivate extension UnsignedInteger {

    init(_ value: Fractional) {
        self.init((value.isPositive ? 1 : -1) * Fractional.FloatingPoint(value.numerator) / Fractional.FloatingPoint(value.denominator))
    }

}


// MARK: - Supporting Functions

/// Raise the power of a `Fractional`.
@inlinable
public func pow(_ lhs: Fraction, _ rhs: Fraction) -> Fraction {
    .init(pow(Fraction.FloatingPoint(lhs), Fraction.FloatingPoint(rhs)))
}

/// The square root.
@inlinable
public func sqrt(_ x: Fractional) -> Fractional {
    x.squareRoot()
}


public typealias Fractional = Fraction
