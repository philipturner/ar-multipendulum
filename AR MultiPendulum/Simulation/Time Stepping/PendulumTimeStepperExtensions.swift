//
//  PendulumTimeStepperExtensions.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/2/21.
//

import ARHeadsetKit

extension PendulumTimeStepper {
    
    @inline(__always)
    func testShouldReset() throws {
        struct ResetSimulationError: Error { }
        
        if pendulumRenderer.shouldResetSimulation {
            throw ResetSimulationError()
        }
    }
    
    func createFrame(lastState: PendulumState, failed: inout Bool) throws -> [PendulumState] {
        let frameStart = lastState.frameProgress
        let frameEnd   = frameStart + 1
        
        var stateGroup = [lastState]
        try doTimeStep(frameStart: frameStart, frameEnd: frameEnd, states: &stateGroup,
                       recursionLevel: 0, failed: &failed)
        
        if stateGroup.count == 1 {
            return []
        }
        
        stateGroup.removeFirst()
        
        
        
        let numFramesPower = min(7, (numPendulums - 1).leadingZeroBitCount - 55)
        let maxNumFrames = Double(1 << numFramesPower)
        
        func shouldCull(_ state: PendulumState) -> Bool {
            simd_fract(state.frameProgress * maxNumFrames) == 0
        }
        
        if stateGroup.contains(where: { shouldCull($0) }) {
            var newStateGroup = [PendulumState](capacity: stateGroup.count)
            
            for state in stateGroup {
                if shouldCull(state) {
                    newStateGroup.append(state)
                }
            }
            
            if newStateGroup.count == 0 {
                stateGroup = [stateGroup.last!]
            } else {
                stateGroup = newStateGroup
            }
        }
        
        stateGroup[stateGroup.count - 1].normalizeAngles()
        
        return stateGroup
    }
    
    func doTimeStep(frameStart: Double, frameEnd: Double, states: inout [PendulumState],
                    recursionLevel: Int, failed: inout Bool) throws
    {
        if recursionLevel > 32 {
            failed = true
        }
        
        if failed {
            return
        }
        
        func doSmallerTimeStep() throws {
            let frameMiddle = (frameStart + frameEnd) * 0.5
            let nextRecursionLevel = recursionLevel + 1
            
            try doTimeStep(frameStart: frameStart,  frameEnd: frameMiddle, states: &states,
                           recursionLevel: nextRecursionLevel, failed: &failed)
            
            try doTimeStep(frameStart: frameMiddle, frameEnd: frameEnd,    states: &states,
                           recursionLevel: nextRecursionLevel, failed: &failed)
        }
        
        if recursionLevel < lastRecursionLevel {
            var shouldDoSmallerTimeStep: Bool
            
            if recursionLevel == lastRecursionLevel - 1 {
                let halfStreak = recursionLevelStreak >> 1
                
                if halfStreak <= 2 {
                    shouldDoSmallerTimeStep = false
                } else if halfStreak == 3 { // skipping every 1 of 2 attempts to double time step
                    shouldDoSmallerTimeStep = true
                } else if halfStreak == 4 {
                    shouldDoSmallerTimeStep = false
                } else if halfStreak < 8 { // skipping every 3 of 4 attempts to double time step
                    shouldDoSmallerTimeStep = true
                } else if halfStreak == 8 {
                    shouldDoSmallerTimeStep = false
                } else { // skipping every 7 of 8 attempts to double time step
                    shouldDoSmallerTimeStep = halfStreak & 7 != 0
                }
            } else { // not going any larger than twice the current step size
                shouldDoSmallerTimeStep = true
            }
            
            if shouldDoSmallerTimeStep {
                try doSmallerTimeStep()
                return
            }
        }
        
        let lastState = states.last!
        
        var (nextState, error) = try createState(frameStart: frameStart, frameEnd: frameEnd, lastState: lastState)
        var energyDifference = nextState.energy - energy
        
        if error > maxError || abs(energyDifference) > energyRange {
            try doSmallerTimeStep()
            return
        }
        
        var multiplier = Double(1)
        var extremeDeviationCounter = 0
        
        let lastAnglesAndMomenta = (0..<numPendulums).map {
            simd_double2(lastState.angles[$0], lastState.momenta[$0])
        }
        
        let angleAndMomentumDifferences = (0..<numPendulums).map {
            simd_double2(nextState.angles[$0], nextState.momenta[$0]) - lastAnglesAndMomenta[$0]
        }
        
        for i in 0..<6 {
            if i != 0 {
                try testShouldReset()
                
                cachedForces = stateEquations.solveAngularVelocitiesAndForces(numPendulums,
                                                                              nextState.angles,
                                                                              nextState.momenta).forces
            }
            
            var actionChangeVector = simd_double2()
            
            for j in 0..<numPendulums {
                let nextAngleAndMomentum = simd_double2(nextState.angles[j],
                                                        nextState.momenta[j])
                
                let angleAndMomentumDifference = nextAngleAndMomentum - lastAnglesAndMomenta[j]
               
                let forceAndAngularVelocity = simd_double2(cachedForces[j],
                                                           nextState.angularVelocities[j])
                
                actionChangeVector = fma(forceAndAngularVelocity, angleAndMomentumDifference, actionChangeVector)
            }
            
            multiplier *= 1 - energyDifference / (actionChangeVector[1] - actionChangeVector[0])
            
            if multiplier > 1.05 {
                multiplier = 1.05
                extremeDeviationCounter += 1
            
            } else if multiplier < 0.95 {
                multiplier = 0.95
                extremeDeviationCounter += 1
                
            } else {
                extremeDeviationCounter = 0
            }
            
            if extremeDeviationCounter >= 3 {
                try doSmallerTimeStep()
                return
            }
            
            for j in 0..<numPendulums {
                let nextAngleAndMomentum = fma(angleAndMomentumDifferences[j], multiplier, lastAnglesAndMomenta[j])
                
                nextState.angles[j]  = nextAngleAndMomentum.x
                nextState.momenta[j] = nextAngleAndMomentum.y
            }
            
            stateEquations.process(numPendulums, gravitationalAccelerationHalf, state: &nextState)
            energyDifference = nextState.energy - energy
            
            if abs(energyDifference) <= energyRange {
                states.append(nextState)
                
                if recursionLevel == lastRecursionLevel {
                    recursionLevelStreak += 1
                } else {
                    lastRecursionLevel = recursionLevel
                    recursionLevelStreak = 1
                }
                
                return
            }
        }
        
        try doSmallerTimeStep()
    }
    
