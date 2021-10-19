//
//  PendulumMeshConstructorExtensions.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/7/21.
//

import ARHeadsetKit

extension PendulumMeshConstructor {
    
    func updateResources() {
        assert(shouldRenderToDisplay)
        guard statesToRender != nil else { return }
        
        let computeUniformPointer = uniformBuffer[.computeUniform].assumingMemoryBound(to: ComputeUniforms.self)
        computeUniformPointer[renderIndex] = .init(pendulumRenderer: pendulumRenderer)
        
        let cameraPositionPointer = uniformBuffer[.cameraPosition].assumingMemoryBound(to: simd_float3.self)
        let selectedCameraPositionPointer = cameraPositionPointer + renderIndex << 1
        let rawVertexUniformPointer = uniformBuffer[.vertexUniform] + vertexUniformOffset
        
        
        
        let worldToCameraTransformPointer = uniformBuffer[.worldToCameraTransform].assumingMemoryBound(to: simd_float4x4.self)
        let selectedWorldToCameraTransforms = worldToCameraTransformPointer + renderIndex << 1
        
        let transform = usingFlyingMode ? worldToFlyingPerspectiveTransform : worldToCameraTransform
        
        if usingHeadsetMode {
            selectedWorldToCameraTransforms[0] = transform.appendingTranslation(-cameraSpaceLeftEyePosition)
            selectedWorldToCameraTransforms[1] = transform.appendingTranslation(-cameraSpaceRightEyePosition)
            
            selectedCameraPositionPointer[0] = pendulumRenderer.leftEyePosition
            selectedCameraPositionPointer[1] = pendulumRenderer.rightEyePosition
            
            let vertexUniformPointer = rawVertexUniformPointer.assumingMemoryBound(to: MixedRealityUniforms.self)
            vertexUniformPointer.pointee = .init(pendulumRenderer: pendulumRenderer)
        } else {
            selectedWorldToCameraTransforms[0] = transform
            selectedCameraPositionPointer[0] = pendulumRenderer.handheldEyePosition
            
            let vertexUniformPointer = rawVertexUniformPointer.assumingMemoryBound(to: VertexUniforms.self)
            vertexUniformPointer.pointee = .init(pendulumRenderer: pendulumRenderer)
        }
        
        
        
        let jointFragmentUniformPointer = uniformBuffer[.jointFragmentUniform].assumingMemoryBound(to: FragmentUniforms.self)
        jointFragmentUniformPointer[renderIndex] = .init(modelColor: jointColor)
        
        let rectangleFragmentUniformPointer = uniformBuffer[.rectangleFragmentUniform].assumingMemoryBound(to: FragmentUniforms.self)
        rectangleFragmentUniformPointer[renderIndex] = .init(modelColor: rectangleColor)
        
        
        
        @inline(__always)
        func getPointer(_ layer: UniformLayer, offset: Int = 0) -> UnsafeMutablePointer<UInt32> {
            (uniformBuffer[layer] + offset).assumingMemoryBound(to: UInt32.self)
        }
        
        getPointer(.jointTriangleCount,       offset: indexedNumInstancesOffset).pointee = 0
        getPointer(.rectangleTriangleCount,   offset: numInstancesOffset).pointee = 0
        getPointer(.rectangleLineCount,       offset: indexedNumInstancesOffset).pointee = 0
        getPointer(.createJointMeshArguments, offset: createJointMeshArgumentsOffset).pointee = 0
        
        getPointer(.jointVertexCount    )[renderIndex] = 0
        getPointer(.rectangleVertexCount)[renderIndex] = 0
        
        createMesh(statesToRender)
    }
    
    func drawGeometry(renderEncoder: ARMetalRenderCommandEncoder) {
        assert(shouldRenderToDisplay)
        guard statesToRender != nil else { return }
        
        renderEncoder.pushOptDebugGroup("Render Pendulums")
        renderEncoder.pushOptDebugGroup("Render Joints")
        
        renderEncoder.setCullMode(.back)
        renderEncoder.setRenderPipelineState(jointRenderPipelineState)
        
        renderEncoder.setVertexBuffer(uniformBuffer,  layer: .vertexUniform, offset: vertexUniformOffset, index: 1)
        renderEncoder.setVertexBuffer(geometryBuffer, layer: .jointBaseVertex,                            index: 2)
        
        renderEncoder.setVertexBuffer(geometryBuffer, layer: .jointVertex,                                index: 3)
        renderEncoder.setVertexBuffer(geometryBuffer, layer: .jointEdgeVertex,                            index: 4)
        renderEncoder.setVertexBuffer(geometryBuffer, layer: .jointEdgeNormal,                            index: 5)
        
        renderEncoder.setFragmentBuffer(uniformBuffer, layer: .jointFragmentUniform, offset: fragmentUniformOffset, index: 1)
        
        renderEncoder.drawIndexedPrimitives(type:          .triangle,      indexType:           .uint16,
                                            indexBuffer:    uniformBuffer, indexBufferLayer:    .jointIndex,
                                            indirectBuffer: uniformBuffer, indirectBufferLayer: .jointTriangleCount,
                                            indirectLayerOffset: indexedIndirectArgumentsOffset)
        renderEncoder.popOptDebugGroup()
        
        
        
        renderEncoder.pushOptDebugGroup("Render Rectangle Surfaces")
        renderEncoder.setRenderPipelineState(rectangleRenderPipelineState)
        
        renderEncoder.setVertexBuffer(uniformBuffer,  layer: .isPerimeter,            index: 0)
        renderEncoder.setVertexBuffer(geometryBuffer, layer: .rectangleDepthRange,    index: 2, bound: true)
        
        renderEncoder.setVertexBuffer(geometryBuffer, layer: .rectangleVertex,        index: 3, bound: true)
        renderEncoder.setVertexBuffer(geometryBuffer, layer: .rectangleTriangleIndex, index: 4, bound: true)
        renderEncoder.setVertexBuffer(geometryBuffer, layer: .rectangleLineIndex,     index: 5, bound: true)
        
        renderEncoder.setFragmentBuffer(uniformBuffer, layer: .rectangleFragmentUniform, offset: fragmentUniformOffset, index: 1, bound: true)
        
        renderEncoder.drawPrimitives(type:                .triangle,               indirectBuffer:      uniformBuffer,
                                     indirectBufferLayer: .rectangleTriangleCount, indirectLayerOffset: indirectArgumentsOffset)
        renderEncoder.popOptDebugGroup()
        
        
        
        renderEncoder.pushOptDebugGroup("Render Rectangle Perimeters")
        renderEncoder.setVertexBuffer(uniformBuffer, layer: .isPerimeter, offset: 4, index: 0, bound: true)
        
        renderEncoder.drawIndexedPrimitives(type:          .triangle,      indexType:           .uint16,
                                            indexBuffer:    uniformBuffer, indexBufferLayer:    .rectangleIndex,
                                            indirectBuffer: uniformBuffer, indirectBufferLayer: .rectangleLineCount,
                                            indirectLayerOffset: indexedIndirectArgumentsOffset)
        renderEncoder.popOptDebugGroup()
    }
    
}

extension PendulumMeshConstructor {
    
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
