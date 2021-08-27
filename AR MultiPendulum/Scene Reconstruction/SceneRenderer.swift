//
//  SceneRenderer.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 4/13/21.
//

import Metal
import ARKit

final class SceneRenderer: DelegateRenderer {
    var renderer: Renderer
    
    static let profilingSceneReconstruction = false
    
    var doingRendering = false
    var segmentationTextureSemaphore = DispatchSemaphore(value: 0)
    var colorTextureSemaphore = DispatchSemaphore(value: 0)
    var updateResourcesSemaphore = DispatchSemaphore(value: 0)
    
    var currentlyMatchingMeshes = false
    var justCompletedMatching = false
    var completedMatchingBeforeLastFrame = false
    
    var meshToWorldTransform = simd_float4x4(1)
    var colorSampleCounter = -1
    
    var colorSamplingRate: Int {
        if SceneRenderer.profilingSceneReconstruction {
            return 1
        }
        
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return 6
        case .fair:     return 9
        case .serious:  return 24
        case .critical: return 100_000_000
        @unknown default: fatalError("This thermal state is not possible!")
        }
    }
    
    struct VertexUniforms {
        var viewProjectionTransform: simd_float4x4
        var cameraProjectionTransform: simd_float4x4
        
        init(sceneRenderer: SceneRenderer, camera: ARCamera) {
            cameraProjectionTransform = camera.projectionMatrix(for: .landscapeRight,
                                                                viewportSize: .init(width: 256, height: 192),
                                                                zNear: 0.026, zFar: 1000)
            cameraProjectionTransform *= sceneRenderer.worldToCameraTransform
            
            viewProjectionTransform = sceneRenderer.doingMixedRealityRendering
                                    ? sceneRenderer.worldToMixedRealityCullTransform
                                    : sceneRenderer.worldToScreenClipTransform
            
            viewProjectionTransform   *= sceneRenderer.meshToWorldTransform
            cameraProjectionTransform *= sceneRenderer.meshToWorldTransform
        }
    }
    
    struct MixedRealityUniforms {
        var leftProjectionTransform: simd_float4x4
        
        init(sceneRenderer: SceneRenderer) {
            leftProjectionTransform = sceneRenderer.worldToLeftClipTransform * sceneRenderer.meshToWorldTransform
        }
    }
    
    enum UniformLevel: UInt8, MultiLevelBufferLevel {
        case vertexUniform
        case mixedRealityUniform
        
        case preCullVertexCount
        case preCullTriangleCount
        
        case triangleVertexCount
        case occlusionTriangleInstanceCount
        case occlusionTriangleCount
        
        static let bufferLabel = "Scene Renderer Uniform Buffer"
        
        func getSize(capacity _: Int) -> Int {
            switch self {
            case .vertexUniform:                  return Renderer.numRenderBuffers * MemoryLayout<VertexUniforms>.stride
            case .mixedRealityUniform:            return Renderer.numRenderBuffers * MemoryLayout<MixedRealityUniforms>.stride
            
            case .preCullVertexCount:             return Renderer.numRenderBuffers * MemoryLayout<UInt32>.stride
            case .preCullTriangleCount:           return Renderer.numRenderBuffers * MemoryLayout<UInt32>.stride
            
            case .triangleVertexCount:            return MemoryLayout<MTLDrawPrimitivesIndirectArguments>.stride
            case .occlusionTriangleInstanceCount: return MemoryLayout<MTLDrawPrimitivesIndirectArguments>.stride
            case .occlusionTriangleCount:         return MemoryLayout<MTLDispatchThreadgroupsIndirectArguments>.stride
            }
        }
    }
    
    enum VertexLevel: UInt8, MultiLevelBufferLevel {
        case renderVertex
        case occlusionVertex
        case videoFrameCoord
        
        static let bufferLabel = "Scene Renderer Vertex Buffer"
        
        func getSize(capacity: Int) -> Int {
            switch self {
            case .renderVertex:    return capacity * MemoryLayout<simd_float4>.stride
            case .occlusionVertex: return capacity * MemoryLayout<simd_float4>.stride
            case .videoFrameCoord: return capacity * MemoryLayout<simd_float2>.stride
            }
        }
    }
    
    var uniformBuffer: MultiLevelBuffer<UniformLevel>
    var vertexBuffer: MultiLevelBuffer<VertexLevel>
    
    var triangleIDBuffer: MTLBuffer
    
    var reducedVertexBuffer: MTLBuffer!
    var reducedNormalBuffer: MTLBuffer!
    var reducedColorBuffer: MTLBuffer!
    var reducedIndexBuffer: MTLBuffer!
    
    var preCullVertexCount: Int!
    var preCullTriangleCount: Int!
    var preCullVertexCountOffset: Int { renderIndex * MemoryLayout<UInt32>.stride }
    var preCullTriangleCountOffset: Int { renderIndex * MemoryLayout<UInt32>.stride }
    
    var vertexUniformOffset: Int { renderIndex * MemoryLayout<VertexUniforms>.stride }
    var mixedRealityUniformOffset: Int { renderIndex * MemoryLayout<MixedRealityUniforms>.stride }
    
    var renderPipelineState: MTLRenderPipelineState
    var modifiedPerspectiveRenderPipelineState: MTLRenderPipelineState
    var mixedRealityRenderPipelineState: MTLRenderPipelineState
    
    var sceneMeshReducer: SceneMeshReducer!
    var sceneSorter: SceneSorter!
    var sceneDuplicateRemover: SceneDuplicateRemover!
    var sceneMeshMatcher: SceneMeshMatcher!
    var sceneTexelRasterizer: SceneTexelRasterizer!
    var sceneTexelManager: SceneTexelManager!
    
    var sceneCuller: SceneCuller!
    var sceneOcclusionTester: SceneOcclusionTester!
    
    init(renderer: Renderer, library: MTLLibrary) {
        self.renderer = renderer
        let device = renderer.device
        
        let vertexCapacity = 32768
        let triangleCapacity = 65536
        
        uniformBuffer = device.makeMultiLevelBuffer(capacity: 1, options: .storageModeShared)
        vertexBuffer  = device.makeMultiLevelBuffer(capacity: vertexCapacity)
        
        let triangleIDBufferSize = triangleCapacity * MemoryLayout<UInt32>.stride
        triangleIDBuffer = device.makeBuffer(length: triangleIDBufferSize, options: .storageModePrivate)!
        triangleIDBuffer.optLabel = "Scene Triangle ID Buffer"
        
        typealias RenderArguments = MTLDrawPrimitivesIndirectArguments
        let triangleVertexCountPointer = uniformBuffer[.triangleVertexCount].assumingMemoryBound(to: RenderArguments.self)
        triangleVertexCountPointer.pointee = .init(vertexCount: 3, instanceCount: 0, vertexStart: 0, baseInstance: 0)
        
        
    
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.sampleCount = 4
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = renderer.msaaTexture.pixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
        renderPipelineDescriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
        renderPipelineDescriptor.inputPrimitiveTopology = .triangle
        
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: "sceneVertexTransform")!
        renderPipelineDescriptor.fragmentFunction = library.makeFunction(name: "sceneFragmentShader")!
        renderPipelineDescriptor.optLabel = "Scene Render Pipeline"
        renderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        
        renderPipelineDescriptor.fragmentFunction = library.makeFunction(name: "sceneMRFragmentShader")!
        renderPipelineDescriptor.optLabel = "Scene Modifed Perspective Render Pipeline"
        modifiedPerspectiveRenderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        
        
        
        if renderer.usingVertexAmplification { renderPipelineDescriptor.maxVertexAmplificationCount = 2 }
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = .rg11b10Float
        
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: renderer.usingVertexAmplification
                                                                           ? "sceneMRVertexTransform"
                                                                           : "sceneMRVertexTransform2")!
        renderPipelineDescriptor.optLabel = "Scene Mixed Reality Render Pipeline"
        mixedRealityRenderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        
        
        
        sceneMeshReducer      = SceneMeshReducer     (sceneRenderer: self, library: library)
        sceneSorter           = SceneSorter          (sceneRenderer: self, library: library)
        sceneDuplicateRemover = SceneDuplicateRemover(sceneRenderer: self, library: library)
        sceneMeshMatcher      = SceneMeshMatcher     (sceneRenderer: self, library: library)
        sceneTexelRasterizer  = SceneTexelRasterizer (sceneRenderer: self, library: library)
        sceneTexelManager     = SceneTexelManager    (sceneRenderer: self, library: library)
        
        sceneCuller          = SceneCuller         (sceneRenderer: self, library: library)
        sceneOcclusionTester = SceneOcclusionTester(sceneRenderer: self, library: library)
    }
}



