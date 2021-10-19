//
//  SceneCuller.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 4/13/21.
//

import Metal
import simd

final class SceneCuller: DelegateSceneRenderer {
    var sceneRenderer: SceneRenderer
    
    var preCullVertexCount: Int { sceneRenderer.preCullVertexCount }
    var preCullTriangleCount: Int { sceneRenderer.preCullTriangleCount }
    var preCullVertexCountOffset: Int { sceneRenderer.preCullVertexCountOffset }
    var preCullTriangleCountOffset: Int { sceneRenderer.preCullTriangleCountOffset }
    
    var renderTriangleIDBuffer: MTLBuffer { sceneRenderer.triangleIDBuffer }
    var occlusionTriangleIDBuffer: MTLBuffer { sceneOcclusionTester.triangleIDBuffer }
    
    typealias UniformLevel = SceneRenderer.UniformLevel
    typealias VertexLevel = SceneRenderer.VertexLevel
    typealias SectorIDLevel = SceneMeshReducer.SectorIDLevel
    
    var uniformBuffer: MultiLevelBuffer<UniformLevel> { sceneRenderer.uniformBuffer }
    var vertexBuffer: MultiLevelBuffer<VertexLevel> { sceneRenderer.vertexBuffer }
    var sectorIDBuffer: MultiLevelBuffer<SectorIDLevel> { sceneMeshReducer.currentSectorIDBuffer }
    
    enum VertexDataLevel: UInt8, MultiLevelBufferLevel {
        case inclusionData
        case mark
        case inclusions8
        
        case renderOffset
        case occlusionOffset
        
        static let bufferLabel = "Scene Culler Vertex Data Buffer"
        
        func getSize(capacity: Int) -> Int {
            switch self {
            case .inclusionData:   return capacity * MemoryLayout<simd_uchar2>.stride
            case .mark:            return capacity * MemoryLayout<simd_bool2>.stride
            case .inclusions8:     return capacity >> 3 * MemoryLayout<simd_ushort2>.stride
            
            case .renderOffset:    return capacity * MemoryLayout<UInt32>.stride
            case .occlusionOffset: return capacity * MemoryLayout<UInt32>.stride
            }
        }
    }
    
    enum BridgeLevel: UInt8, MultiLevelBufferLevel {
        case triangleInclusions8
        
        case counts8
        case counts32
        case counts128
        case counts512
        case counts2048
        case counts8192
        
        case offsets8192
        case offsets2048
        case offsets512
        case offsets128
        case offsets32
        case offsets8
        
        static let bufferLabel = "Scene Culler Bridge Buffer"
        
        func getSize(capacity: Int) -> Int {
            switch self {
            case .triangleInclusions8: return capacity >> 3 * MemoryLayout<simd_ushort2>.stride
                
            case .counts8:             return capacity >>  3 * MemoryLayout<simd_uchar4>.stride
            case .counts32:            return capacity >>  5 * MemoryLayout<simd_uchar4>.stride
            case .counts128:           return capacity >>  7 * MemoryLayout<simd_uchar4>.stride
            case .counts512:           return capacity >>  9 * MemoryLayout<simd_ushort4>.stride
            case .counts2048:          return capacity >> 11 * MemoryLayout<simd_ushort4>.stride
            case .counts8192:          return capacity >> 13 * MemoryLayout<simd_ushort4>.stride
            
            case .offsets8192:         return capacity >> 13 * MemoryLayout<simd_uint4>.stride
            case .offsets2048:         return capacity >> 11 * MemoryLayout<simd_uint4>.stride
            case .offsets512:          return capacity >>  9 * MemoryLayout<simd_uint4>.stride
            case .offsets128:          return capacity >>  7 * MemoryLayout<simd_uint4>.stride
            case .offsets32:           return capacity >>  5 * MemoryLayout<simd_uint4>.stride
            case .offsets8:            return capacity >>  3 * MemoryLayout<simd_uint4>.stride
            }
        }
    }
    
    enum SmallSectorLevel: UInt8, MultiLevelBufferLevel {
        case inclusions
        
        static let bufferLabel = "Scene Culler Small Sector Inclusions buffer"
        
        func getSize(capacity: Int) -> Int {
            switch self {
            case .inclusions: return Renderer.numRenderBuffers * capacity * MemoryLayout<Bool>.stride
            }
        }
    }
    
    var vertexDataBuffer: MultiLevelBuffer<VertexDataLevel>
    var bridgeBuffer: MultiLevelBuffer<BridgeLevel>
    var smallSectorBuffer: MultiLevelBuffer<SmallSectorLevel>
    
