//
//  InterfaceRendererExtensions.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/28/21.
//

import Metal
import simd

extension InterfaceRenderer: GeometryRenderer {
    
    func updateResources() {
        assert(shouldRenderToDisplay)
        
        opaqueRenderedElementIndices.removeAll(keepingCapacity: true)
        transparentRenderedElementIndices.removeAll(keepingCapacity: true)
        
        let cameraMeasurements = renderer.cameraMeasurements
        
        for i in 0..<interfaceElements.count {
            if interfaceElements[i].shouldPresent(cameraMeasurements: cameraMeasurements) {
                if interfaceElements[i].surfaceOpacity == 1 {
                    opaqueRenderedElementIndices.append(i)
                } else {
                    transparentRenderedElementIndices.append(i)
                }
            }
        }
        
        numRenderedElements = opaqueRenderedElementIndices.count + transparentRenderedElementIndices.count
        guard numRenderedElements > 0 else { return }
        
        ensureBufferCapacity(type: .uniform, capacity: numRenderedElements)
        
        let rawVertexUniformPointer  = uniformBuffer[.vertexUniform]   + vertexUniformOffset
        let rawFragmentUniformBuffer = uniformBuffer[.fragmentUniform] + fragmentUniformOffset
        var fragmentUniformPointer   = rawFragmentUniformBuffer.assumingMemoryBound(to: FragmentUniforms.self)
        
        @inline(__always)
        func setUniforms<T: InterfaceVertexUniforms>(_ type: T.Type) {
            var vertexUniformPointer = rawVertexUniformPointer.assumingMemoryBound(to: T.self)
            
            for index in opaqueRenderedElementIndices {
                vertexUniformPointer.pointee   = T(interfaceRenderer: self, interfaceElement: interfaceElements[index])
                fragmentUniformPointer.pointee = FragmentUniforms(interfaceElement: interfaceElements[index])
                
                vertexUniformPointer   += 1
                fragmentUniformPointer += 1
            }
            
            for index in transparentRenderedElementIndices {
                vertexUniformPointer.pointee   = T(interfaceRenderer: self, interfaceElement: interfaceElements[index])
                fragmentUniformPointer.pointee = FragmentUniforms(interfaceElement: interfaceElements[index])
                
                vertexUniformPointer   += 1
                fragmentUniformPointer += 1
            }
        }
        
        if doingMixedRealityRendering {
            setUniforms(MixedRealityUniforms.self)
        } else {
            setUniforms(VertexUniforms.self)
        }
        
        opaqueRenderedElementGroupCounts.removeAll(keepingCapacity: true)
        transparentRenderedElementGroupCounts.removeAll(keepingCapacity: true)
        
        var numOpaqueElements = opaqueRenderedElementIndices.count
        var numTransparentElements = transparentRenderedElementIndices.count
        
        while numOpaqueElements > 255 {
            opaqueRenderedElementGroupCounts.append(255)
            numOpaqueElements -= 255
        }
        
        if numOpaqueElements > 0 {
            opaqueRenderedElementGroupCounts.append(numOpaqueElements)
        }
        
        if numTransparentElements > 0 {
            if numOpaqueElements != 255 {
                let firstTransparentElementGroupSize = min(numTransparentElements, 255 - numOpaqueElements)
                transparentRenderedElementGroupCounts.append(firstTransparentElementGroupSize)
                numTransparentElements -= firstTransparentElementGroupSize
            }
            
            while numTransparentElements > 255 {
                transparentRenderedElementGroupCounts.append(255)
                numTransparentElements -= 255
            }
            
            if numTransparentElements > 0 {
                transparentRenderedElementGroupCounts.append(numTransparentElements)
            }
        }
        
        
        
        let commandBuffer = renderer.commandQueue.makeDebugCommandBuffer()
        commandBuffer.optLabel = "Interface Surface Mesh Construction Command Buffer"
        
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.optLabel = "Interface Surface Mesh Construction - Compute Pass"
        
        computeEncoder.pushOptDebugGroup("Create Interface Surface Meshes")
        
        if doingMixedRealityRendering {
            computeEncoder.setComputePipelineState(createMixedRealitySurfaceMeshesPipelineState)
        } else {
            computeEncoder.setComputePipelineState(createSurfaceMeshesPipelineState)
        }
        
        var numSurfacesTimes256 = numRenderedElements << 8
        computeEncoder.setBytes(&numSurfacesTimes256, length: 4, index: 2)
        
        computeEncoder.setBuffer(uniformBuffer,  level: .vertexUniform, offset: vertexUniformOffset, index: 0)
        computeEncoder.setBuffer(geometryBuffer, level: .cornerNormal,                               index: 1)
        
        computeEncoder.setBuffer(uniformBuffer,  level: .surfaceVertex,                              index: 3)
        computeEncoder.setBuffer(uniformBuffer,  level: .surfaceEyeDirection,                        index: 4)
        computeEncoder.setBuffer(uniformBuffer,  level: .surfaceNormal,                              index: 5)
        
        let numVertices = numSurfacesTimes256 + numSurfacesTimes256 >> 4
        computeEncoder.dispatchThreadgroups([ numVertices ], threadsPerThreadgroup: 1)
        
        computeEncoder.endEncoding()
        commandBuffer.commit()
    }
    
    
    
