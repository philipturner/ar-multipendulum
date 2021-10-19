//
//  PendulumStateEquations.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/2/21.
//

import ARHeadsetKit

final class PendulumStateEquations {
    var masses: [Double] = []
    var lengths: [Double] = []
    
    var massSums: [Double]
    var massSumsTimesLengthProducts: [[Double]]
    var massSumsTimesLengthsTimesGravity: [Double]
    
    var inputLayer: UnsafeMutablePointer<Double>
    var outputLayer: UnsafeMutablePointer<Double>
    
    var inputDerivativeLayer: UnsafeMutablePointer<Double>
    var outputDerivativeLayer: UnsafeMutablePointer<Double>
    var transientPartialDerivatives: UnsafeMutablePointer<Double>
    
    var constantPotential: Double = .nan
    var pendulumCapacity: Int
    
    init() {
        let pendulumCapacity = 32
        self.pendulumCapacity = pendulumCapacity
        
        massSums                    = Array(capacity: pendulumCapacity)
        massSumsTimesLengthProducts = Array(capacity: pendulumCapacity)
        massSumsTimesLengthsTimesGravity = Array(repeating: .nan, count: pendulumCapacity)
        
        for _ in 0..<pendulumCapacity {
            massSumsTimesLengthProducts.append(Array(repeating: .nan, count: pendulumCapacity))
        }
        
        @inline(__always)
        func getBuffer(length: Int) -> UnsafeMutablePointer<Double> {
            malloc(length)!.assumingMemoryBound(to: Double.self)
        }
        
        transientPartialDerivatives = getBuffer(length: pendulumCapacity * MemoryLayout<Double>.stride)
        
        let rowSize = (pendulumCapacity + 1) * MemoryLayout<Double>.stride
        let layerSize = pendulumCapacity * rowSize
        inputLayer  = getBuffer(length: layerSize)
        outputLayer = getBuffer(length: layerSize)
        
        let derivativeLayerSize = pendulumCapacity * layerSize
        inputDerivativeLayer  = getBuffer(length: derivativeLayerSize)
        outputDerivativeLayer = getBuffer(length: derivativeLayerSize)
    }
    
    func setSimulation(_ numPendulums: Int, _ gravitationalAccelerationHalf: Double, masses: [Double], lengths: [Double]) {
        ensurePendulumCapacity(capacity: numPendulums)
        
        self.masses = masses
        self.lengths = lengths
        
        massSums.removeAll(keepingCapacity: true)
        var accumulatedMass = Double(0)
        
        for i in 1...numPendulums {
            accumulatedMass += masses[numPendulums - i]
            massSums.append(accumulatedMass)
        }
        
        massSums.reverse()
        
        for i in 0..<numPendulums {
            var output = massSums[i] * lengths[i]
            output *= -gravitationalAccelerationHalf
            
            massSumsTimesLengthsTimesGravity[i] = output
        }
        
        for i in 0..<numPendulums {
            let length_i = lengths[i]
            
            for j in 0..<numPendulums {
                let massSum = massSums[max(i, j)]
                let lengthProduct = length_i * lengths[j]
                
                massSumsTimesLengthProducts[i][j] = massSum * lengthProduct
            }
        }
        
        // Adding `constantPotential` to the potential energy
        // ensures that potential energy is always greater
        // than or equal to zero.
        
        constantPotential = 0
        var accumulatedLength = Double(0)
        
        for i in 0..<numPendulums {
            accumulatedLength += lengths[i]
            constantPotential += accumulatedLength * masses[i]
        }
        
        constantPotential *= gravitationalAccelerationHalf
    }
    
}

extension PendulumStateEquations {
    
    enum BufferType {
        case pendulum
    }
    
    func ensureBufferCapacity(type: BufferType, capacity: Int) {
        let newCapacity = roundUpToPowerOf2(capacity)
        
        switch type {
        case .pendulum: ensurePendulumCapacity(capacity: newCapacity)
        }
    }
    
    private func ensurePendulumCapacity(capacity: Int) {
        guard pendulumCapacity < capacity else {
            return
        }
        
        pendulumCapacity = capacity
        
        massSums                    = Array(capacity: capacity)
        massSumsTimesLengthProducts = Array(capacity: capacity)
        massSumsTimesLengthsTimesGravity = Array(repeating: .nan, count: capacity)
        
        for _ in 0..<capacity {
            massSumsTimesLengthProducts.append(Array(repeating: .nan, count: capacity))
        }
        
        
        
        @inline(__always)
        func setBuffer(_ input: inout UnsafeMutablePointer<Double>, length: Int) {
            free(input)
            input = malloc(length)!.assumingMemoryBound(to: Double.self)
        }
        
        setBuffer(&transientPartialDerivatives, length: capacity * MemoryLayout<Double>.stride)
        
        let rowSize = (capacity + 1) * MemoryLayout<Double>.stride
        let layerSize = capacity * rowSize
        setBuffer(&inputLayer,  length: layerSize)
        setBuffer(&outputLayer, length: layerSize)
        
        let derivativeLayerSize = capacity * layerSize
        setBuffer(&inputDerivativeLayer,  length: derivativeLayerSize)
        setBuffer(&outputDerivativeLayer, length: derivativeLayerSize)
    }
    
}