    var smallSectorBufferOffset: Int { renderIndex * smallSectorBuffer.capacity * MemoryLayout<Bool>.stride }
    var octreeNodeCenters: [simd_float3]!
    
    var markVertexCulls_8bitPipelineState: MTLComputePipelineState
    var markVertexCulls_16bitPipelineState: MTLComputePipelineState
    var markTriangleCulls_8bitPipelineState: MTLComputePipelineState
    var markTriangleCulls_16bitPipelineState: MTLComputePipelineState
    
    var countCullMarks8PipelineState: MTLComputePipelineState
    var countCullMarks32to128PipelineState: MTLComputePipelineState
    var countCullMarks512PipelineState: MTLComputePipelineState
    var countCullMarks2048to8192PipelineState: MTLComputePipelineState
    
    var scanSceneCullsPipelineState: MTLComputePipelineState
    var markCullOffsets8192to2048PipelineState: MTLComputePipelineState
    var markCullOffsets512to32PipelineState: MTLComputePipelineState
    
    var condenseVerticesPipelineState: MTLComputePipelineState
    var condenseMRVerticesPipelineState: MTLComputePipelineState
    var condenseTrianglesPipelineState: MTLComputePipelineState
    var condenseTrianglesForColorUpdatePipelineState: MTLComputePipelineState
    
    init(sceneRenderer: SceneRenderer, library: MTLLibrary) {
        self.sceneRenderer = sceneRenderer
        let device = sceneRenderer.device
        
        let sectorCapacity = 16
        let vertexCapacity = 32768
        let triangleCapacity = 65536
        
        vertexDataBuffer  = device.makeMultiLevelBuffer(capacity: vertexCapacity)
        bridgeBuffer      = device.makeMultiLevelBuffer(capacity: triangleCapacity)
        smallSectorBuffer = device.makeMultiLevelBuffer(capacity: sectorCapacity, options: .storageModeShared)
        
        
        
        markVertexCulls_8bitPipelineState    = library.makeComputePipeline(Self.self, name: "markVertexCulls_8bit")
        markVertexCulls_16bitPipelineState   = library.makeComputePipeline(Self.self, name: "markVertexCulls_16bit")
        markTriangleCulls_8bitPipelineState  = library.makeComputePipeline(Self.self, name: "markTriangleCulls_8bit")
        markTriangleCulls_16bitPipelineState = library.makeComputePipeline(Self.self, name: "markTriangleCulls_16bit")
        
        countCullMarks8PipelineState          = library.makeComputePipeline(Self.self, name: "countCullMarks8")
        countCullMarks32to128PipelineState    = library.makeComputePipeline(Self.self, name: "countCullMarks32to128")
        countCullMarks512PipelineState        = library.makeComputePipeline(Self.self, name: "countCullMarks512")
        countCullMarks2048to8192PipelineState = library.makeComputePipeline(Self.self, name: "countCullMarks2048to8192")
        
        scanSceneCullsPipelineState            = library.makeComputePipeline(Self.self, name: "scanSceneCulls")
        markCullOffsets8192to2048PipelineState = library.makeComputePipeline(Self.self, name: "markCullOffsets8192to2048")
        markCullOffsets512to32PipelineState    = library.makeComputePipeline(Self.self, name: "markCullOffsets512to32")
        
        condenseVerticesPipelineState                = library.makeComputePipeline(Self.self, name: "condenseVertices")
        condenseMRVerticesPipelineState              = library.makeComputePipeline(Self.self, name: "condenseMRVertices")
        condenseTrianglesPipelineState               = library.makeComputePipeline(Self.self, name: "condenseTriangles")
        condenseTrianglesForColorUpdatePipelineState = library.makeComputePipeline(Self.self, name: "condenseTrianglesForColorUpdate")
    }
}

extension SceneCuller: BufferExpandable {
    
    enum BufferType {
        case sector
        case vertex
        case triangle
    }
    
    func ensureBufferCapacity(type: BufferType, capacity: Int) {
        let newCapacity = roundUpToPowerOf2(capacity)
        
        switch type {
        case .sector:   smallSectorBuffer.ensureCapacity(device: device, capacity: newCapacity)
        case .vertex:   vertexDataBuffer.ensureCapacity(device: device, capacity: newCapacity)
        case .triangle: bridgeBuffer.ensureCapacity(device: device, capacity: newCapacity)
        }
    }
    
}