    func drawGeometry(renderEncoder: MTLRenderCommandEncoder, threadID: Int) { fatalError() }
    
    func drawOpaqueGeometry(renderEncoder: MTLRenderCommandEncoder, threadID: Int) {
        assert(shouldRenderToDisplay)
        guard opaqueRenderedElementIndices.count > 0 else { return }
        
        drawGeometry(renderEncoder: renderEncoder, threadID: threadID, renderingTransparentGeometry: false)
    }
    
    func drawTransparentGeometry(renderEncoder: MTLRenderCommandEncoder, threadID: Int) {
        assert(shouldRenderToDisplay)
        guard transparentRenderedElementIndices.count > 0 else { return }
        
        drawGeometry(renderEncoder: renderEncoder, threadID: threadID, renderingTransparentGeometry: true)
    }
    
    private func drawGeometry(renderEncoder: MTLRenderCommandEncoder, threadID: Int, renderingTransparentGeometry: Bool) {
        renderEncoder.pushOptDebugGroup("Render Interface")
        
        if centralRenderer.currentlyCulling[threadID] == 0 {
            centralRenderer.currentlyCulling[threadID] = 1
            renderEncoder.setCullMode(.back)
        }
        
        if centralRenderer.didSetGlobalFragmentUniforms[threadID] == 0 {
            centralRenderer.didSetGlobalFragmentUniforms[threadID] = 1
            renderEncoder.setFragmentBuffer(centralRenderer.globalFragmentUniformBuffer,
                                            offset: centralRenderer.globalFragmentUniformOffset, index: 0)
        }
        
        renderEncoder.setVertexBuffer(geometryBuffer, level: .surfaceVertexAttribute, index: 1)
        
        
        
        var baseVertexUniformOffset   = self.vertexUniformOffset
        var baseFragmentUniformOffset = self.fragmentUniformOffset
        
        let vertexUniformStride = doingMixedRealityRendering ? MemoryLayout<MixedRealityUniforms>.stride
                                                             : MemoryLayout<VertexUniforms>.stride
        
        var surfaceRenderPipelineState: MTLRenderPipelineState
        var startStencilReferenceValue: UInt32
        
        var renderedElementGroupCounts: [Int]
        var renderedElementIndices: [Int]
        
        var baseMeshOffset: Int
        
        @inline(__always)
        func getGeometryOffsets(_ meshStart: Int) -> (Int, Int, Int) {
            if doingMixedRealityRendering {
                return (
                    meshStart * MemoryLayout<simd_float4>.stride,
                    meshStart * MemoryLayout<simd_float3>.stride,
                    meshStart * MemoryLayout<simd_half3>.stride >> 1
                )
            } else {
                return (
                    meshStart * MemoryLayout<simd_float4>.stride,
                    meshStart * MemoryLayout<simd_half3>.stride,
                    meshStart * MemoryLayout<simd_half3>.stride >> 1
                )
            }
        }
        
        if renderingTransparentGeometry {
            baseMeshOffset = opaqueRenderedElementIndices.count
            baseVertexUniformOffset   += baseMeshOffset * vertexUniformStride
            baseFragmentUniformOffset += baseMeshOffset * MemoryLayout<FragmentUniforms>.stride
            
            renderEncoder.setDepthStencilState(depthPassDepthStencilState)

            if doingMixedRealityRendering {
                renderEncoder.setRenderPipelineState(mixedRealityDepthPassPipelineState)
                surfaceRenderPipelineState = mixedRealityTransparentSurfaceRenderPipelineState
            } else {
                renderEncoder.setRenderPipelineState(depthPassPipelineState)
                surfaceRenderPipelineState = transparentSurfaceRenderPipelineState
            }
            
            let meshStart = baseMeshOffset << 8 + baseMeshOffset << 4
            let (vertexOffset, eyeDirectionOffset, normalOffset) = getGeometryOffsets(meshStart)
            
            renderEncoder.setVertexBuffer(uniformBuffer, level: .surfaceVertex,       offset: vertexOffset,       index: 5)
            renderEncoder.setVertexBuffer(uniformBuffer, level: .surfaceEyeDirection, offset: eyeDirectionOffset, index: 6)
            renderEncoder.setVertexBuffer(uniformBuffer, level: .surfaceNormal,       offset: normalOffset,       index: 7)
            
            renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: 266 * 6, indexType: .uint16,
                                                indexBuffer:       geometryBuffer.buffer,
                                                indexBufferOffset: geometryBuffer.offset(for: .surfaceIndex),
                                                instanceCount:     transparentRenderedElementIndices.count)
            
            
            
            startStencilReferenceValue = UInt32(opaqueRenderedElementIndices.last ?? 0)
            
            if startStencilReferenceValue == 255 {
                startStencilReferenceValue = 1
            } else if startStencilReferenceValue > 0 {
                startStencilReferenceValue += 1
            }
            
            renderedElementGroupCounts = transparentRenderedElementGroupCounts
            renderedElementIndices     = transparentRenderedElementIndices
        } else {
            baseMeshOffset = 0
            
            renderEncoder.setVertexBuffer(uniformBuffer, level: .surfaceVertex,       index: 5)
            renderEncoder.setVertexBuffer(uniformBuffer, level: .surfaceEyeDirection, index: 6)
            renderEncoder.setVertexBuffer(uniformBuffer, level: .surfaceNormal,       index: 7)
            
            if doingMixedRealityRendering {
                surfaceRenderPipelineState = mixedRealitySurfaceRenderPipelineState
            } else {
                surfaceRenderPipelineState = self.surfaceRenderPipelineState
            }
            
            startStencilReferenceValue = 0
            
            renderedElementGroupCounts = opaqueRenderedElementGroupCounts
            renderedElementIndices     = opaqueRenderedElementIndices
        }
        
