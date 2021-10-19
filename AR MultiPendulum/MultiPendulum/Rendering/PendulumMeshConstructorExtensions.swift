//
//  PendulumMeshConstructorExtensions.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/7/21.
//

import Metal
import simd

extension PendulumMeshConstructor: GeometryRenderer {
    
    func updateResources() {
        assert(pendulumRenderer.shouldRenderToDisplay)
        
        guard statesToRender != nil else {
            return
        }
        
        let computeUniformPointer = uniformBuffer[.computeUniform].assumingMemoryBound(to: ComputeUniforms.self)
        computeUniformPointer[renderIndex] = .init(pendulumRenderer: pendulumRenderer)
        
        let worldToCameraTransformPointer = uniformBuffer[.worldToCameraTransform].assumingMemoryBound(to: simd_float4x4.self)
        let selectedWorldToCameraTransforms = worldToCameraTransformPointer + renderIndex << 1
        selectedWorldToCameraTransforms[0] = centralRenderer.lodTransform
        
        let cameraPositionPointer = uniformBuffer[.cameraPosition].assumingMemoryBound(to: simd_float3.self)
        let selectedCameraPositionPointer = cameraPositionPointer + renderIndex << 1
        let rawVertexUniformPointer = uniformBuffer[.vertexUniform] + vertexUniformOffset
        
        if doingMixedRealityRendering {
            selectedWorldToCameraTransforms[1] = centralRenderer.lodTransform2
            selectedCameraPositionPointer[0] = pendulumRenderer.leftEyePosition
            selectedCameraPositionPointer[1] = pendulumRenderer.rightEyePosition
            
            let vertexUniformPointer = rawVertexUniformPointer.assumingMemoryBound(to: MixedRealityUniforms.self)
            vertexUniformPointer.pointee = .init(pendulumRenderer: pendulumRenderer)
        } else {
            selectedCameraPositionPointer[0] = pendulumRenderer.handheldEyePosition
            
            let vertexUniformPointer = rawVertexUniformPointer.assumingMemoryBound(to: VertexUniforms.self)
            vertexUniformPointer.pointee = .init(pendulumRenderer: pendulumRenderer)
        }
        
        let jointFragmentUniformPointer = uniformBuffer[.jointFragmentUniform].assumingMemoryBound(to: FragmentUniforms.self)
        jointFragmentUniformPointer[renderIndex] = .init(modelColor: jointColor)
        
        let rectangleFragmentUniformPointer = uniformBuffer[.rectangleFragmentUniform].assumingMemoryBound(to: FragmentUniforms.self)
        rectangleFragmentUniformPointer[renderIndex] = .init(modelColor: rectangleColor)
        
        
        
        @inline(__always)
        func getPointer(_ level: UniformLevel, offset: Int = 0) -> UnsafeMutablePointer<UInt32> {
            (uniformBuffer[level] + offset).assumingMemoryBound(to: UInt32.self)
        }
        
        getPointer(.jointTriangleCount,       offset: indexedNumInstancesOffset).pointee = 0
        getPointer(.rectangleTriangleCount,   offset: numInstancesOffset).pointee = 0
        getPointer(.rectangleLineCount,       offset: indexedNumInstancesOffset).pointee = 0
        getPointer(.createJointMeshArguments, offset: createJointMeshArgumentsOffset).pointee = 0
        
        getPointer(.jointVertexCount    )[renderIndex] = 0
        getPointer(.rectangleVertexCount)[renderIndex] = 0
        
        createMesh(statesToRender)
    }
    
