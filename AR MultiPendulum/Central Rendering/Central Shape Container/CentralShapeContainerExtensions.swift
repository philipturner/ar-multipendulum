//
//  CentralShapeContainerExtensions.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 4/19/21.
//

import Metal
import simd

extension CentralShapeContainer {
    
    mutating func clearAliases() {
        numAliases = 0
        
        for i in 0..<sizeRange.count {
            aliases[i].removeAll()
        }
    }
    
    mutating func ensureAliasCapacity() {
        let newCapacity = roundUpToPowerOf2(numAliases)
        uniformBuffer.ensureCapacity(device: device, capacity: newCapacity)
    }
    
    mutating func updateResources() {
        ensureAliasCapacity()
        
        let bufferElementOffset = renderIndex * uniformBuffer.capacity
        
        var fragmentUniformPointer = uniformBuffer[.fragment].assumingMemoryBound(to: FragmentUniforms.self)
        fragmentUniformPointer += bufferElementOffset
        
        let vertexUniformOffset = bufferElementOffset * MemoryLayout<MixedRealityUniforms>.stride
        let rawVertexUniformPointer = uniformBuffer[.vertex] + vertexUniformOffset
        
        @inline(__always)
        func addUniforms<T: CentralVertexUniforms>(_ type: T.Type) {
            var vertexUniformPointer = rawVertexUniformPointer.assumingMemoryBound(to: T.self)
            
            aliases.forEach{ $0.forEach {
                vertexUniformPointer.pointee   = T(centralRenderer: centralRenderer, alias: $0)
                fragmentUniformPointer.pointee = FragmentUniforms(alias: $0)
                
                vertexUniformPointer   += 1
                fragmentUniformPointer += 1
            }}
        }
        
        if doingMixedRealityRendering {
            addUniforms(MixedRealityUniforms.self)
        } else {
            addUniforms(VertexUniforms.self)
        }
    }
    
    func drawGeometry(renderEncoder: MTLRenderCommandEncoder, threadID: Int) {
        guard numAliases > 0 else {
            return
        }
        
        if Self.shapeType == .cylinder {
            renderEncoder.setRenderPipelineState(doingMixedRealityRendering
                                               ? centralRenderer.mixedRealityCylinderRenderPipelineState
                                               : centralRenderer.cylinderRenderPipelineState)
        } else if Self.shapeType == .cone {
            renderEncoder.setRenderPipelineState(doingMixedRealityRendering
                                               ? centralRenderer.mixedRealityConeRenderPipelineState
                                               : centralRenderer.coneRenderPipelineState)
        } else if centralRenderer.didSetRenderPipeline[threadID] == 0 {
            renderEncoder.setRenderPipelineState(doingMixedRealityRendering
                                               ? centralRenderer.mixedRealityRenderPipelineState
                                               : centralRenderer.renderPipelineState)
        }
        
        if centralRenderer.didSetRenderPipeline[threadID] == 0 {
            centralRenderer.didSetRenderPipeline[threadID] = 1
            
            if centralRenderer.didSetGlobalFragmentUniforms[threadID] == 0 {
                centralRenderer.didSetGlobalFragmentUniforms[threadID] = 1
                renderEncoder.setFragmentBuffer(centralRenderer.globalFragmentUniformBuffer,
                                                offset: centralRenderer.globalFragmentUniformOffset, index: 0)
            }
        }
        
        renderEncoder.pushOptDebugGroup("Render \(Self.shapeType.toString)s")
        
        let bufferElementOffset   = renderIndex * uniformBuffer.capacity
        var vertexUniformOffset   = bufferElementOffset * MemoryLayout<MixedRealityUniforms>.stride
        var fragmentUniformOffset = bufferElementOffset * MemoryLayout<FragmentUniforms>.stride
        
        let normalOffset = self.normalOffset
        let indexOffset  = self.indexOffset
        
        let vertexUniformStride = doingMixedRealityRendering ? MemoryLayout<MixedRealityUniforms>.stride
                                                             : MemoryLayout<VertexUniforms>.stride
        var alreadySetVertexBuffers = false
        var alreadySetUniforms = false
        
        for i in 0..<shapes.count {
            let numObjects = aliases[i].count
            if numObjects == 0 {
                continue
            }
            
            let shape = shapes[i]
            let fullVertexOffset = shape.normalOffset << 1
            let fullNormalOffset = shape.normalOffset + normalOffset
            
            if !alreadySetVertexBuffers {
                alreadySetVertexBuffers = true
                
                renderEncoder.setVertexBuffer(geometryBuffer, offset: fullVertexOffset, index: 0)
                renderEncoder.setVertexBuffer(geometryBuffer, offset: fullNormalOffset, index: 1)
            } else {
                renderEncoder.setVertexBufferOffset(fullVertexOffset, index: 0)
                renderEncoder.setVertexBufferOffset(fullNormalOffset, index: 1)
            }
            
            let fullIndexOffset = indexOffset + shape.indexOffset
            
            for j in 0..<2 {
                let subGroupSize = j == 0 ? aliases[i].closeAliases.count
                                          : aliases[i].farAliases.count
                if subGroupSize == 0 {
                    continue
                }
                
                renderEncoder.setVertexBuffer(uniformBuffer, level: .vertex, offset: vertexUniformOffset,
                                              index: 2, asOffset: alreadySetUniforms)
                
                renderEncoder.setFragmentBuffer(uniformBuffer, level: .fragment, offset: fragmentUniformOffset,
                                                index: 1, asOffset: alreadySetUniforms)
                
                alreadySetUniforms = true
                
                if centralRenderer.currentlyCulling[threadID] != j {
                    centralRenderer.currentlyCulling[threadID] = j
                    
                    renderEncoder.setCullMode(j == 1 ? .back : .none)
                }
                
                renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: shape.numIndices, indexType: .uint16,
                                                    indexBuffer: geometryBuffer, indexBufferOffset: fullIndexOffset,
                                                    instanceCount: subGroupSize)
                
                vertexUniformOffset   += subGroupSize * vertexUniformStride
                fragmentUniformOffset += subGroupSize * MemoryLayout<FragmentUniforms>.stride
            }
        }
        
        renderEncoder.popOptDebugGroup()
    }
    
}
