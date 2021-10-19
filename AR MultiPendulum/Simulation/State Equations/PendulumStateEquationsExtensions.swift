//
//  PendulumStateEquationsExtensions.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/2/21.
//

import ARHeadsetKit

extension PendulumStateEquations {
    
    @discardableResult
    func process(_ numPendulums: Int, _ gravitationalAccelerationHalf: Double,
                 state: inout PendulumState, returningForces: Bool = false) -> [Double]?
    {
        var forces: [Double]?
        
        if state.momenta == nil {
            assert(!returningForces)
            
            let numPendulumsIsOdd = numPendulums & 1
            let numVectorizedPendulums = numPendulums - numPendulumsIsOdd
            
            let angles = state.angles
            
            state.momenta = (0..<numPendulums).map { i -> Double in
                let angle_i = angles[i]
                let massSumsTimesLengthProducts_i = massSumsTimesLengthProducts[i]
                
                var momentumVector = simd_double2()
                var j = 0
                
                while j < numVectorizedPendulums {
                    let cosine_vector = cos(simd_double2(angle_i - angles[j],
                                                         angle_i - angles[j + 1]))
                    let j_plus_1 = j + 1
                    
                    var multipliers = simd_double2(massSumsTimesLengthProducts_i[j],
                                                   massSumsTimesLengthProducts_i[j_plus_1])
                    
                    multipliers *= simd_double2(state.angularVelocities[j],
                                                state.angularVelocities[j_plus_1])
                    
                    momentumVector = fma(cosine_vector, multipliers, momentumVector)
                    
                    j += 2
                }
                
                if numPendulumsIsOdd != 0 {
                    let cosine_value = cos(angle_i - angles[j])
                    let multiplier = state.angularVelocities[j] * massSumsTimesLengthProducts_i[j]
                    
                    momentumVector[0] = fma(cosine_value, multiplier, momentumVector[0])
                }
                
                return momentumVector.sum()
            }
        } else if state.angularVelocities == nil {
            if returningForces {
                (state.angularVelocities, forces) = solveAngularVelocitiesAndForces(numPendulums, state.angles, state.momenta)
            } else {
                state.angularVelocities = solveAngularVelocities(numPendulums, state.angles, state.momenta)
            }
        } else if returningForces {
            (state.angularVelocities, forces) = solveAngularVelocitiesAndForces(numPendulums, state.angles, state.momenta)
        }
        
        solveEnergy(numPendulums, gravitationalAccelerationHalf, state: &state)
        
        return forces
    }
    
    static func solveCoords(_ numPendulums: Int, lengths: [Double], state: inout PendulumState) {
        var coords = [simd_double2](capacity: numPendulums)
        
        for i in 0..<numPendulums {
            let sincosValues = __sincos_stret(state.angles[i])
            let sincosVector = simd_double2(sincosValues.__sinval, -sincosValues.__cosval)
            let retrievedLength = lengths[i]
            
            let lastCoords = i == 0 ? .zero : coords[i - 1]
            let nextCoords = fma(sincosVector, retrievedLength, lastCoords)
            coords.append(nextCoords)
        }
        
        state.coords = coords
    }
    
    func solveEnergy(_ numPendulums: Int, _ gravitationalAccelerationHalf: Double, state: inout PendulumState) {
        var potential_kinetic = simd_double2()
        var coords = [simd_double2](capacity: numPendulums)
        
        for i in 0..<numPendulums {
            let sincosValues = __sincos_stret(state.angles[i])
            let sincosVector = simd_double2(sincosValues.__sinval, -sincosValues.__cosval)
            let retrievedLength = lengths[i]
            
            let lastCoords = i == 0 ? .zero : coords[i - 1]
            let nextCoords = fma(sincosVector, retrievedLength, lastCoords)
            coords.append(nextCoords)
            
            // Update potential and kinetic energy
            
            let massAndMomentum = simd_double2(masses[i], state.momenta[i])
            let heightAndAngularVelocity = simd_double2(nextCoords.y, state.angularVelocities[i])
            
            potential_kinetic = fma(massAndMomentum, heightAndAngularVelocity, potential_kinetic)
        }
        
        potential_kinetic[0] = fma(potential_kinetic[0], gravitationalAccelerationHalf, constantPotential)
        potential_kinetic[1] *= 0.5
        
        state.energy = potential_kinetic.sum()
        state.coords = coords
    }
    
