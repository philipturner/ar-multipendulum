//
//  SceneOcclusionTester.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 4/13/21.
//

import Metal
import simd

final class SceneOcclusionTester: DelegateSceneRenderer {
    var sceneRenderer: SceneRenderer
    
    var preCullVertexCount: Int { sceneRenderer.preCullVertexCount }
    var preCullTriangleCount: Int { sceneRenderer.preCullTriangleCount }
    
    var uniformBuffer: MultiLevelBuffer<SceneRenderer.UniformLevel> { sceneRenderer.uniformBuffer }
    
    var colorTextureY: MTLTexture! { renderer.colorTextureY }
    var colorTextureCbCr: MTLTexture! { renderer.colorTextureCbCr }
    var segmentationTexture: MTLTexture! { renderer.segmentationTexture }
    
    var reducedColorBuffer: MTLBuffer { sceneRenderer.reducedColorBuffer }
    var rasterizationComponentBuffer: MTLBuffer!
    var expandedColumnOffsetBuffer: MTLBuffer!
    
    typealias VertexLevel = SceneRenderer.VertexLevel
    typealias VertexDataLevel = SceneCuller.VertexDataLevel
    typealias TriangleDataLevel = SceneTexelRasterizer.TriangleDataLevel
    typealias TriangleMarkLevel = SceneTexelManager.TriangleMarkLevel
    
    typealias SmallColorLevel = SceneTexelManager.SmallColorLevel
    typealias LargeColorLevel = SceneTexelManager.LargeColorLevel
    
    var vertexBuffer: MultiLevelBuffer<VertexLevel> { sceneRenderer.vertexBuffer }
    var vertexDataBuffer: MultiLevelBuffer<VertexDataLevel> { sceneCuller.vertexDataBuffer }
    var triangleDataBuffer: MultiLevelBuffer<TriangleDataLevel>!
    var triangleMarkBuffer: MultiLevelBuffer<TriangleMarkLevel>!
    
    var smallTriangleColorBuffer: MultiLevelBuffer<SmallColorLevel>!
    var largeTriangleColorBuffer: MultiLevelBuffer<LargeColorLevel>!
    
    var smallTriangleLumaTexture: MTLTexture!
    var largeTriangleLumaTexture: MTLTexture!
    var smallTriangleChromaTexture: MTLTexture!
    var largeTriangleChromaTexture: MTLTexture!
    
    var triangleIDBuffer: MTLBuffer
    
    var triangleIDTexture: MTLTexture
    var renderDepthTexture: MTLTexture
    
    var resampledColorTextureY: MTLTexture
    var resampledColorTextureCbCr: MTLTexture
    var resampledColorTextureY_alias: MTLTexture
    
    var renderPipelineState: MTLRenderPipelineState
    var depthStencilState: MTLDepthStencilState
    
    var checkSegmentationTexturePipelineState: MTLComputePipelineState
    var doColorUpdatePipelineState: MTLComputePipelineState
    var resampleColorTexturesPipelineState: MTLComputePipelineState
    
