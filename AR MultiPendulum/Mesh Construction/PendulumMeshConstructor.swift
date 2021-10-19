//
//  PendulumMeshConstructor.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/7/21.
//

import Metal
import ARHeadsetKit

final class PendulumMeshConstructor: DelegateRenderer {
    unowned let renderer: MainRenderer
    unowned let pendulumRenderer: PendulumRenderer
    var centralRenderer: CentralRenderer { renderer.centralRenderer }
    
    var numPendulums: Int { pendulumRenderer.numPendulums }
    var jointRadius: Float { pendulumRenderer.jointRadius }
    var pendulumHalfWidth: Float { pendulumRenderer.pendulumHalfWidth }
    
    var rectangleColor: simd_float3 { pendulumRenderer.pendulumColor }
    var jointColor: simd_float3 { pendulumRenderer.jointColor }
    
    var usingThreadgroups: Bool
    
    var statesToRender: [PendulumState]!
    
    struct ComputeUniforms {
        var rectangleHalfWidth: Float
        var jointRadius: Float
        var halfDepth: Float
        
        var minDistance: Float
        var minDistanceSquared: Float
        
        var doingAmplification: Bool
        var usingHeadsetMode: Bool
        
        init(pendulumRenderer: PendulumRenderer) {
            let halfWidth = pendulumRenderer.pendulumHalfWidth
            let radius    = pendulumRenderer.jointRadius
            
            rectangleHalfWidth = halfWidth
            jointRadius        = radius
            
            let depthMultiplier = simd_fast_recip(Double(pendulumRenderer.numPendulums << 1 - 1))
            halfDepth = pendulumRenderer.pendulumHalfWidth * Float(depthMultiplier)
            
            if halfWidth > radius {
                minDistance = 0
                minDistanceSquared = 0
            } else {
                minDistanceSquared = (0.9375 * 0.9375) * fma(radius, radius, -halfWidth * halfWidth)
                minDistance = sqrt(minDistanceSquared)
            }
            
            doingAmplification = pendulumRenderer.doingTwoSidedPendulums
            usingHeadsetMode   = pendulumRenderer.usingHeadsetMode
        }
    }
    
    struct VertexUniforms {
        var normalTransform: simd_half3x3
        var negativeZAxis: simd_half3
        
        var modelToWorldTransform: simd_float4x4
        var worldToModelTransform: simd_float4x4
        
        var projectionTransform: simd_float4x4
        var eyeDirectionTransform: simd_float4x4
        
        init(pendulumRenderer: PendulumRenderer) {
            let rotationTransform = simd_float3x3(pendulumRenderer.pendulumOrientation)
            normalTransform = simd_half3x3(rotationTransform)
            negativeZAxis = -normalTransform.columns.2
            
            modelToWorldTransform = .init(rotation: rotationTransform, translation: pendulumRenderer.pendulumLocation)
            worldToModelTransform = modelToWorldTransform.inverseRotationTranslation
            
            projectionTransform = pendulumRenderer.worldToScreenClipTransform * modelToWorldTransform
            eyeDirectionTransform = (-modelToWorldTransform).appendingTranslation(pendulumRenderer.handheldEyePosition)
        }
    }
    
    struct MixedRealityUniforms {
        var normalTransform: simd_half3x3
        var negativeZAxis: simd_half3
        
        var modelToWorldTransform: simd_float4x4
        var worldToModelTransform: simd_float4x4
        var cullTransform: simd_float4x4
        
        var leftProjectionTransform: simd_float4x4
        var rightProjectionTransform: simd_float4x4
        
        var leftEyeDirectionTransform: simd_float4x4
        var rightEyeDirectionTransform: simd_float4x4
        
