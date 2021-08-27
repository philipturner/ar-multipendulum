//
//  PendulumMatrixSolving.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/2/21.
//

import Foundation
import simd

extension PendulumStateEquations {
    
    // The `matrix` is a system of linear of equations representing angular velocities
    // The derivative of each value in that matrix is used to calculate forces
    
    // Solving the `matrix` has O(n^3) algorithmic complexity with respect to the number of pendulums
    // Solving the `matrix derivative` has O(n^4) algorithmic complexity
    
    func solveOnlyMatrix(_ numPendulums: Int, _ angles: [Double], _ momenta: [Double]) {
        let rowSize = numPendulums + 1
        let layerSize = numPendulums * rowSize
        
        memset(outputLayer, 0, layerSize * MemoryLayout<Double>.stride)
        
        let numPendulumsIsOdd = numPendulums & 1
        let numVectorizedPendulums = numPendulums - numPendulumsIsOdd
        
        for i in 0..<numPendulums {
            var matrixFillStart: Int { i + 1 }
            var j = ~1 & matrixFillStart
            
            var j_row = outputLayer + j * rowSize
            let i_row = outputLayer + i * rowSize
            
            let massSumsTimesLengthProducts_i = massSumsTimesLengthProducts[i]
            i_row[i] = massSumsTimesLengthProducts_i[i]
            
            let angle_i = angles[i]
            
            while j < numVectorizedPendulums {
                let ijLocation = i_row + j
                let jiLocation = j_row + i
                
                let j_plus_1 = j + 1
                
                let ijMultipliers = simd_double2(massSumsTimesLengthProducts_i[j],
                                                 massSumsTimesLengthProducts_i[j_plus_1])
                
                let ijValues = ijMultipliers * cos(simd_double2(angle_i - angles[j],
                                                                angle_i - angles[j_plus_1]))
                
                if j > i {
                    ijLocation.pointee = ijValues[0]
                    jiLocation.pointee = ijValues[0]
                }
                
                ijLocation[1]       = ijValues[1]
                jiLocation[rowSize] = ijValues[1]
                
                j += 2
                j_row += rowSize << 1
            }
            
            if numPendulumsIsOdd != 0, j >= matrixFillStart {
                let ijLocation = i_row + j
                let jiLocation = j_row + i
                
                let ijMultiplier = massSumsTimesLengthProducts_i[j]
                let ijValue = ijMultiplier * cos(angle_i - angles[j])
                
                ijLocation.pointee = ijValue
                jiLocation.pointee = ijValue
            }
            
            i_row[numPendulums] = momenta[i]
        }
        
        let rowSizeIsOdd = rowSize & 1
        let roundedRowSize = rowSize - rowSizeIsOdd
        
        var inputLayer = self.inputLayer
        var outputLayer = self.outputLayer
        
        defer {
            self.inputLayer = inputLayer
            self.outputLayer = outputLayer
        }
        
        for i in 0..<numPendulums {
            let layerRef = inputLayer
            inputLayer = outputLayer
            outputLayer = layerRef
            
            let iiiValue = inputLayer[i * (rowSize + 1)]
            
            for j in 0..<numPendulums {
                let ij_Offset = j * rowSize
                let ijiOffset = ij_Offset + i
                let ijiValue  = inputLayer[ijiOffset]
                
                let ijkOffset_end = ij_Offset + roundedRowSize
                
                if i == j || abs(ijiValue) < .leastNormalMagnitude {
                    var ijkOffset = ij_Offset
                    
                    while ijkOffset < ijkOffset_end {
                        let ijkOffset_plus_1 = ijkOffset + 1
                        
                        outputLayer[ijkOffset]        = inputLayer[ijkOffset]
                        outputLayer[ijkOffset_plus_1] = inputLayer[ijkOffset_plus_1]
                        
                        ijkOffset += 2
                    }
                    
                    if rowSizeIsOdd != 0 {
                        outputLayer[ijkOffset] = inputLayer[ijkOffset]
                    }
                } else {
                    let ijiReciprocal = simd_precise_recip(ijiValue)
                    let cachedTerm1 = iiiValue * ijiReciprocal
                    
                    let j_less_than_i = j < i
                    let ijjOffset = ij_Offset + j
                    let ijDifferenceOffset = (i - j) * rowSize
                    
                    var ijkOffset = ij_Offset
                    
                    while ijkOffset < ijkOffset_end {
                        let ijkOffset_plus_1 = ijkOffset + 1
                        
                        var mask0 = ijiOffset < ijkOffset
                        var mask1 = ijiOffset < ijkOffset_plus_1
                        
                        if j_less_than_i {
                            mask0 = mask0 || ijjOffset == ijkOffset
                            mask1 = mask1 || ijjOffset == ijkOffset_plus_1
                        }
                        
                        if mask0 {
                            if mask1 {
                                let ijkValues = simd_double2(inputLayer[ijkOffset],
                                                             inputLayer[ijkOffset_plus_1])
                                
                                let iikValues = simd_double2(inputLayer[ijkOffset + ijDifferenceOffset],
                                                             inputLayer[ijkOffset_plus_1 + ijDifferenceOffset])
                                
                                let output = (ijkValues * cachedTerm1) - iikValues
                                
                                outputLayer[ijkOffset] = output.x
                                outputLayer[ijkOffset_plus_1] = output.y
                            } else {
                                let ijkValue = inputLayer[ijkOffset]
                                let iikValue = inputLayer[ijkOffset + ijDifferenceOffset]
                                
                                outputLayer[ijkOffset] = (ijkValue * cachedTerm1) - iikValue
                                outputLayer[ijkOffset_plus_1] = 0
                            }
                        } else if mask1 {
                            let ijkValue = inputLayer[ijkOffset_plus_1]
                            let iikValue = inputLayer[ijkOffset_plus_1 + ijDifferenceOffset]
                            
                            outputLayer[ijkOffset] = 0
                            outputLayer[ijkOffset_plus_1] = (ijkValue * cachedTerm1) - iikValue
                        } else {
                            outputLayer[ijkOffset] = 0
                            outputLayer[ijkOffset_plus_1] = 0
                        }
                        
                        ijkOffset += 2
                    }
                    
                    if rowSizeIsOdd != 0 {
                        if ijkOffset > ijiOffset || (j_less_than_i && ijjOffset == ijkOffset) {
                            let ijkValue = inputLayer[ijkOffset]

                            let iikOffset = ijkOffset + ijDifferenceOffset
                            let iikValue = inputLayer[iikOffset]
                            outputLayer[ijkOffset] = (ijkValue * cachedTerm1) - iikValue
                        }
                    }
                }
            }
        }
    }
    
