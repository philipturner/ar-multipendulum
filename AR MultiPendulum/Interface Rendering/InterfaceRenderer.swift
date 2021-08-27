//
//  InterfaceRenderer.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/28/21.
//

import Metal
import simd

protocol InterfaceVertexUniforms {
    init(interfaceRenderer: InterfaceRenderer, interfaceElement: InterfaceRenderer.InterfaceElement)
}

final class InterfaceRenderer: DelegateRenderer {
    var renderer: Renderer
    var fontHandles: [FontHandle] { Self.fontHandles }
    
    var interfaceElements: [InterfaceElement] = []
    var numRenderedElements = -1
    
    var opaqueRenderedElementIndices: [Int] = []
    var opaqueRenderedElementGroupCounts: [Int] = []
    var transparentRenderedElementIndices: [Int] = []
    var transparentRenderedElementGroupCounts: [Int] = []
    
    struct VertexUniforms: InterfaceVertexUniforms {
        var projectionTransform: simd_float4x4
        var eyeDirectionTransform: simd_float4x4
        var normalTransform: simd_half3x3
        
        var controlPoints: simd_float4x2
        
        init(interfaceRenderer: InterfaceRenderer, interfaceElement: InterfaceElement) {
            let modelToWorldTransform = interfaceElement.modelToWorldTransform
            projectionTransform = interfaceRenderer.worldToScreenClipTransform * modelToWorldTransform
            eyeDirectionTransform = (-modelToWorldTransform).appendingTranslation(interfaceRenderer.handheldEyePosition)
            
            normalTransform = interfaceElement.normalTransform
            controlPoints = interfaceElement.controlPoints
        }
    }
    
    struct MixedRealityUniforms: InterfaceVertexUniforms {
        var leftProjectionTransform: simd_float4x4
        var rightProjectionTransform: simd_float4x4
        
        var leftEyeDirectionTransform: simd_float4x4
        var rightEyeDirectionTransform: simd_float4x4
        var normalTransform: simd_half3x3
        
        var controlPoints: simd_float4x2
        
        init(interfaceRenderer: InterfaceRenderer, interfaceElement: InterfaceElement) {
            let modelToWorldTransform = interfaceElement.modelToWorldTransform
            leftProjectionTransform  = interfaceRenderer.worldToLeftClipTransform  * modelToWorldTransform
            rightProjectionTransform = interfaceRenderer.worldToRightClipTransform * modelToWorldTransform
            
            leftEyeDirectionTransform  = (-modelToWorldTransform).appendingTranslation(interfaceRenderer.leftEyePosition)
            rightEyeDirectionTransform = (-modelToWorldTransform).appendingTranslation(interfaceRenderer.rightEyePosition)
            
            normalTransform = interfaceElement.normalTransform
            controlPoints = interfaceElement.controlPoints
        }
    }
    
    struct FragmentUniforms {
        var surfaceColor: simd_packed_half3
        var surfaceShininess: Float16
        
        var textColor: simd_half3
        var textShininess: Float16
        var textOpacity: Float16
        
        init(interfaceElement: InterfaceElement) {
            surfaceColor     = interfaceElement.surfaceColor
            surfaceShininess = interfaceElement.surfaceShininess
            
            textColor     = interfaceElement.textColor
            textShininess = interfaceElement.textShininess
            textOpacity   = interfaceElement.textOpacity
        }
    }
    
    enum UniformLevel: UInt8, MultiLevelBufferLevel {
        case vertexUniform
        case fragmentUniform
        
        case surfaceVertex
        case surfaceEyeDirection
        case surfaceNormal
        
        static let bufferLabel = "Interface Renderer Uniform Buffer"
        
        func getSize(capacity: Int) -> Int {
            switch self {
            case .vertexUniform:       return capacity * Renderer.numRenderBuffers  * MemoryLayout<MixedRealityUniforms>.stride
            case .fragmentUniform:     return capacity * Renderer.numRenderBuffers  * MemoryLayout<FragmentUniforms>.stride
            
            case .surfaceVertex:       return capacity * 272     * MemoryLayout<simd_float4>.stride
            case .surfaceEyeDirection: return capacity * 272     * MemoryLayout<simd_float3>.stride
            case .surfaceNormal:       return capacity * 272 / 2 * MemoryLayout<simd_half3>.stride
            }
        }
    }
    
    enum GeometryLevel: UInt8, MultiLevelBufferLevel {
        case cornerNormal
        case surfaceVertexAttribute
        
        case surfaceIndex
        case textIndex
        
        static let bufferLabel = "Interface Renderer Geometry Buffer"
        
        func getSize(capacity _: Int) -> Int {
            switch self {
            case .cornerNormal:           return 32  * MemoryLayout<simd_half2>.stride
            case .surfaceVertexAttribute: return 536 * MemoryLayout<simd_ushort2>.stride
            
            case .surfaceIndex:           return 266 * 6 * MemoryLayout<UInt16>.stride
            case .textIndex:              return       6 * MemoryLayout<UInt16>.stride
            }
        }
    }
    