        init(pendulumRenderer: PendulumRenderer) {
            let rotationTransform = simd_float3x3(pendulumRenderer.pendulumOrientation)
            normalTransform = simd_half3x3(rotationTransform)
            negativeZAxis = -normalTransform.columns.2
            
            modelToWorldTransform = .init(rotation: rotationTransform, translation: pendulumRenderer.pendulumLocation)
            worldToModelTransform = modelToWorldTransform.inverseRotationTranslation
            cullTransform = pendulumRenderer.worldToHeadsetModeCullTransform * modelToWorldTransform
            
            leftProjectionTransform  = pendulumRenderer.worldToLeftClipTransform  * modelToWorldTransform
            rightProjectionTransform = pendulumRenderer.worldToRightClipTransform * modelToWorldTransform
            
            leftEyeDirectionTransform  = (-modelToWorldTransform).appendingTranslation(pendulumRenderer.leftEyePosition)
            rightEyeDirectionTransform = (-modelToWorldTransform).appendingTranslation(pendulumRenderer.rightEyePosition)
        }
    }
    
    struct FragmentUniforms {
        var modelColor: simd_packed_half3
        var shininess: Float16
        
        init(modelColor: simd_float3, shininess: Float = 32) {
            self.modelColor = simd_packed_half3(modelColor)
            self.shininess = Float16(shininess)
        }
    }
    
    struct AngleRange {
        var angleStart: Float
        var angleStepSize: Float
        var startVertexID: UInt32
    }
    
    struct JointVertex {
        var edgeVertexIndex: UInt32
        var baseVertexIndex: UInt16
    }
    
    struct JointBaseVertex {
        var depthRanges: simd_half2x2
        var position: simd_float2
    }
    
    enum UniformLayer: UInt16, MTLBufferLayer {
        case worldToCameraTransform
        case cameraPosition
        case vertexUniform
        case computeUniform
        
        case jointTriangleCount
        case rectangleTriangleCount
        case rectangleLineCount
        
        case createJointMeshArguments
        case jointVertexCount
        case rectangleVertexCount
        
        case jointFragmentUniform
        case rectangleFragmentUniform
        
        case isPerimeter
        case rectangleIndex
        case jointIndex
        
        static let bufferLabel = "Pendulum Renderer Uniform Buffer"
        
        private var numRenderBuffers: Int { MainRenderer.numRenderBuffers }
        
        func getSize(capacity: Int) -> Int {
            switch self {
            case .worldToCameraTransform:   return numRenderBuffers * 2 * MemoryLayout<simd_float4x4>.stride
            case .cameraPosition:           return numRenderBuffers * 2 * MemoryLayout<simd_float3>.stride
            case .vertexUniform:            return numRenderBuffers *     MemoryLayout<MixedRealityUniforms>.stride
            case .computeUniform:           return numRenderBuffers *     MemoryLayout<ComputeUniforms>.stride
            
            case .jointTriangleCount:       return numRenderBuffers * MemoryLayout<MTLDrawIndexedPrimitivesIndirectArguments>.stride
            case .rectangleTriangleCount:   return numRenderBuffers * MemoryLayout<MTLDrawPrimitivesIndirectArguments>.stride
            case .rectangleLineCount:       return numRenderBuffers * MemoryLayout<MTLDrawIndexedPrimitivesIndirectArguments>.stride
            
            case .createJointMeshArguments: return numRenderBuffers * MemoryLayout<MTLDispatchThreadgroupsIndirectArguments>.stride
            case .jointVertexCount:         return numRenderBuffers * MemoryLayout<UInt32>.stride
            case .rectangleVertexCount:     return numRenderBuffers * MemoryLayout<UInt32>.stride
            
            case .jointFragmentUniform:     return numRenderBuffers * MemoryLayout<FragmentUniforms>.stride
            case .rectangleFragmentUniform: return numRenderBuffers * MemoryLayout<FragmentUniforms>.stride
            
            case .isPerimeter:              return  2 * max(4, MemoryLayout<Bool>.stride)
            case .rectangleIndex:           return 12 * MemoryLayout<UInt16>.stride
            case .jointIndex:               return 24 * MemoryLayout<UInt16>.stride
            }
        }
    }
    
    enum GeometryLayer: UInt16, MTLBufferLayer {
        case rectangle
        case jointOrigin
        
        case rectangleDepthRange
        case rectangleVertex
        case rectangleTriangleIndex
        case rectangleLineIndex
        
        case jointAngleRange
        case jointBaseVertex
        case jointEdgeVertex
        case jointEdgeNormal
        case jointVertex
        
        static let bufferLabel = "Pendulum Renderer Geometry Buffer"
        
