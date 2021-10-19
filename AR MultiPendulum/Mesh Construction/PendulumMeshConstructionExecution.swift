//
//  PendulumMeshConstructionExecution.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/7/21.
//

import Metal
import ARHeadsetKit

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
        computeEncoder.setBuffer(geometryBuffer, layer: .rectangle,              offset: rectangleOffset,           index: 0)
        computeEncoder.setBuffer(uniformBuffer,  layer: .computeUniform,         offset: computeUniformOffset,      index: 1)
        computeEncoder.setBuffer(uniformBuffer,  layer: .vertexUniform,          offset: vertexUniformOffset,       index: 2)
        
        computeEncoder.setBuffer(geometryBuffer, layer: .rectangleVertex,                                           index: 3)
        computeEncoder.setBuffer(geometryBuffer, layer: .rectangleTriangleIndex,                                    index: 4)
        computeEncoder.setBuffer(geometryBuffer, layer: .rectangleLineIndex,                                        index: 5)
        
        computeEncoder.setBuffer(uniformBuffer,  layer: .rectangleVertexCount,   offset: vertexCountOffset,         index: 6)
        computeEncoder.setBuffer(uniformBuffer,  layer: .rectangleTriangleCount, offset: numInstancesOffset,        index: 7)
        computeEncoder.setBuffer(uniformBuffer,  layer: .rectangleLineCount,     offset: indexedNumInstancesOffset, index: 8)
        
        computeEncoder.setBuffer(geometryBuffer, layer: .rectangleDepthRange,                                       index: 10)
        
        computeEncoder.dispatchThreadgroups([ numPendulums, numKeyFrames ], threadsPerThreadgroup: usingThreadgroups ? 8 : 1)
        computeEncoder.popOptDebugGroup()
        
        
        
        computeEncoder.pushOptDebugGroup("Create Joint Mesh")
        
        let meshArguments = UniformLayer.createJointMeshArguments
        var meshArgumentOffset: Int { createJointMeshArgumentsOffset }
        var transformOffset: Int { worldToCameraTransformOffset }
        
        computeEncoder.setComputePipelineState(makeJointMeshPipelineState)
        computeEncoder.setBuffer(geometryBuffer, layer: .jointOrigin,            offset: jointOriginOffset,    index: 0, bound: true)
        
        computeEncoder.setBuffer(geometryBuffer, layer: .jointAngleRange,                                      index: 3, bound: true)
        computeEncoder.setBuffer(geometryBuffer, layer: .jointBaseVertex,                                      index: 4, bound: true)
        computeEncoder.setBuffer(geometryBuffer, layer: .jointVertex,                                          index: 5, bound: true)
        
        computeEncoder.setBuffer(uniformBuffer,  layer: .worldToCameraTransform, offset: transformOffset,      index: 6, bound: true)
        computeEncoder.setBuffer(uniformBuffer,  layer: .cameraPosition,         offset: cameraPositionOffset, index: 7, bound: true)
        computeEncoder.setBuffer(uniformBuffer,  layer:  meshArguments,          offset: meshArgumentOffset,   index: 8, bound: true)
        computeEncoder.setBuffer(uniformBuffer,  layer: .jointVertexCount,       offset: vertexCountOffset,    index: 9)
        
        computeEncoder.setBuffer(geometryBuffer, layer: .jointEdgeVertex,                                      index: 10, bound: true)
        computeEncoder.setBuffer(geometryBuffer, layer: .jointEdgeNormal,                                      index: 11)
        computeEncoder.dispatchThreadgroups([ numPendulums, numKeyFrames ], threadsPerThreadgroup: usingThreadgroups ? 8 : 1)
        computeEncoder.popOptDebugGroup()
        
        
        
        computeEncoder.pushOptDebugGroup("Create Joint Mesh Vertices")
        computeEncoder.setComputePipelineState(createJointMeshVerticesPipelineState)
        
        computeEncoder.setBuffer(uniformBuffer, layer: .jointTriangleCount, offset: indexedNumInstancesOffset, index: 9, bound: true)
        computeEncoder.dispatchThreadgroups(indirectBuffer:       uniformBuffer,
                                            indirectBufferLayer: .createJointMeshArguments,
                                            indirectLayerOffset:  createJointMeshArgumentsOffset,
                                            threadsPerThreadgroup: 1)
        computeEncoder.popOptDebugGroup()
        
        computeEncoder.endEncoding()
        commandBuffer.commit()
    }
    
}
