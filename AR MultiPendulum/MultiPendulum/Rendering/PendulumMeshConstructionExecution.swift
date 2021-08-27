//
//  PendulumMeshConstructionExecution.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/7/21.
//

import Metal
import simd

extension PendulumMeshConstructor {
    
    func createMesh(_ states: [PendulumState]) {
        ensureBufferCapacity(type: .geometry, capacity: numPendulums * states.count)
        
        var rectanglePointer   = (geometryBuffer[.rectangle]   + rectangleOffset).assumingMemoryBound(to: simd_float2x2.self)
        var jointOriginPointer = (geometryBuffer[.jointOrigin] + jointOriginOffset).assumingMemoryBound(to: simd_float2.self)
        let numKeyFrames = states.count
        
        for state in states {
            var cachedCoords: simd_float2 = .zero
            var selectedRectanglePointer = rectanglePointer
            var selectedJointOriginPointer = jointOriginPointer
            
            for i in 0..<numPendulums {
                let nextCoords = simd_float2(state.coords[i])
                selectedRectanglePointer.pointee = .init(cachedCoords, nextCoords)
                selectedJointOriginPointer.pointee = nextCoords
                
                cachedCoords = nextCoords
                selectedRectanglePointer += numKeyFrames
                selectedJointOriginPointer += numKeyFrames
            }
            
            rectanglePointer += 1
            jointOriginPointer += 1
        }
        
        
        
        let commandBuffer = renderer.commandQueue.makeDebugCommandBuffer()
        commandBuffer.optLabel = "Pendulum Mesh Construction Command Buffer"
        
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.optLabel = "Pendulum Mesh Construction - Compute Pass"
        
        computeEncoder.pushOptDebugGroup("Create Rectangle Mesh")
        
        computeEncoder.setComputePipelineState(makeRectangleMeshPipelineState)
        computeEncoder.setBuffer(geometryBuffer, level: .rectangle,              offset: rectangleOffset,           index: 0)
        computeEncoder.setBuffer(uniformBuffer,  level: .computeUniform,         offset: computeUniformOffset,      index: 1)
        computeEncoder.setBuffer(uniformBuffer,  level: .vertexUniform,          offset: vertexUniformOffset,       index: 2)
        
        computeEncoder.setBuffer(geometryBuffer, level: .rectangleVertex,                                           index: 3)
        computeEncoder.setBuffer(geometryBuffer, level: .rectangleTriangleIndex,                                    index: 4)
        computeEncoder.setBuffer(geometryBuffer, level: .rectangleLineIndex,                                        index: 5)
        
        computeEncoder.setBuffer(uniformBuffer,  level: .rectangleVertexCount,   offset: vertexCountOffset,         index: 6)
        computeEncoder.setBuffer(uniformBuffer,  level: .rectangleTriangleCount, offset: numInstancesOffset,        index: 7)
        computeEncoder.setBuffer(uniformBuffer,  level: .rectangleLineCount,     offset: indexedNumInstancesOffset, index: 8)
        
        computeEncoder.setBuffer(geometryBuffer, level: .rectangleDepthRange,                                       index: 10)
        
        computeEncoder.dispatchThreadgroups([ numPendulums, numKeyFrames ], threadsPerThreadgroup: usingThreadgroups ? 8 : 1)
        
        computeEncoder.popOptDebugGroup()
        
        
        
        computeEncoder.pushOptDebugGroup("Create Joint Mesh")
        
        let meshArguments = UniformLevel.createJointMeshArguments
        var meshArgumentOffset: Int { createJointMeshArgumentsOffset }
        var transformOffset: Int { worldToCameraTransformOffset }
        
        computeEncoder.setComputePipelineState(makeJointMeshPipelineState)
        computeEncoder.setBuffer(geometryBuffer, level: .jointOrigin,            offset: jointOriginOffset,    index: 0, asOffset: true)
        
        computeEncoder.setBuffer(geometryBuffer, level: .jointAngleRange,                                      index: 3, asOffset: true)
        computeEncoder.setBuffer(geometryBuffer, level: .jointBaseVertex,                                      index: 4, asOffset: true)
        computeEncoder.setBuffer(geometryBuffer, level: .jointVertex,                                          index: 5, asOffset: true)
        
        computeEncoder.setBuffer(uniformBuffer,  level: .worldToCameraTransform, offset: transformOffset,      index: 6, asOffset: true)
        computeEncoder.setBuffer(uniformBuffer,  level: .cameraPosition,         offset: cameraPositionOffset, index: 7, asOffset: true)
        computeEncoder.setBuffer(uniformBuffer,  level:  meshArguments,          offset: meshArgumentOffset,   index: 8, asOffset: true)
        computeEncoder.setBuffer(uniformBuffer,  level: .jointVertexCount,       offset: vertexCountOffset,    index: 9)
        
        computeEncoder.setBuffer(geometryBuffer, level: .jointEdgeVertex,                                      index: 10, asOffset: true)
        computeEncoder.setBuffer(geometryBuffer, level: .jointEdgeNormal,                                      index: 11)
        computeEncoder.dispatchThreadgroups([ numPendulums, numKeyFrames ], threadsPerThreadgroup: usingThreadgroups ? 8 : 1)
        
        computeEncoder.setComputePipelineState(createJointMeshVerticesPipelineState)
        computeEncoder.setBuffer(uniformBuffer, level: .jointTriangleCount, offset: indexedNumInstancesOffset, index: 9, asOffset: true)
        computeEncoder.dispatchThreadgroups(indirectBuffer:       uniformBuffer,
                                            indirectBufferLevel: .createJointMeshArguments,
                                            indirectBufferOffset: createJointMeshArgumentsOffset,
                                            threadsPerThreadgroup: 1)
        
        computeEncoder.popOptDebugGroup()
        
        computeEncoder.endEncoding()
        commandBuffer.commit()
    }
    
}
