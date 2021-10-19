//
//  CentralRenderer.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 4/17/21.
//

import Metal
import simd

protocol CentralVertexUniforms {
    init(centralRenderer: CentralRenderer, alias: CentralObject.Alias)
}

final class CentralRenderer: DelegateRenderer {
    var renderer: Renderer
    
    var didSetRenderPipeline: simd_long2 = .zero
    var didSetGlobalFragmentUniforms: simd_long2 = .zero
    var currentlyCulling: simd_long2 = .zero
    
    var cullTransform = simd_float4x4(1)
    var lodTransform = simd_float4x4(1)
    var lodTransformInverse = simd_float4x4(1)
    
    var lodTransform2 = simd_float4x4(1)
    var lodTransformInverse2 = simd_float4x4(1)
    
    private var circles: [UInt16 : [simd_float2]] = [:]
    func circle(numSegments: UInt16) -> [simd_float2] {
        if let circleVertices = circles[numSegments] {
            return circleVertices
        } else {
            let multiplier = 2 / Float(numSegments)
            
            let circleVertices = (0..<numSegments).map {
                __sincospif_stret(Float($0) * multiplier).sinCosVector * 0.5
            }
            
            circles[numSegments] = circleVertices
            
            return circleVertices
        }
    }
    
    struct VertexUniforms: CentralVertexUniforms {
        var projectionTransform: simd_float4x4
        var eyeDirectionTransform: simd_float4x4
        
        var normalTransform: simd_half3x3
        var truncatedConeTopScale: Float
        var truncatedConeNormalMultipliers: simd_half2
        
        init(centralRenderer: CentralRenderer, alias: CentralObject.Alias) {
            projectionTransform = centralRenderer.worldToScreenClipTransform * alias.modelToWorldTransform
            eyeDirectionTransform = (-alias.modelToWorldTransform).appendingTranslation(centralRenderer.handheldEyePosition)
            
            normalTransform = alias.normalTransform
            truncatedConeTopScale = alias.truncatedConeTopScale
            truncatedConeNormalMultipliers = alias.truncatedConeNormalMultipliers
        }
    }
    
    struct MixedRealityUniforms: CentralVertexUniforms {
        var leftProjectionTransform: simd_float4x4
        var rightProjectionTransform: simd_float4x4
        
        var leftEyeDirectionTransform: simd_float4x4
        var rightEyeDirectionTransform: simd_float4x4
        
        var normalTransform: simd_half3x3
        var truncatedConeTopScale: Float
        var truncatedConeNormalMultipliers: simd_half2
        
        init(centralRenderer: CentralRenderer, alias: CentralObject.Alias) {
            leftProjectionTransform  = centralRenderer.worldToLeftClipTransform  * alias.modelToWorldTransform
            rightProjectionTransform = centralRenderer.worldToRightClipTransform * alias.modelToWorldTransform
            
            leftEyeDirectionTransform  = (-alias.modelToWorldTransform).appendingTranslation(centralRenderer.leftEyePosition)
            rightEyeDirectionTransform = (-alias.modelToWorldTransform).appendingTranslation(centralRenderer.rightEyePosition)
            
            normalTransform = alias.normalTransform
            truncatedConeTopScale = alias.truncatedConeTopScale
            truncatedConeNormalMultipliers = alias.truncatedConeNormalMultipliers
        }
    }
    
    struct GlobalFragmentUniforms {
        var ambientLightColor: simd_half3
        var ambientInsideLightColor: simd_half3
        
        var directionalLightColor: simd_half3
        var lightDirection: simd_half3
        
        init(centralRenderer: CentralRenderer) {
            let retrievedAmbientLightColor = centralRenderer.ambientLightColor
            ambientLightColor = retrievedAmbientLightColor
            ambientInsideLightColor = retrievedAmbientLightColor * 0.5
            
            directionalLightColor = centralRenderer.directionalLightColor
            lightDirection = centralRenderer.lightDirection
        }
    }
    
    struct FragmentUniforms {
        var modelColor: simd_packed_half3
        var shininess: Float16
        
        init(alias: CentralObject.Alias) {
            modelColor = alias.color
            shininess = alias.shininess
        }
    }
    
    var shapeContainers: [CentralShapeContainer]
    
    var globalFragmentUniformBuffer: MTLBuffer
    var globalFragmentUniformOffset: Int { renderIndex * MemoryLayout<GlobalFragmentUniforms>.stride }
    
