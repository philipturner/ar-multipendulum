//
//  MemoryUtilities.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/21/21.
//

import Foundation

extension Array {
    init(capacity: Int) {
        self = .init(unsafeUninitializedCapacity: capacity){ _, _ in }
    }
    
    init(unsafeUninitializedCount count: Int) {
        self = .init(unsafeUninitializedCapacity: count){ $1 = count }
    }
    
    var unsafePointer: UnsafePointer<Element>? {
        self.withUnsafeBufferPointer{ $0 }.baseAddress
    }
    
    var unsafeMutablePointer: UnsafeMutablePointer<Element>? { mutating get {
        self.withUnsafeMutableBufferPointer{ $0 }.baseAddress
    } }
}

extension Range where Bound == Int {
    init(_ range: CFRange) {
        self = range.location..<range.location + range.length
    }
    
    var asCFRange: CFRange {
        .init(location: lowerBound, length: upperBound - lowerBound)
    }
}

func makePointer<T>(to reference: UnsafeMutablePointer<T>) -> UnsafeMutablePointer<T> { reference }

func memset_pattern4<T>(_ __b: UnsafeMutablePointer<T>!, _ __pattern4: T, count: Int) {
    assert(MemoryLayout<T>.stride == 4)
    
    var patternRef = __pattern4
    memset_pattern4(__b, &patternRef, count << 2)
}

func memset_pattern8<T>(_ __b: UnsafeMutablePointer<T>!, _ __pattern8: T, count: Int) {
    assert(MemoryLayout<T>.stride == 8)
    
    var patternRef = __pattern8
    memset_pattern8(__b, &patternRef, count << 3)
}

func memset_pattern16<T>(_ __b: UnsafeMutablePointer<T>!, _ __pattern16: T, count: Int) {
    assert(MemoryLayout<T>.stride == 16)
    
    var patternRef = __pattern16
    memset_pattern8(__b, &patternRef, count << 4)
}