    func solveMatrixWithDerivative(_ numPendulums: Int, _ angles: [Double], _ momenta: [Double]) {
        let rowSize = numPendulums + 1
        let layerSize = numPendulums * rowSize
        
        memset(outputLayer, 0, layerSize * MemoryLayout<Double>.stride)
        memset(outputDerivativeLayer, 0, numPendulums * layerSize * MemoryLayout<Double>.stride)
        
        let numPendulumsIsOdd = numPendulums & 1
        let numVectorizedPendulums = numPendulums - numPendulumsIsOdd
        
        for i in 0..<numPendulums {
            var j = 0
            var matrixFillStart: Int { i + 1 }
            let matrixFillRoundedStart = ~1 & matrixFillStart
            
            var ijOffset = i * rowSize
            var jiOffset = i
            
            var j_row = outputLayer
            let i_row = j_row + ijOffset
            
            var layer1 = outputDerivativeLayer
            var layer2 = layer1 + layerSize
            
            let massSumsTimesLengthProducts_i = massSumsTimesLengthProducts[i]
            i_row[i] = massSumsTimesLengthProducts_i[i]
            
            let angle_i = angles[i]
            
            while j < numVectorizedPendulums {
                let angleDifference = simd_double2(angle_i - angles[j],
                                                   angle_i - angles[j + 1])
                let sinval = sin(angleDifference)
                
                let ijMultipliers = simd_double2(massSumsTimesLengthProducts_i[j],
                                                 massSumsTimesLengthProducts_i[j + 1])
                
                if j >= matrixFillRoundedStart {
                    let ijLocation = i_row + j
                    let jiLocation = j_row + i
                    
                    let ijValues = ijMultipliers * getCos(sinval: sinval, angle: angleDifference)
                    
                    if j > i {
                        ijLocation.pointee = ijValues[0]
                        jiLocation.pointee = ijValues[0]
                    }
                    
                    ijLocation[1]       = ijValues[1]
                    jiLocation[rowSize] = ijValues[1]
                }
                
                do {
                    let ijValues = ijMultipliers * sinval
                    
                    if j != i {
                        layer1[ijOffset] = ijValues[0]
                        layer1[jiOffset] = ijValues[0]
                    }
                    
                    if j + 1 != i {
                        layer2[ijOffset + 1]       = ijValues[1]
                        layer2[jiOffset + rowSize] = ijValues[1]
                    }
                }
                
                let rowSizeDouble = rowSize << 1
                let layerSizeDouble = layerSize << 1
                
                j += 2
                j_row += rowSizeDouble
                
                layer1 += layerSizeDouble
                layer2 += layerSizeDouble
                
                ijOffset += 2
                jiOffset += rowSizeDouble
            }
            
            if numPendulumsIsOdd != 0 {
                let angleDifference = angle_i - angles[j]
                let sinval = sin(angleDifference)
                
                let ijMultiplier = massSumsTimesLengthProducts_i[j]
                
                if j >= matrixFillStart {
                    let ijLocation = i_row + j
                    let jiLocation = j_row + i
                    
                    let ijValue = ijMultiplier * getCos(sinval: sinval, angle: angleDifference)
                    
                    ijLocation.pointee = ijValue
                    jiLocation.pointee = ijValue
                }
                
                if j != i {
                    let ijValue = ijMultiplier * sinval
                    
                    layer1[ijOffset] = ijValue
                    layer1[jiOffset] = ijValue
                }
            }
            
            i_row[numPendulums] = momenta[i]
        }
        
        // locating values by their offsets into pointers is substantially
        // faster than locating them by indexing into nested arrays
        
        // values in the matrix are addressed by a 3D coordinate
        // values in the matrix derivative are addressed by a 4D coordinate
        
        // 3 characters before `Offset` means a variable represents a 3D coordinate
        // 4 characters before `Offset` means a variable represents a 4D coordinate
        
        // an underscore means that a coordinate is set to zero
        // for example, `_abOffset` means the first coordinate is zero,
        // the second coordinate is the value of `a`,
        // and the third coordinate is the value of `b`
        
        var inputLayer = self.inputLayer
        var outputLayer = self.outputLayer
        
        var inputDerivativeLayer = self.inputDerivativeLayer
        var outputDerivativeLayer = self.outputDerivativeLayer
        let transientPartialDerivatives = self.transientPartialDerivatives
        
        defer {
            self.inputLayer = inputLayer
            self.outputLayer = outputLayer
            
            self.inputDerivativeLayer = inputDerivativeLayer
            self.outputDerivativeLayer = outputDerivativeLayer
        }
        
        for i in 0..<numPendulums {
            var layerRef = inputLayer
            inputLayer = outputLayer
            outputLayer = layerRef
            
            layerRef = inputDerivativeLayer
            inputDerivativeLayer = outputDerivativeLayer
            outputDerivativeLayer = layerRef
            
            let iiiOffset = i * (rowSize + 1)
            
            do {
                var hiiiDerivativePointer = inputDerivativeLayer + iiiOffset
                let layerSizeDouble = layerSize << 1
                
                var h = 0
                
                while h < numVectorizedPendulums {
                    transientPartialDerivatives[h]     = hiiiDerivativePointer.pointee
                    transientPartialDerivatives[h + 1] = hiiiDerivativePointer[layerSize]
                    
                    hiiiDerivativePointer += layerSizeDouble
                    h += 2
                }
                
                if numPendulumsIsOdd != 0 {
                    transientPartialDerivatives[h] = hiiiDerivativePointer.pointee
                }
            }
            
            let iiiValue = inputLayer[iiiOffset]
            
            for j in 0..<numPendulums {
                let ij_Offset = j * rowSize
                let ijiOffset = ij_Offset + i
                let ijiValue  = inputLayer[ijiOffset]
                
                let ijkOffset_end = ij_Offset + numPendulums
                
                if i == j || abs(ijiValue) < .leastNormalMagnitude {
                    for ijkOffset in ij_Offset...ijkOffset_end {
                        outputLayer[ijkOffset] = inputLayer[ijkOffset]
                        
                        var hijkDerivativePointer_in  = inputDerivativeLayer  + ijkOffset
                        var hijkDerivativePointer_out = outputDerivativeLayer + ijkOffset
                        let layerSizeDouble = layerSize << 1
                        
                        var h = 0
                        
                        while h < numVectorizedPendulums {
                            hijkDerivativePointer_out.pointee    = hijkDerivativePointer_in.pointee
                            hijkDerivativePointer_out[layerSize] = hijkDerivativePointer_in[layerSize]
                            
                            hijkDerivativePointer_in  += layerSizeDouble
                            hijkDerivativePointer_out += layerSizeDouble
                            h += 2
                        }
                        
                        if numPendulumsIsOdd != 0 {
                            hijkDerivativePointer_out.pointee = hijkDerivativePointer_in.pointee
                        }
                    }
                } else {
                    let ijiReciprocal = simd_precise_recip(ijiValue)
                    let cachedTerm1 = iiiValue * ijiReciprocal
                    
                    let j_less_than_i = j < i
                    let ijjOffset = ij_Offset + j
                    
                    let ijDifferenceOffset = (i - j) * rowSize
                    
                    for ijkOffset in ij_Offset...ijkOffset_end {
                        if ijkOffset > ijiOffset || (j_less_than_i && ijjOffset == ijkOffset) {
                            let ijkValue    = inputLayer[ijkOffset]
                            let cachedTerm2 = ijkValue * ijiReciprocal
                            let cachedTerm3 = cachedTerm1 * cachedTerm2
                            
                            let iikOffset = ijkOffset + ijDifferenceOffset
                            outputLayer[ijkOffset] = (ijkValue * cachedTerm1) - inputLayer[iikOffset]
                            
                            var hijkDerivativePointer_in  = inputDerivativeLayer  + ijkOffset
                            var hijkDerivativePointer_out = outputDerivativeLayer + ijkOffset
                            
                            var hijiDerivativePointer = inputDerivativeLayer + ijiOffset
                            var hiikDerivativePointer = inputDerivativeLayer + iikOffset
                            let layerSizeDouble = layerSize << 1
                            
                            var transientPartialDerivatives_h = transientPartialDerivatives
                            var h = 0
                            
                            while h < numVectorizedPendulums {
                                let hiikDerivatives = simd_double2(hiikDerivativePointer.pointee,
                                                                   hiikDerivativePointer[layerSize])
                                
                                let hijiDerivatives = simd_double2(hijiDerivativePointer.pointee,
                                                                   hijiDerivativePointer[layerSize])
                                
                                var output = fma(hijiDerivatives, cachedTerm3, hiikDerivatives)
                                
                                let hiiiDerivatives = simd_double2(transientPartialDerivatives_h.pointee,
                                                                   transientPartialDerivatives_h[1])
                                
                                output = fma(hiiiDerivatives, cachedTerm2, -output)
                                
                                let hijkDerivatives = simd_double2(hijkDerivativePointer_in.pointee,
                                                                   hijkDerivativePointer_in[layerSize])
                                
                                output = fma(hijkDerivatives, cachedTerm1, output)
                                
                                hijkDerivativePointer_out.pointee    = output.x
                                hijkDerivativePointer_out[layerSize] = output.y
                                
                                hijkDerivativePointer_in  += layerSizeDouble
                                hijkDerivativePointer_out += layerSizeDouble
                                
                                hijiDerivativePointer += layerSizeDouble
                                hiikDerivativePointer += layerSizeDouble
                                
                                transientPartialDerivatives_h += 2
                                h += 2
                            }
                            
                            if numPendulumsIsOdd != 0 {
                                let hiikDerivative = hiikDerivativePointer.pointee
                                let hijiDerivative = hijiDerivativePointer.pointee
                                
                                var output = fma(hijiDerivative, cachedTerm3, hiikDerivative)
                                
                                let hiiiDerivative = transientPartialDerivatives_h.pointee
                                output = fma(hiiiDerivative, cachedTerm2, -output)
                                
                                let hijkDerivative = hijkDerivativePointer_in.pointee
                                output = fma(hijkDerivative, cachedTerm1, output)
                                
                                hijkDerivativePointer_out.pointee = output
                            }
                        } else {
                            outputLayer[ijkOffset] = 0
                            
                            var hijkDerivativePointer_out = outputDerivativeLayer + ijkOffset
                            let layerSizeDouble = layerSize << 1
                            
                            var h = 0
                            
                            while h < numVectorizedPendulums {
                                hijkDerivativePointer_out.pointee    = 0
                                hijkDerivativePointer_out[layerSize] = 0
                                
                                hijkDerivativePointer_out += layerSizeDouble
                                h += 2
                            }
                            
                            if numPendulumsIsOdd != 0 {
                                hijkDerivativePointer_out.pointee = 0
                            }
                        }
                    }
                }
            }
        }
    }
    
}