    var uniformBuffer: MultiLevelBuffer<UniformLevel>
    var geometryBuffer: MultiLevelBuffer<GeometryLevel>
    
    var vertexUniformOffset: Int { renderIndex * uniformBuffer.capacity * MemoryLayout<MixedRealityUniforms>.stride }
    var fragmentUniformOffset: Int { renderIndex * uniformBuffer.capacity * MemoryLayout<FragmentUniforms>.stride }
    
    var createSurfaceMeshesPipelineState: MTLComputePipelineState
    var createMixedRealitySurfaceMeshesPipelineState: MTLComputePipelineState
    
    var textRenderPipelineState: MTLRenderPipelineState
    var surfaceRenderPipelineState: MTLRenderPipelineState
    var clearStencilPipelineState: MTLRenderPipelineState
    var depthPassPipelineState: MTLRenderPipelineState
    var transparentSurfaceRenderPipelineState: MTLRenderPipelineState
    
    var mixedRealityTextRenderPipelineState: MTLRenderPipelineState
    var mixedRealitySurfaceRenderPipelineState: MTLRenderPipelineState
    var mixedRealityClearStencilPipelineState: MTLRenderPipelineState
    var mixedRealityDepthPassPipelineState: MTLRenderPipelineState
    var mixedRealityTransparentSurfaceRenderPipelineState: MTLRenderPipelineState
    
    var textDepthStencilState: MTLDepthStencilState
    var surfaceDepthStencilState: MTLDepthStencilState
    var clearStencilDepthStencilState: MTLDepthStencilState
    var depthPassDepthStencilState: MTLDepthStencilState
    var transparentSurfaceDepthStencilState: MTLDepthStencilState
    
