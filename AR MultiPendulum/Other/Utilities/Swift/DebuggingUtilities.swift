//
//  DebuggingUtilities.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/21/21.
//

import Foundation

fileprivate let doingDebugLabels = true
fileprivate let bypassingMetalAPIValidation = false

@inline(__always)
func debugLabel(_ closure: (() -> Void)) {
    #if DEBUG
    if doingDebugLabels {
        closure()
    }
    #endif
}

@inline(__always)
func debugLabelReturn<T>(_ defaultOutput: T, _ closure: (() -> T)) -> T {
    #if DEBUG
    if doingDebugLabels {
        return closure()
    } else {
        return defaultOutput
    }
    #else
    return defaultOutput
    #endif
}

@inline(__always)
func debugLabelConditionalReturn<T>(_ closure1: (() -> T), else closure2: (() -> T)) -> T {
    #if DEBUG
    if doingDebugLabels {
        return closure1()
    } else {
        return closure2()
    }
    #else
    return closure2()
    #endif
}

@inline(__always)
func onlyForMetalAPIValidation(_ closure: (() -> Void)) {
    #if DEBUG
    if !bypassingMetalAPIValidation {
        closure()
    }
    #endif
}