    var renderPipelineState: MTLRenderPipelineState
    var coneRenderPipelineState: MTLRenderPipelineState
    var cylinderRenderPipelineState: MTLRenderPipelineState
    
    var mixedRealityRenderPipelineState: MTLRenderPipelineState
    var mixedRealityConeRenderPipelineState: MTLRenderPipelineState
    var mixedRealityCylinderRenderPipelineState: MTLRenderPipelineState
    
    init(renderer: Renderer, library: MTLLibrary) {
        self.renderer = renderer
        let device = renderer.device
        
        let globalFragmentUniformBufferSize = Renderer.numRenderBuffers * MemoryLayout<GlobalFragmentUniforms>.stride
        globalFragmentUniformBuffer = device.makeBuffer(length: globalFragmentUniformBufferSize, options: .storageModeShared)!
        globalFragmentUniformBuffer.optLabel = "Central Global Fragment Uniform Buffer"
        
        
        
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.sampleCount = 4
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = renderer.msaaTexture.pixelFormat
        renderPipelineDescriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
        renderPipelineDescriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
        renderPipelineDescriptor.inputPrimitiveTopology = .triangle
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.layouts[0].stride = MemoryLayout<simd_float3>.stride
        vertexDescriptor.layouts[1].stride = MemoryLayout<simd_half3>.stride
        
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .half3
        vertexDescriptor.attributes[1].offset = 0
        vertexDescriptor.attributes[1].bufferIndex = 1
        
        vertexDescriptor.attributes[2].format = .ushort
        vertexDescriptor.attributes[2].offset = 6
        vertexDescriptor.attributes[2].bufferIndex = 1
        
        renderPipelineDescriptor.vertexDescriptor = vertexDescriptor
        renderPipelineDescriptor.fragmentFunction = library.makeFunction(name: "centralFragmentShader")!
        
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: "centralVertexTransform")!
        renderPipelineDescriptor.optLabel = "Central Render Pipeline"
        renderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: "centralConeVertexTransform")!
        renderPipelineDescriptor.optLabel = "Central Cone Render Pipeline"
        coneRenderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: "centralCylinderVertexTransform")!
        renderPipelineDescriptor.optLabel = "Central Cylinder Render Pipeline"
        cylinderRenderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        
        
        
        if renderer.usingVertexAmplification { renderPipelineDescriptor.maxVertexAmplificationCount = 2 }
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = .rg11b10Float
        
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: renderer.usingVertexAmplification
                                                                           ? "centralMRVertexTransform"
                                                                           : "centralMRVertexTransform2")!
        renderPipelineDescriptor.optLabel = "Central Mixed Reality Render Pipeline"
        mixedRealityRenderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: renderer.usingVertexAmplification
                                                                           ? "centralMRConeVertexTransform"
                                                                           : "centralMRConeVertexTransform2")!
        renderPipelineDescriptor.optLabel = "Central Mixed Reality Cone Render Pipeline"
        mixedRealityConeRenderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: renderer.usingVertexAmplification
                                                                           ? "centralMRCylinderVertexTransform"
                                                                           : "centralMRCylinderVertexTransform2")!
        renderPipelineDescriptor.optLabel = "Central Mixed Reality Cylinder Render Pipeline"
        mixedRealityCylinderRenderPipelineState = try! device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        
        
        
        shapeContainers = Array(capacity: 6)
        
        shapeContainers.append(ShapeContainer<CentralCube>         (centralRenderer: self))
        shapeContainers.append(ShapeContainer<CentralSquarePyramid>(centralRenderer: self))
        shapeContainers.append(ShapeContainer<CentralOctahedron>   (centralRenderer: self))
        
        var shapeSizes = (3...11).map {
            Int(round(exp2(Float($0) * 0.5)))
        }
        
        shapeContainers.append(ShapeContainer<CentralSphere>(centralRenderer: self, range: shapeSizes))
        
        shapeSizes += (12...14).map {
            Int(round(exp2(Float($0) * 0.5)))
        }
        
        shapeContainers.append(ShapeContainer<CentralCone>    (centralRenderer: self, range: shapeSizes))
        shapeContainers.append(ShapeContainer<CentralCylinder>(centralRenderer: self, range: shapeSizes))
        
        circles = [:]
    }
}