protocol DelegateSceneRenderer {
    var sceneRenderer: SceneRenderer { get }
    
    init(sceneRenderer: SceneRenderer, library: MTLLibrary)
}

extension DelegateSceneRenderer {
    var renderer: Renderer { sceneRenderer.renderer }
    var device: MTLDevice { sceneRenderer.device }
    var renderIndex: Int { sceneRenderer.renderIndex }
    
    var doingMixedRealityRendering: Bool { sceneRenderer.doingMixedRealityRendering }
    var usingModifiedPerspective: Bool { sceneRenderer.usingModifiedPerspective }
    
    var reducedVertexBuffer: MTLBuffer { sceneRenderer.reducedVertexBuffer }
    var reducedNormalBuffer: MTLBuffer { sceneRenderer.reducedNormalBuffer }
    var reducedColorBuffer: MTLBuffer { sceneRenderer.reducedColorBuffer }
    var reducedIndexBuffer: MTLBuffer { sceneRenderer.reducedIndexBuffer }
    
    var vertexUniformOffset: Int { sceneRenderer.vertexUniformOffset }
    var mixedRealityUniformOffset: Int { sceneRenderer.mixedRealityUniformOffset }
    
    var sceneMeshReducer: SceneMeshReducer { sceneRenderer.sceneMeshReducer }
    var sceneSorter: SceneSorter { sceneRenderer.sceneSorter }
    var sceneDuplicateRemover: SceneDuplicateRemover { sceneRenderer.sceneDuplicateRemover }
    var sceneMeshMatcher: SceneMeshMatcher { sceneRenderer.sceneMeshMatcher }
    var sceneTexelRasterizer: SceneTexelRasterizer { sceneRenderer.sceneTexelRasterizer }
    var sceneTexelManager: SceneTexelManager { sceneRenderer.sceneTexelManager }
    
    var sceneCuller: SceneCuller { sceneRenderer.sceneCuller }
    var sceneOcclusionTester: SceneOcclusionTester { sceneRenderer.sceneOcclusionTester }
}