    func drawGeometry(renderEncoder: MTLRenderCommandEncoder, threadID: Int) {
        assert(pendulumRenderer.shouldRenderToDisplay)
        
        guard statesToRender != nil else {
            return
        }
        
        renderEncoder.pushOptDebugGroup("Render Pendulums")
        
        if centralRenderer.currentlyCulling[threadID] == 0 {
            centralRenderer.currentlyCulling[threadID] = 1
            renderEncoder.setCullMode(.back)
        }
        
        if centralRenderer.didSetGlobalFragmentUniforms[threadID] == 0 {
            centralRenderer.didSetGlobalFragmentUniforms[threadID] = 1
            renderEncoder.setFragmentBuffer(globalFragmentUniformBuffer, offset: globalFragmentUniformOffset, index: 0)
        }
        
        if doingMixedRealityRendering {
            renderEncoder.setRenderPipelineState(mixedRealityJointRenderPipelineState)
        } else {
            renderEncoder.setRenderPipelineState(jointRenderPipelineState)
        }
        renderEncoder.setVertexBuffer(uniformBuffer,  level: .vertexUniform, offset: vertexUniformOffset, index: 1)
        renderEncoder.setVertexBuffer(geometryBuffer, level: .jointBaseVertex,                            index: 2)
        
        renderEncoder.setVertexBuffer(geometryBuffer, level: .jointVertex,                                index: 3)
        renderEncoder.setVertexBuffer(geometryBuffer, level: .jointEdgeVertex,                            index: 4)
        renderEncoder.setVertexBuffer(geometryBuffer, level: .jointEdgeNormal,                            index: 5)
        
        renderEncoder.setFragmentBuffer(uniformBuffer, level: .jointFragmentUniform, offset: fragmentUniformOffset, index: 1)
        renderEncoder.drawIndexedPrimitives(type: .triangle, indexType: .uint16,
                                            indexBuffer:       uniformBuffer.buffer,
                                            indexBufferOffset: uniformBuffer.offset(for: .jointIndex),

                                            indirectBuffer:       uniformBuffer,
                                            indirectBufferLevel: .jointTriangleCount,
                                            indirectBufferOffset: indexedIndirectArgumentsOffset)
        
        if doingMixedRealityRendering {
            renderEncoder.setRenderPipelineState(mixedRealityRectangleRenderPipelineState)
        } else {
            renderEncoder.setRenderPipelineState(rectangleRenderPipelineState)
        }
        renderEncoder.setVertexBuffer(geometryBuffer, level: .rectangleDepthRange,    index: 2, asOffset: true)
        
        renderEncoder.setVertexBuffer(geometryBuffer, level: .rectangleVertex,        index: 3, asOffset: true)
        renderEncoder.setVertexBuffer(geometryBuffer, level: .rectangleTriangleIndex, index: 4, asOffset: true)
        renderEncoder.setVertexBuffer(geometryBuffer, level: .rectangleLineIndex,     index: 5, asOffset: true)
        
        renderEncoder.setFragmentBuffer(uniformBuffer, level: .rectangleFragmentUniform,
                                        offset: fragmentUniformOffset, index: 1, asOffset: true)
        
        renderEncoder.setVertexBuffer(uniformBuffer, level: .isPerimeter, index: 0)
        renderEncoder.drawPrimitives(type: .triangle,               indirectBuffer:       uniformBuffer,
                      indirectBufferLevel: .rectangleTriangleCount, indirectBufferOffset: indirectArgumentsOffset)
        
        renderEncoder.setVertexBuffer(uniformBuffer, level: .isPerimeter, offset: 4, index: 0, asOffset: true)
        renderEncoder.drawIndexedPrimitives(type: .triangle, indexType: .uint16,
                                            indexBuffer:       uniformBuffer.buffer,
                                            indexBufferOffset: uniformBuffer.offset(for: .rectangleIndex),

                                            indirectBuffer:       uniformBuffer,
                                            indirectBufferLevel: .rectangleLineCount,
                                            indirectBufferOffset: indexedIndirectArgumentsOffset)
        
        renderEncoder.popOptDebugGroup()
    }
    
}

extension PendulumMeshConstructor: BufferExpandable {
    
    enum BufferType {
        case geometry
    }
    
    func ensureBufferCapacity(type: BufferType, capacity: Int) {
        let newCapacity = roundUpToPowerOf2(capacity)
        
        switch type {
        case .geometry: geometryBuffer.ensureCapacity(device: device, capacity: newCapacity)
        }
    }
    
}