        renderEncoder.setVertexBuffer  (uniformBuffer, level: .vertexUniform,   offset: baseVertexUniformOffset,   index: 0)
        renderEncoder.setFragmentBuffer(uniformBuffer, level: .fragmentUniform, offset: baseFragmentUniformOffset, index: 1)
        
        
        
        var numRenderedSurfaces = 0
        var numRenderedParagraphs = 0
        
        for groupCount in renderedElementGroupCounts {
            if startStencilReferenceValue == 1 {
                renderEncoder.setDepthStencilState(clearStencilDepthStencilState)
                
                if doingMixedRealityRendering {
                    renderEncoder.setRenderPipelineState(mixedRealityClearStencilPipelineState)
                } else {
                    renderEncoder.setRenderPipelineState(clearStencilPipelineState)
                }
                
                renderEncoder.setStencilReferenceValue(0)
                renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            } else {
                startStencilReferenceValue = 1
            }
            
            // Render surfaces
            
            if renderingTransparentGeometry {
                renderEncoder.setDepthStencilState(transparentSurfaceDepthStencilState)
            } else {
                renderEncoder.setDepthStencilState(surfaceDepthStencilState)
            }
            
            renderEncoder.setRenderPipelineState(surfaceRenderPipelineState)
            
            let endStencilReferenceValue = startStencilReferenceValue + UInt32(groupCount)
            var fragmentUniformOffset = baseFragmentUniformOffset
            
            for stencilReferenceValue in startStencilReferenceValue..<endStencilReferenceValue {
                renderEncoder.setStencilReferenceValue(stencilReferenceValue)
                
                if renderingTransparentGeometry {
                    let elementID = renderedElementIndices[numRenderedSurfaces]
                    let opacity = interfaceElements[elementID].surfaceOpacity
                    renderEncoder.setBlendColor(red: .nan, green: .nan, blue: .nan, alpha: opacity)
                }
                
                if numRenderedSurfaces > 0 {
                    let meshOffset = baseMeshOffset + numRenderedSurfaces
                    let meshStart = meshOffset << 8 + meshOffset << 4
                    let (vertexOffset, eyeOffset, normalOffset) = getGeometryOffsets(meshStart)
                    
                    renderEncoder.setVertexBuffer(uniformBuffer, level: .surfaceVertex,       offset: vertexOffset, index: 5, asOffset: true)
                    renderEncoder.setVertexBuffer(uniformBuffer, level: .surfaceEyeDirection, offset: eyeOffset,    index: 6, asOffset: true)
                    renderEncoder.setVertexBuffer(uniformBuffer, level: .surfaceNormal,       offset: normalOffset, index: 7, asOffset: true)
                    
                    renderEncoder.setFragmentBuffer(uniformBuffer, level: .fragmentUniform,
                                                    offset: fragmentUniformOffset, index: 1, asOffset: true)
                }
                
                renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: 266 * 6, indexType: .uint16,
                                                    indexBuffer:       geometryBuffer.buffer,
                                                    indexBufferOffset: geometryBuffer.offset(for: .surfaceIndex))
                
                fragmentUniformOffset += MemoryLayout<FragmentUniforms>.stride
                numRenderedSurfaces   += 1
            }
            