    init(renderer: Renderer, library: MTLLibrary) {
        self.renderer = renderer
        let device = renderer.device
        
        uniformBuffer  = device.makeMultiLevelBuffer(capacity: 8, options: [.cpuCacheModeWriteCombined, .storageModeShared])
        geometryBuffer = device.makeMultiLevelBuffer(capacity: 1, options: [.cpuCacheModeWriteCombined, .storageModeShared])
        
        let cornerNormalPointer = geometryBuffer[.cornerNormal].assumingMemoryBound(to: SIMD8<Float16>.self)
        
        for i in 0..<32 >> 2 {
            let indices = simd_uint4(repeating: UInt32(i << 2)) &+ simd_uint4(0, 1, 2, 3)
            let angles = simd_float4(indices) * (.pi / 2 / 32)
            
            let sines = sin(angles)
            let cosines = sqrt(fma(-sines, sines, 1))
            
            let output1 = simd_half4(simd_float4(cosines[0], sines[0], cosines[1], sines[1]))
            let output2 = simd_half4(simd_float4(cosines[2], sines[2], cosines[3], sines[3]))
            
            cornerNormalPointer[i] = .init(lowHalf: output1, highHalf: output2)
        }
        
        let surfaceMeshIndicesURL = Bundle.main.url(forResource: "InterfaceSurfaceMeshIndices", withExtension: "data")!
        let surfaceMeshIndexData = try! Data(contentsOf: surfaceMeshIndicesURL)
        
        let vertexAttributeDestinationPointer = geometryBuffer[.surfaceVertexAttribute]
        let vertexAttributeSourcePointer = surfaceMeshIndexData.withUnsafeBytes{ $0.baseAddress! }
        let vertexAttributeBufferSize = GeometryLevel.surfaceVertexAttribute.getSize(capacity: 1)
        memcpy(vertexAttributeDestinationPointer, vertexAttributeSourcePointer, vertexAttributeBufferSize)
        
        let surfaceIndexDestinationPointer = geometryBuffer[.surfaceIndex]
        let surfaceIndexSourcePointer = vertexAttributeSourcePointer + vertexAttributeBufferSize
        let surfaceIndexBufferSize = GeometryLevel.surfaceIndex.getSize(capacity: 1)
        memcpy(surfaceIndexDestinationPointer, surfaceIndexSourcePointer, surfaceIndexBufferSize)
        
        let textIndexPointer = geometryBuffer[.textIndex].assumingMemoryBound(to: simd_uint3.self)
        textIndexPointer[0] = .init(unsafeBitCast(simd_ushort2(0, 1), to: UInt32.self),
                                    unsafeBitCast(simd_ushort2(2, 0), to: UInt32.self),
                                    unsafeBitCast(simd_ushort2(2, 3), to: UInt32.self))
        
        createSurfaceMeshesPipelineState             = library.makeComputePipeline(Self.self, name: "createInterfaceSurfaceMeshes")
        createMixedRealitySurfaceMeshesPipelineState = library.makeComputePipeline(Self.self, name: "createInterfaceMRSurfaceMeshes")
        
        
        
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.sampleCount = 4
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = renderer.msaaTexture.pixelFormat
        
        renderPipelineDescriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
        renderPipelineDescriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
        renderPipelineDescriptor.inputPrimitiveTopology = .triangle
        
        let surfaceFragmentShader = library.makeFunction(name: "pendulumFragmentShader")!
        renderPipelineDescriptor.fragmentFunction = surfaceFragmentShader
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: "interfaceSurfaceTransform")!
        renderPipelineDescriptor.optLabel = "Interface Surface Render Pipeline"
        surfaceRenderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        
        renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        renderPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .blendAlpha
        renderPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusBlendAlpha
        renderPipelineDescriptor.optLabel = "Interface Transparent Surface Render Pipeline"
        transparentSurfaceRenderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        
        let textFragmentShader = library.makeFunction(name: "interfaceTextFragmentShader")!
        renderPipelineDescriptor.fragmentFunction = textFragmentShader
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: "interfaceTextTransform")!
        renderPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        renderPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        renderPipelineDescriptor.optLabel = "Interface Text Render Pipeline"
        textRenderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        
        
        
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: "interfaceDepthPassTransform")!
        renderPipelineDescriptor.fragmentFunction = nil
        renderPipelineDescriptor.optLabel = "Interface Depth Pass Pipeline"
        depthPassPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: "clearStencilVertexTransform")!
        renderPipelineDescriptor.optLabel = "Clear Stencil Render Pipeline"
        clearStencilPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        
        if renderer.usingVertexAmplification { renderPipelineDescriptor.maxVertexAmplificationCount = 2 }
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = .rg11b10Float
        
        renderPipelineDescriptor.optLabel = "Mixed Reality Clear Stencil Render Pipeline State"
        mixedRealityClearStencilPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: renderer.usingVertexAmplification
                                                                           ? "interfaceMRDepthPassTransform"
                                                                           : "interfaceMRDepthPassTransform2")!
        renderPipelineDescriptor.optLabel = "Interface Mixed Reality Depth Pass Pipeline"
        mixedRealityDepthPassPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        
        
        
        renderPipelineDescriptor.fragmentFunction = textFragmentShader
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: renderer.usingVertexAmplification
                                                                           ? "interfaceMRTextTransform"
                                                                           : "interfaceMRTextTransform2")!
        renderPipelineDescriptor.optLabel = "Interface Mixed Reality Text Render Pipeline"
        mixedRealityTextRenderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        
        renderPipelineDescriptor.fragmentFunction = surfaceFragmentShader
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: renderer.usingVertexAmplification
                                                                           ? "interfaceMRSurfaceTransform"
                                                                           : "interfaceMRSurfaceTransform2")
        renderPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .blendAlpha
        renderPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusBlendAlpha
        renderPipelineDescriptor.optLabel = "Interface Mixed Reality Transparent Surface Render Pipeline"
        mixedRealityTransparentSurfaceRenderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        
        renderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
        renderPipelineDescriptor.optLabel = "Interface Mixed Reality Surface Render Pipeline"
        mixedRealitySurfaceRenderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        
        
        
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.frontFaceStencil = .init()
        depthStencilDescriptor.frontFaceStencil.depthStencilPassOperation = .replace
        depthStencilDescriptor.optLabel = "Clear Stencil Depth-Stencil State"
        clearStencilDepthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)!
        
        depthStencilDescriptor.depthCompareFunction = .equal
        depthStencilDescriptor.optLabel = "Transparent Surface Depth-Stencil State"
        transparentSurfaceDepthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)!
        
        depthStencilDescriptor.depthCompareFunction = .greater
        depthStencilDescriptor.isDepthWriteEnabled = true
        depthStencilDescriptor.optLabel = "Interface Surface Depth-Stencil State"
        surfaceDepthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)!
        
        depthStencilDescriptor.frontFaceStencil.stencilCompareFunction = .equal
        depthStencilDescriptor.depthCompareFunction = .always
        depthStencilDescriptor.isDepthWriteEnabled = false
        depthStencilDescriptor.optLabel = "Interface Text Depth-Stencil State"
        textDepthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)!
        
        depthStencilDescriptor.frontFaceStencil = nil
        depthStencilDescriptor.depthCompareFunction = .greater
        depthStencilDescriptor.isDepthWriteEnabled = true
        depthStencilDescriptor.optLabel = "Depth Pass Depth-Stencil State"
        depthPassDepthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)!
        
        
        
        Self.fontHandles = Self.createFontHandles(device: device, commandQueue: renderer.commandQueue, library: library,
                                                  configurations: [
                                                      (name: "System Font Regular", size: 144),
                                                      (name: "System Font Bold",    size: 144)
                                                  ])
    }
}
