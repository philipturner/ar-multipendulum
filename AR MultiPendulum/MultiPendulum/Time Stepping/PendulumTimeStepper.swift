//
//  PendulumTimeStepper.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/2/21.
//

import simd

final class PendulumTimeStepper {
    var pendulumRenderer: PendulumRenderer
    var stateEquations: PendulumStateEquations
    var numPendulums: Int
    var gravitationalAccelerationHalf: Double
    
    var energy: Double
    var energyRange: Double
    var maxError: Double
    
    static let rkdpCoefficients: [[Double]] = [
        [],
        [    1.0 / 5],
        [    3.0 / 40,        9.0 / 40],
        [   44.0 / 45,      -56.0 / 15,      32.0 / 9],
        [19372.0 / 6561, -25360.0 / 2187, 64448.0 / 6561, -212.0 / 729],
        [ 9017.0 / 3168,   -355.0 / 33,   46732.0 / 5247,   49.0 / 176, -5103.0 / 18656]
    ]
    
    static let weights: [Double] = [
           35.0 / 384,
                0,
          500.0 / 1113,
          125.0 / 192,
        -2187.0 / 6784,
           11.0 / 84
    ]
    
    static let altWeights: [Double] = [
          5197.0 / 57600,
                 0,
          7571.0 / 16695,
           393.0 / 640,
        -92097.0 / 339200,
           187.0 / 2100,
             1.0 / 40
    ]
    
    var lastRecursionLevel = 0
    var recursionLevelStreak = 0
    
    var cachedForces: [Double] = []
    
    init(pendulumRenderer: PendulumRenderer, energy: Double) {
        self.pendulumRenderer = pendulumRenderer
        self.energy = energy
        
        stateEquations = pendulumRenderer.stateEquations
        numPendulums = pendulumRenderer.numPendulums
        gravitationalAccelerationHalf = pendulumRenderer.gravitationalAccelerationHalf
        
        energyRange = 5e-4 * energy
        maxError = 1e-4 * Double(numPendulums) * pendulumRenderer.combinedPendulumLength
    }
    
    func reset(pendulumRenderer: PendulumRenderer, energy: Double) {
        numPendulums = pendulumRenderer.numPendulums
        gravitationalAccelerationHalf = pendulumRenderer.gravitationalAccelerationHalf
        
        self.energy = energy
        self.energyRange = 5e-4 * energy
        self.maxError = 1e-4 * Double(numPendulums) * pendulumRenderer.combinedPendulumLength
        
        lastRecursionLevel = 0
        recursionLevelStreak = 0
    }
    
}
