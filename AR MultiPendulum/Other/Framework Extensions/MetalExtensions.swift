//
//  MetalExtensions.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 6/5/21.
//

import Metal

extension MTLDevice {
    func makeComputePipelineState(descriptor: MTLComputePipelineDescriptor) -> MTLComputePipelineState {
        try! makeComputePipelineState(descriptor: descriptor, options: [], reflection: nil)
    }
}

extension MTLResource {
    var optLabel: String {
        get { debugLabelReturn("") { label! } }
        set { debugLabel { label = newValue } }
    }
}

extension MTLCommandQueue {
    var optLabel: String {
        get { debugLabelReturn("") { label! } }
        set { debugLabel { label = newValue } }
    }
    
    func makeDebugCommandBuffer() -> MTLCommandBuffer {
        debugLabelConditionalReturn ({
            let descriptor = MTLCommandBufferDescriptor()
            descriptor.errorOptions = .encoderExecutionStatus
            
            let output = makeCommandBuffer(descriptor: descriptor)!
            output.addCompletedHandler{ $0.printErrors() }
            
            return output
        }, else: {
            return makeCommandBuffer()!
        })
    }
}

extension MTLCommandBuffer {
    var optLabel: String {
        get { debugLabelReturn("") { label! } }
        set { debugLabel { label = newValue } }
    }
    
    func pushOptDebugGroup(_ string: String) {
        debugLabel { pushDebugGroup(string) }
    }
    
    func popOptDebugGroup() {
        debugLabel { popDebugGroup() }
    }
}

extension MTLCommandEncoder {
    var optLabel: String {
        get { debugLabelReturn("") { label! } }
        set { debugLabel { label = newValue } }
    }
    
    func pushOptDebugGroup(_ string: String) {
        debugLabel { pushDebugGroup(string) }
    }
    
    func popOptDebugGroup() {
        debugLabel { popDebugGroup() }
    }
}

extension MTLComputePipelineDescriptor {
    var optLabel: String {
        get { debugLabelReturn("") { label! } }
        set { debugLabel { label = newValue } }
    }
}

extension MTLRenderPipelineDescriptor {
    var optLabel: String {
        get { debugLabelReturn("") { label! } }
        set { debugLabel { label = newValue } }
    }
}

extension MTLDepthStencilDescriptor {
    var optLabel: String {
        get { debugLabelReturn("") { label! } }
        set { debugLabel { label = newValue } }
    }
}

extension MTLRasterizationRateMapDescriptor {
    var optLabel: String {
        get { debugLabelReturn("") { label! } }
        set { debugLabel { label = newValue } }
    }
}

extension MTLLibrary {
    func makeComputePipeline<T>(_ type: T.Type, name: String) -> MTLComputePipelineState {
        makeComputePipeline(type, name: name, function: makeFunction(name: name)!)
    }
    
    func makeComputePipeline<T>(_ type: T.Type, name: String, function computeFunction: MTLFunction) -> MTLComputePipelineState {
        debugLabelConditionalReturn({
            let computePipelineDescriptor = MTLComputePipelineDescriptor()
            computePipelineDescriptor.computeFunction = computeFunction
            computePipelineDescriptor.label = String(describing: type) + " " + name + " Pipeline"
            
            return device.makeComputePipelineState(descriptor: computePipelineDescriptor)
        }, else: {
            return try! device.makeComputePipelineState(function: computeFunction)
        })
    }
}

extension MTLSize: ExpressibleByIntegerLiteral, ExpressibleByArrayLiteral {
    
    public init(integerLiteral value: IntegerLiteralType) {
        self = MTLSizeMake(value, 1, 1)
    }
    
    public typealias ArrayLiteralElement = Int
    
    @inline(__always)
    public init(arrayLiteral elements: ArrayLiteralElement...) {
        switch elements.count {
        case 1:  self = MTLSizeMake(elements[0], 1, 1)
        case 2:  self = MTLSizeMake(elements[0], elements[1], 1)
        case 3:  self = MTLSizeMake(elements[0], elements[1], elements[2])
        default: fatalError("A MTLSize must not exceed three dimensions!")
        }
    }
    
}

extension MTLCommandBuffer {
    
    func printErrors() {
        debugLabel {
            for log in logs {
                print(log.description)
                
                let encoderLabel = log.encoderLabel ?? "Unknown Label"
                print("Faulting encoder \"\(encoderLabel)\"")
                
                guard let debugLocation = log.debugLocation,
                      let functionName = debugLocation.functionName else {
                    return
                }
                print("Faulting function \(functionName):\(debugLocation.line):\(debugLocation.column)")
            }
            
            if let error = error as NSError?,
               let encoderInfos = error.userInfo[MTLCommandBufferEncoderInfoErrorKey] as? [MTLCommandBufferEncoderInfo] {
                print()
                
                switch status {
                case .notEnqueued: print("Status: not enqueued")
                case .enqueued:    print("Status: enqueued")
                case .committed:   print("Status: committed")
                case .scheduled:   print("Status: scheduled")
                case .completed:   print("Status: completed")
                case .error:       print("Status: error")
                @unknown default: fatalError("This status is not possible!")
                }
                
                print("Error code: \(error.code)")
                print("Description: \(error.localizedDescription)")
                
                if let reason = error.localizedFailureReason {
                    print("Failure reason: \(reason)")
                }
                
                if let options = error.localizedRecoveryOptions {
                    for i in 0..<options.count {
                        print("Recovery option \(i): \(options[i])")
                    }
                }
                
                if let suggestion = error.localizedRecoverySuggestion {
                    print("Recovery suggestion: \(suggestion)")
                }
                
                print()
                
                for info in encoderInfos {
                    switch info.errorState {
                    case .faulted:   print(info.label + " faulted")
                    case .affected:  print(info.label + " affected")
                    case .completed: print(info.label + " completed")
                    case .unknown:   print(info.label + " error state unknown")
                    case .pending:   print(info.label + " unknown")
                    @unknown default: fatalError("This error state is not possible!")
                    }
                    
                    for signpost in info.debugSignposts {
                        print("Signpost:", signpost)
                    }
                }
                
                print()
            }
        }
    }
    
}