        func getSize(capacity: Int) -> Int {
            switch self {
            case .rectangle:              return capacity * MainRenderer.numRenderBuffers * MemoryLayout<simd_float2x2>.stride
            case .jointOrigin:            return capacity * MainRenderer.numRenderBuffers * MemoryLayout<simd_float2>.stride
            
            case .rectangleDepthRange:    return capacity *      MemoryLayout<simd_half2x2>.stride
            case .rectangleVertex:        return capacity * 12 * MemoryLayout<simd_float2>.stride
            case .rectangleTriangleIndex: return capacity *  7 * MemoryLayout<simd_ushort4>.stride
            case .rectangleLineIndex:     return capacity *  8 * MemoryLayout<simd_ushort3>.stride
                
            case .jointAngleRange:        return capacity *   2 * MemoryLayout<AngleRange>.stride
            case .jointBaseVertex:        return capacity *   2 * MemoryLayout<JointBaseVertex>.stride
            case .jointEdgeVertex:        return capacity * 136 * MemoryLayout<simd_float2>.stride
            case .jointEdgeNormal:        return capacity * 136 * MemoryLayout<simd_half3>.stride
            case .jointVertex:            return capacity * 136 * MemoryLayout<JointVertex>.stride
            }
        }
    }
    
    var uniformBuffer: MTLLayeredBuffer<UniformLayer>
    var geometryBuffer: MTLLayeredBuffer<GeometryLayer>
    
    var worldToCameraTransformOffset: Int { renderIndex * 2 * MemoryLayout<simd_float4x4>.stride }
    var cameraPositionOffset: Int { renderIndex * 2 * MemoryLayout<simd_float3>.stride }
    var computeUniformOffset: Int { renderIndex * MemoryLayout<ComputeUniforms>.stride }
    
    var vertexUniformOffset: Int { renderIndex * MemoryLayout<MixedRealityUniforms>.stride }
    var fragmentUniformOffset: Int { renderIndex * MemoryLayout<FragmentUniforms>.stride }
    
    var createJointMeshArgumentsOffset: Int { renderIndex * MemoryLayout<MTLDispatchThreadgroupsIndirectArguments>.stride }
    var indexedIndirectArgumentsOffset: Int { renderIndex * MemoryLayout<MTLDrawIndexedPrimitivesIndirectArguments>.stride }
    var indirectArgumentsOffset: Int { renderIndex * MemoryLayout<MTLDrawPrimitivesIndirectArguments>.stride }
    
    var indexedNumInstancesOffset: Int { indexedIndirectArgumentsOffset + MemoryLayout<UInt32>.stride }
    var numInstancesOffset: Int { indirectArgumentsOffset + MemoryLayout<UInt32>.stride }
    var vertexCountOffset: Int { renderIndex * MemoryLayout<UInt32>.stride }
    
    var rectangleOffset: Int { renderIndex * geometryBuffer.capacity * MemoryLayout<simd_float2x2>.stride }
    var jointOriginOffset: Int { renderIndex * geometryBuffer.capacity * MemoryLayout<simd_float2>.stride }
    
    var makeJointMeshPipelineState: MTLComputePipelineState
    var makeRectangleMeshPipelineState: MTLComputePipelineState
    var createJointMeshVerticesPipelineState: MTLComputePipelineState
    
    var jointRenderPipelineState: ARMetalRenderPipelineState
    var rectangleRenderPipelineState: ARMetalRenderPipelineState
    
