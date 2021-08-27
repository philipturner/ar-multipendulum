//
//  DebuggingUtilities.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/21/21.
//

import Foundation

fileprivate let doingDebugLabels = true
fileprivate let bypassingMetalAPIValidation = false

func debugLabel(_ closure: (() -> Void)) {
    #if DEBUG
    if doingDebugLabels {
        closure()
    }
    #endif
}

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

func onlyForMetalAPIValidation(_ closure: (() -> Void)) {
    #if DEBUG
    if !bypassingMetalAPIValidation {
        closure()
    }
    #endif
}