    func solveAngularVelocities(_ numPendulums: Int, _ angles: [Double], _ momenta: [Double]) -> [Double] {
        solveOnlyMatrix(numPendulums, angles, momenta)
        
        var outputAngularVelocities = [Double](capacity: numPendulums)
        
        let numPendulumsIsOdd = numPendulums & 1
        let numVectorizedPendulums = numPendulums - numPendulumsIsOdd
        
        let rowSize = numPendulums + 1
        let rowSizeDouble = rowSize << 1
        var i = 0
        
        var matrixPointer = outputLayer
        
        while i < numVectorizedPendulums {
            let nValuePointer = matrixPointer + numPendulums
            let iValuePointer = matrixPointer + i
            
            let nValues = simd_double2(nValuePointer.pointee, nValuePointer[rowSize])
            let iValues = simd_double2(iValuePointer.pointee, iValuePointer[rowSize + 1])
            
            let angularVelocities = nValues * simd_precise_recip(iValues)
            
            outputAngularVelocities.append(angularVelocities[0])
            outputAngularVelocities.append(angularVelocities[1])
            
            matrixPointer += rowSizeDouble
            i += 2
        }
        
        if numPendulumsIsOdd != 0 {
            let nValue = matrixPointer[numPendulums]
            let iValue = matrixPointer[i]
            
            outputAngularVelocities.append(nValue * simd_precise_recip(iValue))
        }
        
        return outputAngularVelocities
    }
    
    typealias AngularVelocitiesAndForces = (angularVelocities: [Double], forces: [Double])
    
    func solveAngularVelocitiesAndForces(_ numPendulums: Int, _ angles: [Double], _ momenta: [Double]) -> AngularVelocitiesAndForces {
        solveMatrixWithDerivative(numPendulums, angles, momenta)
        
        let rowSize = numPendulums + 1
        let layerSize = numPendulums * rowSize
        
        let numPendulumsIsOdd = numPendulums & 1
        let numVectorizedPendulums = numPendulums - numPendulumsIsOdd
        
        var outputForces            = [Double](repeating: 0, count: numPendulums)
        var outputAngularVelocities = [Double](capacity: numPendulums)
        
        for i in 0..<numPendulums {
            let matrixPointer = outputLayer + i * rowSize
            
            let nValue = matrixPointer[numPendulums]
            let iValue = matrixPointer[i]
            
            let iValueReciprocal = simd_precise_recip(iValue)
            let angularVelocity = nValue * iValueReciprocal
            let nOver_iValueSquared = angularVelocity * iValueReciprocal
            
            outputAngularVelocities.append(angularVelocity)
            
            let momentum_i = momenta[i]
            
            var matrixDerivativePointer1 = outputDerivativeLayer + i * rowSize
            var matrixDerivativePointer2 = matrixDerivativePointer1 + layerSize
            let layerSizeDouble = layerSize << 1
            
            var h = 0
            
            while h < numVectorizedPendulums {
                let iDerivatives = simd_double2(matrixDerivativePointer1[i],
                                                matrixDerivativePointer2[i])
                
                var forceContribution = iDerivatives * nOver_iValueSquared
                
                let nDerivatives = simd_double2(matrixDerivativePointer1[numPendulums],
                                                matrixDerivativePointer2[numPendulums])
                
                forceContribution = fma(nDerivatives, iValueReciprocal, -forceContribution)
                
                let h_plus_1 = h + 1
                
                var forces = simd_double2(outputForces[h],
                                          outputForces[h_plus_1])
                
                forces = fma(forceContribution, momentum_i, forces)
                
                outputForces[h]        = forces[0]
                outputForces[h_plus_1] = forces[1]
                
                matrixDerivativePointer1 += layerSizeDouble
                matrixDerivativePointer2 += layerSizeDouble
                
                h += 2
            }
            
            if numPendulumsIsOdd != 0 {
                let iDerivative = matrixDerivativePointer1[i]
                var forceContribution = iDerivative * nOver_iValueSquared
                
                let nDerivative = matrixDerivativePointer1[numPendulums]
                forceContribution = fma(nDerivative, iValueReciprocal, -forceContribution)
                
                outputForces[h] = fma(forceContribution, momentum_i, outputForces[h])
            }
        }
        
        var h = 0
        
        while h < numVectorizedPendulums {
            let sines_h_vector = sin(simd_double2(angles[h], angles[h + 1]))
            let h_plus_1 = h + 1
            
            let multipliers = simd_double2(massSumsTimesLengthsTimesGravity[h],
                                           massSumsTimesLengthsTimesGravity[h_plus_1])
            
            var forces = simd_double2(outputForces[h], outputForces[h_plus_1])
            
            forces *= -0.5
            forces = fma(sines_h_vector, multipliers, forces)
            
            outputForces[h]        = forces[0]
            outputForces[h_plus_1] = forces[1]
            
            h += 2
        }
        
        if numPendulumsIsOdd != 0 {
            let sine_h = sin(angles[h])
            let multiplier = massSumsTimesLengthsTimesGravity[h]
            
            outputForces[h] = fma(sine_h, multiplier, -0.5 * outputForces[h])
        }
        
        return (outputAngularVelocities, outputForces)
    }
    
}