            // Render text

            renderEncoder.setDepthStencilState(textDepthStencilState)

            if doingMixedRealityRendering {
                renderEncoder.setRenderPipelineState(mixedRealityTextRenderPipelineState)
            } else {
                renderEncoder.setRenderPipelineState(textRenderPipelineState)
            }

            var vertexUniformOffset = baseVertexUniformOffset
            fragmentUniformOffset = baseFragmentUniformOffset

            var lastBoundFontID = -1

            for stencilReferenceValue in startStencilReferenceValue..<endStencilReferenceValue {
                let elementID = renderedElementIndices[numRenderedParagraphs]
                let characterGroups = interfaceElements[elementID].characterGroups

                defer {
                    vertexUniformOffset   += vertexUniformStride
                    fragmentUniformOffset += MemoryLayout<FragmentUniforms>.stride
                    numRenderedParagraphs += 1
                }

                guard characterGroups.contains(where: { $0 != nil }) else { continue }
                
                if numRenderedParagraphs > 0 {
                    renderEncoder.setVertexBuffer(uniformBuffer, level: .vertexUniform, offset: vertexUniformOffset,
                                                  index: 0, asOffset: true)
                }
                
                if stencilReferenceValue < groupCount || lastBoundFontID != -1 {
                    renderEncoder.setStencilReferenceValue(stencilReferenceValue)
                    
                    renderEncoder.setFragmentBuffer(uniformBuffer, level: .fragmentUniform, offset: fragmentUniformOffset,
                                                    index: 1, asOffset: true)
                }
                
                for fontID in 0..<fontHandles.count {
                    guard let (boundingRects, glyphIndices) = characterGroups[fontID] else {
                        continue
                    }
                    
                    if lastBoundFontID != fontID {
                        renderEncoder.setVertexBuffer(fontHandles[fontID].texCoordBuffer, offset: 0, index: 2)
                        renderEncoder.setFragmentTexture(fontHandles[fontID].signedDistanceField, index: 0)

                        lastBoundFontID = fontID
                    }

                    var boundingRectPointer = boundingRects.withUnsafeBytes{ $0.baseAddress! }
                    var glyphIndexPointer   = glyphIndices .withUnsafeBytes{ $0.baseAddress! }
                    
                    var i = 0
                    let numCharacters = boundingRects.count
                    
                    while i < numCharacters {
                        let groupSize = min(numCharacters - i, 256)

                        let boundingRectBufferSize = groupSize * MemoryLayout<simd_float4>.stride
                        let glyphIndexBufferSize   = groupSize * MemoryLayout<UInt16>.stride

                        renderEncoder.setVertexBytes(boundingRectPointer, length: boundingRectBufferSize, index: 3)
                        renderEncoder.setVertexBytes(glyphIndexPointer,   length: glyphIndexBufferSize,   index: 4)
                        renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: 6, indexType: .uint16,
                                                            indexBuffer:       geometryBuffer.buffer,
                                                            indexBufferOffset: geometryBuffer.offset(for: .textIndex),
                                                            instanceCount: groupSize, baseVertex: 0, baseInstance: i)
                        
                        i += 256
                        boundingRectPointer += boundingRectBufferSize
                        glyphIndexPointer += glyphIndexBufferSize
                    }
                }
            }
            
            baseVertexUniformOffset   += 255 * vertexUniformStride
            baseFragmentUniformOffset += 255 * MemoryLayout<FragmentUniforms>.stride
            startStencilReferenceValue = 1
        }
        
        renderEncoder.popOptDebugGroup()
    }
    
}

extension InterfaceRenderer: BufferExpandable {
    
    enum BufferType {
        case uniform
    }
    
    func ensureBufferCapacity(type: BufferType, capacity: Int) {
        let newCapacity = roundUpToPowerOf2(capacity)
        
        switch type {
        case .uniform: uniformBuffer.ensureCapacity(device: device, capacity: newCapacity)
        }
    }
    
}