    typealias CreateStateReturn = (nextState: PendulumState, error: Double)
    
    func createState(frameStart: Double, frameEnd: Double, lastState: PendulumState) throws -> CreateStateReturn {
        let timeStep = (frameEnd - frameStart) / 60
        
        var anglesAndMomenta = [simd_double2](repeating: .zero, count: numPendulums)
        var angularVelocitiesAndForces = [[simd_double2]](capacity: 6)
        
        for i in 0..<6 {
            let rkdpCoefficients_i = Self.rkdpCoefficients[i]
            
            for j in 0..<i {
                let ijValue = rkdpCoefficients_i[j]
                let angularVelocitiesAndForces_j = angularVelocitiesAndForces[j]
                
                for k in 0..<numPendulums {
                    anglesAndMomenta[k] = fma(angularVelocitiesAndForces_j[k], ijValue, anglesAndMomenta[k])
                }
            }
            
            for j in 0..<numPendulums {
                let lastAngleAndMomentum = simd_double2(lastState.angles[j],
                                                        lastState.momenta[j])
                
                anglesAndMomenta[j] = fma(anglesAndMomenta[j], timeStep, lastAngleAndMomentum)
            }
            
            try testShouldReset()
            
            let separatedAngularVelocitiesAndForces =
                stateEquations.solveAngularVelocitiesAndForces(numPendulums,
                                                               anglesAndMomenta.map{ $0.x },
                                                               anglesAndMomenta.map{ $0.y })
            
            angularVelocitiesAndForces.append((0..<numPendulums).map {
                simd_double2(separatedAngularVelocitiesAndForces.angularVelocities[$0],
                             separatedAngularVelocitiesAndForces.forces[$0])
            })
            
            anglesAndMomenta = Array(repeating: .zero, count: numPendulums)
        }
        
        try testShouldReset()
        
        var altAnglesAndMomenta = [simd_double2](repeating: .zero, count: numPendulums)
        
        for i in 0..<6 {
            let weight_i    = Self.weights[i]
            let altWeight_i = Self.altWeights[i]
            
            let angularVelocitiesAndForces_i = angularVelocitiesAndForces[i]
            
            for j in 0..<numPendulums {
                let ijVelocityAndForce = angularVelocitiesAndForces_i[j]
                
                anglesAndMomenta[j]    = fma(ijVelocityAndForce, weight_i, anglesAndMomenta[j])
                altAnglesAndMomenta[j] = fma(ijVelocityAndForce, altWeight_i, altAnglesAndMomenta[j])
            }
        }
        
        let altWeight6 = Self.altWeights[6]
        
        for i in 0..<numPendulums {
            let lastAngleAndMomentum = simd_double2(lastState.angles[i],
                                                    lastState.momenta[i])
            
            let angleAndMomentum = anglesAndMomenta[i]
            let altAngleAndMomentum = fma(angleAndMomentum, altWeight6, altAnglesAndMomenta[i])
            
            anglesAndMomenta[i]    = fma(angleAndMomentum,    timeStep, lastAngleAndMomentum)
            altAnglesAndMomenta[i] = fma(altAngleAndMomentum, timeStep, lastAngleAndMomentum)
        }
        
        var altState = PendulumState(frameProgress: frameEnd, angles:  altAnglesAndMomenta.map{ $0.x },
                                                              momenta: altAnglesAndMomenta.map{ $0.y })
        stateEquations.process(numPendulums, gravitationalAccelerationHalf, state: &altState)
        
        var nextState = PendulumState(frameProgress: frameEnd, angles:  anglesAndMomenta.map{ $0.x },
                                                               momenta: anglesAndMomenta.map{ $0.y })
        cachedForces = stateEquations.process(numPendulums, gravitationalAccelerationHalf,
                                              state: &nextState, returningForces: true)!
        
        return (nextState, (0..<numPendulums).reduce(into: 0) { (error, i) in
            error += length(altState.coords[i] - nextState.coords[i])
        })
    }
    
}