    init(pendulumRenderer: PendulumRenderer, library: MTLLibrary) {
        self.renderer = pendulumRenderer.renderer
        self.pendulumRenderer = pendulumRenderer
        let device = pendulumRenderer.device
        
        uniformBuffer  = device.makeLayeredBuffer(capacity: 1,   options: .storageModeShared)
        geometryBuffer = device.makeLayeredBuffer(capacity: 512, options: .storageModeShared)
        
        for primitiveType: UniformLayer in [.jointTriangleCount, .rectangleTriangleCount, .rectangleLineCount] {
            let primitiveCountPointer = uniformBuffer[primitiveType]
            
            func setIndirectArguments<T>(_ value: T) {
                for i in 0..<3 {
                    primitiveCountPointer.assumingMemoryBound(to: T.self)[i] = value
                }
            }
            
            if primitiveType == .rectangleTriangleCount {
                typealias RenderArguments = MTLDrawPrimitivesIndirectArguments
                let renderArguments = RenderArguments(vertexCount: 12, instanceCount: 0,
                                                      vertexStart: 0, baseInstance: 0)
                setIndirectArguments(renderArguments)
            } else {
                let indexCount: UInt32 = (primitiveType == .jointTriangleCount) ? 24 : 12
                
                typealias RenderArguments = MTLDrawIndexedPrimitivesIndirectArguments
                let renderArguments = RenderArguments(indexCount: indexCount, instanceCount: 0, indexStart: 0,
                                                      baseVertex: 0, baseInstance: 0)
                setIndirectArguments(renderArguments)
            }
        }
        
        typealias ComputeArguments = MTLDispatchThreadgroupsIndirectArguments
        let jointVertexCountPointer = uniformBuffer[.createJointMeshArguments].assumingMemoryBound(to: ComputeArguments.self)
        jointVertexCountPointer[0] = .init(threadgroupsPerGrid: (0, 1, 1))
        jointVertexCountPointer[1] = .init(threadgroupsPerGrid: (0, 1, 1))
        jointVertexCountPointer[2] = .init(threadgroupsPerGrid: (0, 1, 1))
        
        
        
        let isPerimeterPointer = uniformBuffer[.isPerimeter].assumingMemoryBound(to: Bool.self)
        isPerimeterPointer[0] = false
        isPerimeterPointer[4] = true
        
        let rectangleIndexPointer = uniformBuffer[.rectangleIndex].assumingMemoryBound(to: simd_ushort2.self)
        rectangleIndexPointer[0] = [0, 1]
        rectangleIndexPointer[1] = [2, 2]
        rectangleIndexPointer[2] = [1, 3]
        
        rectangleIndexPointer[3] = [4, 5]
        rectangleIndexPointer[4] = [6, 6]
        rectangleIndexPointer[5] = [5, 7]
        
        let jointIndexPointer = uniformBuffer[.jointIndex].assumingMemoryBound(to: simd_ushort4.self)
        jointIndexPointer[0] = [0, 1, 2, 3]
        jointIndexPointer[1] = [4, 5, 6, 7]
        jointIndexPointer[2] = [8, 8, 7, 9]

        jointIndexPointer[3] = [10, 11, 12, 13]
        jointIndexPointer[4] = [14, 15, 16, 17]
        jointIndexPointer[5] = [18, 18, 17, 19]
        
        
        
        do {
            var descriptor = ARMetalRenderPipelineDescriptor(renderer: renderer)
            descriptor.vertexFunction = library.makeARVertexFunction(rendererName: "pendulum", objectName: "Joint")
            descriptor.optLabel = "Pendulum Rectangle Joint Pipeline"
            jointRenderPipelineState = try! descriptor.makeRenderPipelineState()
            
            descriptor.vertexFunction = library.makeARVertexFunction(rendererName: "pendulum", objectName: "Rectangle")
            descriptor.optLabel = "Pendulum Rectangle Render Pipeline"
            rectangleRenderPipelineState = try! descriptor.makeRenderPipelineState()
        }
        
        
        
        usingThreadgroups = device.supportsFamily(.apple4)
        
        // Although devices in the `.apple3` GPU family support using threadgroup memory, the back-end
        // Metal compiler fails every time the optimized pendulum mesh construction shaders are loaded at runtime.
        // So, slower compute shaders that don't use threadgroup memory are used for these devices.
        
        makeJointMeshPipelineState = library.makeComputePipeline(Self.self, name: usingThreadgroups
                                                                                ? "makePendulumJointMesh"
                                                                                : "makePendulumJointMesh2")
        
        makeRectangleMeshPipelineState = library.makeComputePipeline(Self.self, name: usingThreadgroups
                                                                                    ? "makePendulumRectangleMesh"
                                                                                    : "makePendulumRectangleMesh2")
        
        createJointMeshVerticesPipelineState = library.makeComputePipeline(Self.self, name: "createPendulumJointMeshVertices")
        
    }
}
