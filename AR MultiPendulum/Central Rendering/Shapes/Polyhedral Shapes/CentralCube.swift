//
//  CentralCube.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 4/17/21.
//

import Metal
import simd

struct CentralCube: CentralPolyhedralShape {
    static var shapeType: CentralShapeType = .cube
    
    var numIndices: Int
    var normalOffset: Int
    var indexOffset: Int
    
    init(centralRenderer: CentralRenderer, numSegments _: UInt16,
         vertices: inout [CentralVertex], indices: inout [UInt16])
    {
        let normalVectors: [simd_float3] = [
            [-0.5, 0,   0  ],
            [ 0,  -0.5, 0  ],
            [ 0,   0,  -0.5],
            [ 0.5, 0,   0  ],
            [ 0,   0.5, 0  ],
            [ 0,   0,   0.5]
        ]
        
        let horizontalVectors: [simd_float3] = [
            [ 0,   0,  0.5],
            [ 0.5, 0,  0  ],
            [-0.5, 0,  0  ],
            [ 0,   0, -0.5],
            [ 0.5, 0,  0  ],
            [ 0.5, 0,  0  ],
        ]
        
        let verticalVectors: [simd_float3] = [
            [ 0,  0.5, 0  ],
            [ 0,  0,   0.5],
            [ 0,  0.5, 0  ],
            [ 0,  0.5, 0  ],
            [ 0,  0,  -0.5],
            [ 0,  0.5, 0  ],
        ]
        
        let currentVertices = (0..<6).flatMap { sideID -> [CentralVertex] in
            let normalVector     = normalVectors    [sideID]
            let horizontalVector = horizontalVectors[sideID]
            let verticalVector   = verticalVectors  [sideID]
            
            let positions: [simd_float3] = [
                normalVector - horizontalVector - verticalVector,
                normalVector + horizontalVector - verticalVector,
                normalVector - horizontalVector + verticalVector,
                normalVector + horizontalVector + verticalVector
            ]
            
            let normal = normalVector + normalVector
            
            return positions.map {
                CentralVertex(position: $0, normal: normal)
            }
        }
        
        let currentIndices = (UInt16(0)..<6).flatMap { sideID -> [UInt16] in
            let baseIndex = sideID << 2
            
            return Self.makeQuadIndices([0, 1, 2, 3].map{ $0 + baseIndex})
        }
        
        numIndices   = currentIndices.count
        normalOffset = vertices.count * MemoryLayout<simd_half3>.stride
        indexOffset  = indices.count  * MemoryLayout<UInt16>.stride
        
        vertices += currentVertices
        indices  += currentIndices
    }
}

extension RayTracing.Ray {
    
    func getCentralCubeProgress() -> Float? {
        var baseProgresses = getBoundingCoordinatePlaneProgresses()
        
        @inline(__always)
        func testBaseProgress(axis: Int, altAxis1: Int, altAxis2: Int) {
            guard !baseProgresses[axis].isNaN else { return }
            
            let projection3D = project(progress: baseProgresses[axis])
            let projection2D = simd_float2(projection3D[altAxis1], projection3D[altAxis2])
            
            if any(abs(projection2D) .> 0.5) {
                baseProgresses[axis] = .nan
            }
        }
        
        testBaseProgress(axis: 0, altAxis1: 1, altAxis2: 2)
        testBaseProgress(axis: 1, altAxis1: 0, altAxis2: 2)
        testBaseProgress(axis: 2, altAxis1: 0, altAxis2: 1)
        
        let possibleBaseProgress = baseProgresses.min()
        return possibleBaseProgress.isNaN ? nil : possibleBaseProgress
    }
    
    mutating func transformIntoBoundingBox(_ boundingBox: simd_float2x3) {
        let translation = (boundingBox[0] + boundingBox[1]) * 0.5
        origin -= translation
        
        let inverseScale = simd_fast_recip(boundingBox[1] - boundingBox[0])
        origin *= inverseScale
        direction *= inverseScale
    }
    
    func transformedIntoBoundingBox(_ boundingBox: simd_float2x3) -> RayTracing.Ray {
        var copy = self
        copy.transformIntoBoundingBox(boundingBox)
        return copy
    }
    
}
