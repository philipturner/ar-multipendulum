//
//  SceneRenderer2D.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/13/21.
//

import Metal
import simd

final class SceneRenderer2D: DelegateRenderer {
    var renderer: Renderer
    
    var cameraPlaneDepth: Float = 2
    var colorTextureSemaphore = DispatchSemaphore(value: 0)
    var updateResourcesSemaphore = DispatchSemaphore(value: 0)
    
    var renderPipelineState: MTLRenderPipelineState
    var mixedRealityRenderPipelineState: MTLRenderPipelineState
    
    init(renderer: Renderer, library: MTLLibrary) {
        self.renderer = renderer
        let device = renderer.device
        
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.sampleCount = 4
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = renderer.msaaTexture.pixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
        renderPipelineDescriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
        renderPipelineDescriptor.inputPrimitiveTopology = .triangle
        
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: "scene2DVertexTransform")!
        renderPipelineDescriptor.fragmentFunction = library.makeFunction(name: "scene2DFragmentShader")!
        renderPipelineDescriptor.optLabel = "Scene 2D Render Pipeline"
        renderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        
        
        
        if renderer.usingVertexAmplification { renderPipelineDescriptor.maxVertexAmplificationCount = 2 }
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = .rg11b10Float
        
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: renderer.usingVertexAmplification
                                                                           ? "scene2DMRVertexTransform"
                                                                           : "scene2DMRVertexTransform2")!
        renderPipelineDescriptor.optLabel = "Scene 2D Mixed Reality Render Pipeline"
        mixedRealityRenderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
    }
}

extension SceneRenderer2D: GeometryRenderer {
    
    func asyncUpdateResources() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            colorTextureSemaphore.wait()
            updateResourcesSemaphore.signal()
            
            if doingMixedRealityRendering, !usingVertexAmplification, shouldRenderToDisplay {
                updateResourcesSemaphore.signal()
            }
        }
    }
    
    func drawGeometry(renderEncoder: MTLRenderCommandEncoder, threadID: Int) {
        assert(shouldRenderToDisplay)
        renderEncoder.pushOptDebugGroup("Render Scene (2D)")
        
        if usingModifiedPerspective {
            if centralRenderer.currentlyCulling[threadID] != 0 {
                centralRenderer.currentlyCulling[threadID] = 0
                renderEncoder.setCullMode(.none)
            }
        } else {
            if centralRenderer.currentlyCulling[threadID] != 1 {
                centralRenderer.currentlyCulling[threadID] = 1
                renderEncoder.setCullMode(.back)
            }
        }
        
        var projectionTransforms = [simd_float4x4](unsafeUninitializedCount: 2)
        var projectionTransformsNumBytes: Int
        
        if doingMixedRealityRendering {
            renderEncoder.setRenderPipelineState(mixedRealityRenderPipelineState)
            
            projectionTransforms[0] = worldToLeftClipTransform  * cameraToWorldTransform
            projectionTransforms[1] = worldToRightClipTransform * cameraToWorldTransform
            projectionTransformsNumBytes = 2 * MemoryLayout<simd_float4x4>.stride
        } else {
            renderEncoder.setRenderPipelineState(renderPipelineState)
            
            projectionTransforms[0] = worldToScreenClipTransform * cameraToWorldTransform
            projectionTransformsNumBytes = MemoryLayout<simd_float4x4>.stride
        }
        
        renderEncoder.setVertexBytes(&projectionTransforms, length: projectionTransformsNumBytes, index: 0)
        
        struct VertexUniforms {
            var pixelWidth: Float
            var cameraPlaneDepth: Float
            var usingModifiedPerspective: Bool
        }
        
        let pixelWidth = Float(renderer.cameraMeasurements.currentPixelWidth)
        var vertexUniforms = VertexUniforms(pixelWidth: pixelWidth * cameraPlaneDepth,
                                            cameraPlaneDepth: cameraPlaneDepth,
                                            usingModifiedPerspective: usingModifiedPerspective)
        
        renderEncoder.setVertexBytes(&vertexUniforms, length: MemoryLayout<VertexUniforms>.stride, index: 1)
        
        renderEncoder.setFragmentTexture(colorTextureY,    index: 0)
        renderEncoder.setFragmentTexture(colorTextureCbCr, index: 1)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        
        renderEncoder.popOptDebugGroup()
    }
}