    init(sceneRenderer: SceneRenderer, library: MTLLibrary) {
        self.sceneRenderer = sceneRenderer
        let device = sceneRenderer.device
        
        let triangleCapacity = 65536
        
        let triangleIDBufferSize = triangleCapacity * MemoryLayout<UInt32>.stride
        triangleIDBuffer = device.makeBuffer(length: triangleIDBufferSize, options: .storageModePrivate)!
        triangleIDBuffer.optLabel = "Scene Occlusion Tester Triangle ID Buffer"
        
        typealias RenderArguments = MTLDrawPrimitivesIndirectArguments
        let rawTriangleInstanceCountPointer = sceneRenderer.uniformBuffer[.occlusionTriangleInstanceCount]
        let triangleInstanceCountPointer = rawTriangleInstanceCountPointer.assumingMemoryBound(to: RenderArguments.self)
        triangleInstanceCountPointer.pointee = .init(vertexCount: 3, instanceCount: 0, vertexStart: 0, baseInstance: 0)
        
        typealias ComputeArguments = MTLDispatchThreadgroupsIndirectArguments
        let triangleCountPointer = sceneRenderer.uniformBuffer[.occlusionTriangleCount].assumingMemoryBound(to: ComputeArguments.self)
        triangleCountPointer.pointee = .init(threadgroupsPerGrid: (0, 1, 1))
        
        
        
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.width = 1024
        textureDescriptor.height = 768
        
        textureDescriptor.usage = .renderTarget
        textureDescriptor.storageMode = .memoryless
        textureDescriptor.pixelFormat = .depth16Unorm
        renderDepthTexture = device.makeTexture(descriptor: textureDescriptor)!
        renderDepthTexture.optLabel = "Scene Occlusion Tester Render Depth Texture"
        
        textureDescriptor.usage = [.renderTarget, .shaderWrite, .shaderRead]
        textureDescriptor.storageMode = .private
        textureDescriptor.pixelFormat = .r32Uint
        triangleIDTexture = device.makeTexture(descriptor: textureDescriptor)!
        triangleIDTexture.optLabel = "Scene Occlusion Tester Triangle ID Texture"
        
        textureDescriptor.width  = 768
        textureDescriptor.height = 576
        textureDescriptor.mipmapLevelCount = 7
        
        textureDescriptor.usage = [.shaderWrite, .shaderRead]
        textureDescriptor.pixelFormat = .rg8Unorm
        resampledColorTextureCbCr = device.makeTexture(descriptor: textureDescriptor)!
        resampledColorTextureCbCr.optLabel = "Scene Occlusion Tester Resampled Color Texture (CbCr)"
        
        textureDescriptor.width  = 1536
        textureDescriptor.height = 1152
        textureDescriptor.mipmapLevelCount = 8
        
        textureDescriptor.pixelFormat = .r8Unorm
        resampledColorTextureY = device.makeTexture(descriptor: textureDescriptor)!
        resampledColorTextureY.optLabel = "Scene Occlusion Tester Resampled Color Texture (Y)"
        
        resampledColorTextureY_alias = resampledColorTextureY.makeTextureView(pixelFormat: .r8Unorm, textureType: .type2D,
                                                                              levels: 1..<8, slices: 0..<1)!
        resampledColorTextureY_alias.optLabel = "Scene Occlusion Tester Resampled Color Texture (Y) Alias"
        
        
        
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.vertexFunction   = library.makeFunction(name: "occlusionVertexTransform")!
        renderPipelineDescriptor.fragmentFunction = library.makeFunction(name: "occlusionFragmentShader")!
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = triangleIDTexture.pixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = renderDepthTexture.pixelFormat
        renderPipelineDescriptor.optLabel = "Scene Occlusion Tester Render Pipeline"
        renderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        depthStencilDescriptor.optLabel = "Scene Occlusion Tester Depth-Stencil State"
        depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)!
        
        
        
        checkSegmentationTexturePipelineState = library.makeComputePipeline(Self.self, name: "checkSegmentationTexture")
        doColorUpdatePipelineState            = library.makeComputePipeline(Self.self, name: "doColorUpdate")
        
        let computePipelineDescriptor = MTLComputePipelineDescriptor()
        computePipelineDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = true
        computePipelineDescriptor.computeFunction = library.makeFunction(name: "resampleColorTextures")!
        computePipelineDescriptor.optLabel = "Scene Occlusion Tester Resample Color Textures Pipeline"
        resampleColorTexturesPipelineState = device.makeComputePipelineState(descriptor: computePipelineDescriptor)
    }
}

extension SceneOcclusionTester: BufferExpandable {
    
    enum BufferType {
        case triangle
    }
    
    func ensureBufferCapacity(type: BufferType, capacity: Int) {
        let newCapacity = roundUpToPowerOf2(capacity)
        
        switch type {
        case .triangle: ensureTriangleCapacity(capacity: newCapacity)
        }
    }
    
    private func ensureTriangleCapacity(capacity: Int) {
        let triangleIDBufferSize = capacity * MemoryLayout<UInt32>.stride
        if triangleIDBuffer.length < triangleIDBufferSize {
            triangleIDBuffer = device.makeBuffer(length: triangleIDBufferSize, options: .storageModePrivate)!
            triangleIDBuffer.optLabel = "Scene Occlusion Tester Triangle ID Buffer"
        }
    }
    
}
