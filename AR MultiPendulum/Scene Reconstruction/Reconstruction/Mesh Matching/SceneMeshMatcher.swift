//
//  SceneMeshMatcher.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 4/13/21.
//

import Metal
import simd

final class SceneMeshMatcher: DelegateSceneRenderer {
    var sceneRenderer: SceneRenderer
    var octreeAsArray: [OctreeNode.ArrayElement] { sceneSorter.octreeAsArray }
    var thirdSceneSorter: ThirdSceneSorter { sceneSorter.thirdSceneSorter }
    var fourthSceneSorter: FourthSceneSorter { sceneSorter.fourthSceneSorter }
    
    var preCullVertexCount: Int { sceneMeshReducer.preCullVertexCount }
    var preCullTriangleCount: Int { sceneMeshReducer.preCullTriangleCount }
    var numMicroSectors: Int { fourthSceneSorter.numMicroSectors }
    
    var oldReducedVertexBuffer: MTLBuffer! { sceneMeshReducer.currentReducedVertexBuffer }
    var oldReducedIndexBuffer: MTLBuffer! { sceneMeshReducer.currentReducedIndexBuffer }
    var oldReducedColorBuffer: MTLBuffer! { sceneMeshReducer.currentReducedColorBuffer }
    
    var newReducedVertexBuffer: MTLBuffer { sceneMeshReducer.pendingReducedVertexBuffer }
    var newReducedIndexBuffer: MTLBuffer { sceneMeshReducer.pendingReducedIndexBuffer }
    var newReducedColorBuffer: MTLBuffer { sceneMeshReducer.pendingReducedColorBuffer }
    
    var newRasterizationComponentBuffer: MTLBuffer { sceneTexelRasterizer.rasterizationComponentBuffer }
    var oldRasterizationComponentBuffer: MTLBuffer!
    var oldTransientSectorIDBuffer: MTLBuffer { sceneMeshReducer.transientSectorIDBuffer }
    
    typealias ThirdSorterMicroSectorLevel = ThirdSceneSorter.MicroSectorLevel
    typealias ThirdSorterVertexDataLevel = ThirdSceneSorter.VertexDataLevel
    typealias SourceVertexDataLevel = SceneDuplicateRemover.VertexDataLevel
    
    var sceneRendererUniformBuffer: MultiLevelBuffer<SceneRenderer.UniformLevel> { sceneRenderer.uniformBuffer }
    var thirdSorterMicroSectorBuffer: MultiLevelBuffer<ThirdSorterMicroSectorLevel> { thirdSceneSorter.microSectorBuffer }
    var sourceVertexDataBuffer: MultiLevelBuffer<SourceVertexDataLevel> { sceneDuplicateRemover.vertexDataBuffer }
    var nanoSectorColorAlias: MultiLevelBuffer<ThirdSorterVertexDataLevel> {
        get { thirdSceneSorter.vertexDataBuffer }
        set { thirdSceneSorter.vertexDataBuffer = newValue }
    }
    
    var hashToMappingsArray: [(UInt32, UInt16)]!
    var oldTriangleCount: Int!
    var shouldDoMatch = false
    var doingThirdMatch = false
    
    typealias MicroSector512thLevel = ThirdSceneSorter.MicroSector512thLevel
    typealias NanoSector512thLevel = FourthSceneSorter.NanoSector512thLevel
    typealias VertexMapLevel = SceneDuplicateRemover.VertexMapLevel
    
    var oldMicroSector512thBuffer: MultiLevelBuffer<MicroSector512thLevel>!
    var oldNanoSector512thBuffer: MultiLevelBuffer<NanoSector512thLevel>!
    var oldVertexMapBuffer: MultiLevelBuffer<VertexMapLevel>!
    var oldComparisonIDBuffer: MTLBuffer!
    
    enum SmallSectorLevel: UInt8, MultiLevelBufferLevel {
        case mark
        case hashes
        case mappings
        case sortedHashes
        case sortedHashMappings
        
        case numSectorsMinus1
        case preCullVertexCount
        case using8bitSmallSectorIDs
        case shouldDoThirdMatch
        
        static let bufferLabel = "Scene Mesh Matcher Small Sector Buffer"
        
        func getSize(capacity: Int) -> Int {
            switch self {
            case .mark:                    return capacity * MemoryLayout<UInt32>.stride
            case .hashes:                  return capacity * MemoryLayout<UInt32>.stride
            case .mappings:                return capacity * MemoryLayout<UInt16>.stride
            case .sortedHashes:            return capacity * MemoryLayout<UInt32>.stride
            case .sortedHashMappings:      return capacity * MemoryLayout<UInt16>.stride
            
            case .numSectorsMinus1:        return max(4, MemoryLayout<UInt16>.stride)
            case .preCullVertexCount:      return        MemoryLayout<UInt32>.stride
            case .using8bitSmallSectorIDs: return max(4, MemoryLayout<Bool>.stride)
            case .shouldDoThirdMatch:      return        MemoryLayout<Bool>.stride
            
            }
        }
    }
    
    enum MicroSectorLevel: UInt8, MultiLevelBufferLevel {
        case microSectorMark
        case subMicroSectorMark
        static let superNanoSectorMark: Self = .nanoSectorMark
        case nanoSectorMark
        
        case microSectorColor
        case subMicroSectorColor
        
        case counts4th
        case countsIndividual
        case counts4
        case counts16
        case counts64
        
        case offsets64
        case offsets16
        case offsets4
        case offsetsIndividual
        case offsets4th
        case offsets16th
        case offsets512th
        
        static let bufferLabel = "Scene Mesh Matcher Old Micro Sector Buffer"
        
        func getSize(capacity: Int) -> Int {
            switch self {
            case .microSectorMark:     return capacity      * MemoryLayout<UInt8>.stride
            case .subMicroSectorMark:  return capacity      * MemoryLayout<UInt8>.stride
            case .nanoSectorMark:      return capacity << 4 * MemoryLayout<UInt32>.stride
                
            case .microSectorColor:    return capacity      * MemoryLayout<simd_half4>.stride
            case .subMicroSectorColor: return capacity << 3 * MemoryLayout<simd_half4>.stride
                
            case .counts4th:           return capacity << 2 * MemoryLayout<UInt8>.stride
            case .countsIndividual:    return capacity      * MemoryLayout<UInt16>.stride
            case .counts4:             return capacity >> 2 * MemoryLayout<UInt16>.stride
            case .counts16:            return capacity >> 4 * MemoryLayout<UInt16>.stride
            case .counts64:            return capacity >> 6 * MemoryLayout<UInt16>.stride
                
            case .offsets64:           return capacity >> 6 * MemoryLayout<UInt32>.stride
            case .offsets16:           return capacity >> 4 * MemoryLayout<UInt16>.stride
            case .offsets4:            return capacity >> 2 * MemoryLayout<UInt16>.stride
            case .offsetsIndividual:   return capacity      * MemoryLayout<UInt16>.stride
            case .offsets4th:          return capacity << 2 * MemoryLayout<UInt16>.stride
            case .offsets16th:         return capacity << 4 * MemoryLayout<UInt8>.stride
            case .offsets512th:        return capacity << 9 * MemoryLayout<UInt16>.stride
            }
        }
    }
    
    enum VertexMatchLevel: UInt8, MultiLevelBufferLevel {
        case newToOldMatches
        
        case count
        case counts16
        case counts64
        case counts512
        case counts4096
        
        case offsets4096
        case offsets512
        case offsets64
        case offsets16
        case offset
        
        static let bufferLabel = "Scene Mesh Matcher Vertex Match Buffer"
        
        func getSize(capacity: Int) -> Int {
            switch self {
            case .newToOldMatches: return capacity * MemoryLayout<UInt32>.stride
            
            case .count:           return capacity >>  1 * MemoryLayout<UInt8>.stride
            case .counts16:        return capacity >>  4 * MemoryLayout<UInt8>.stride
            case .counts64:        return capacity >>  6 * MemoryLayout<UInt16>.stride
            case .counts512:       return capacity >>  9 * MemoryLayout<UInt16>.stride
            case .counts4096:      return capacity >> 12 * MemoryLayout<UInt16>.stride
            
            case .offsets4096:     return capacity >> 12 * MemoryLayout<UInt32>.stride
            case .offsets512:      return capacity >>  9 * MemoryLayout<UInt16>.stride
            case .offsets64:       return capacity >>  6 * MemoryLayout<UInt16>.stride
            case .offsets16:       return capacity >>  4 * MemoryLayout<UInt16>.stride
            case .offset:          return capacity       * MemoryLayout<UInt8>.stride
            }
        }
    }
    
    var oldSmallSectorBuffer: MultiLevelBuffer<SmallSectorLevel>
    var newSmallSectorBuffer: MultiLevelBuffer<SmallSectorLevel>
    var oldMicroSectorBuffer: MultiLevelBuffer<MicroSectorLevel>
    var vertexMatchBuffer: MultiLevelBuffer<VertexMatchLevel>
    
    var newToOldVertexMatchesBuffer: MTLBuffer
    var newToOldMatchWindingBuffer: MTLBuffer
    var newToOldTriangleMatchesBuffer: MTLBuffer
    
    // First match
    
    var mapMeshSmallSectorsPipelineState: MTLComputePipelineState
    var matchMeshVerticesPipelineState: MTLComputePipelineState
    
    var countMatchedVertices64PipelineState: MTLComputePipelineState
    var countMatchedVertices512PipelineState: MTLComputePipelineState
    var markMatchedVertexOffsets512PipelineState: MTLComputePipelineState
    
    var writeMatchedMeshVerticesPipelineState: MTLComputePipelineState
    var matchMeshTrianglesPipelineState: MTLComputePipelineState
    
    // Second match
    
    var prepareSecondMeshMatchPipelineState: MTLComputePipelineState
    var countNanoSectors4thForMatchPipelineState: MTLComputePipelineState
    var countNanoSectors1ForMatchPipelineState: MTLComputePipelineState
    var countNanoSectors4to16ForMatchPipelineState: MTLComputePipelineState
    var scanNanoSectors64ForMatchPipelineState: MTLComputePipelineState
    
    var markNanoSector16to4OffsetsForMatchPipelineState: MTLComputePipelineState
    var markNanoSector1OffsetsForMatchPipelineState: MTLComputePipelineState
    var markNanoSector16thOffsetsForMatchPipelineState: MTLComputePipelineState
    var clearNanoSectorColorsPipelineState: MTLComputePipelineState
    var markNanoSectorColorsPipelineState: MTLComputePipelineState
    
    var divideNanoSectorColorsPipelineState: MTLComputePipelineState
    var doSecondMeshMatchPipelineState: MTLComputePipelineState
    
    // Third match
    
    var prepareThirdMeshMatchPipelineState: MTLComputePipelineState
    var markMicroSectorColorsPipelineState: MTLComputePipelineState
    var doThirdMeshMatchPipelineState: MTLComputePipelineState
    
    init(sceneRenderer: SceneRenderer, library: MTLLibrary) {
        self.sceneRenderer = sceneRenderer
        let device = sceneRenderer.device
        
        let smallSectorCapacity = 16
        let microSectorCapacity = 512
        
        let vertexCapacity = 32768
        let triangleCapacity = 65536
        
        oldSmallSectorBuffer = device.makeMultiLevelBuffer(capacity: smallSectorCapacity, options: .storageModeShared)
        newSmallSectorBuffer = device.makeMultiLevelBuffer(capacity: smallSectorCapacity, options: .storageModeShared)
        oldMicroSectorBuffer = device.makeMultiLevelBuffer(capacity: microSectorCapacity, options: .storageModeShared)
        
        vertexMatchBuffer = device.makeMultiLevelBuffer(capacity: vertexCapacity, options: .storageModeShared)
        
        
        
        let newToOldVertexMatchesBufferSize = vertexCapacity * MemoryLayout<UInt32>.stride
        newToOldVertexMatchesBuffer = device.makeBuffer(length: newToOldVertexMatchesBufferSize, options: .storageModePrivate)!
        newToOldVertexMatchesBuffer.optLabel = "Scene Mesh Reduced New To Old Vertex Matches Buffer"
        
        let newToOldMatchWindingBufferSize = triangleCapacity * MemoryLayout<UInt8>.stride
        newToOldMatchWindingBuffer = device.makeBuffer(length: newToOldMatchWindingBufferSize, options: .storageModePrivate)!
        newToOldMatchWindingBuffer.optLabel = "Scene Mesh Matcher New To Old Match Winding Buffer"
        
        let newToOldTriangleMatchesBufferSize = triangleCapacity * MemoryLayout<UInt32>.stride
        newToOldTriangleMatchesBuffer = device.makeBuffer(length: newToOldTriangleMatchesBufferSize, options: .storageModeShared)!
        newToOldTriangleMatchesBuffer.optLabel = "Scene Mesh Matcher New To Old Triangle Matches Buffer"
        
        
        
        mapMeshSmallSectorsPipelineState = library.makeComputePipeline(Self.self, name: "mapMeshSmallSectors")
        matchMeshVerticesPipelineState   = library.makeComputePipeline(Self.self, name: "matchMeshVertices")
        
        countMatchedVertices64PipelineState      = library.makeComputePipeline(Self.self, name: "countMatchedVertices64")
        countMatchedVertices512PipelineState     = library.makeComputePipeline(Self.self, name: "countMatchedVertices512")
        markMatchedVertexOffsets512PipelineState = library.makeComputePipeline(Self.self, name: "markMatchedVertexOffsets512")
        
        writeMatchedMeshVerticesPipelineState = library.makeComputePipeline(Self.self, name: "writeMatchedMeshVertices")
        matchMeshTrianglesPipelineState       = library.makeComputePipeline(Self.self, name: "matchMeshTriangles")
        
        
        
        prepareSecondMeshMatchPipelineState        = library.makeComputePipeline(Self.self, name: "prepareSecondMeshMatch")
        countNanoSectors4thForMatchPipelineState   = library.makeComputePipeline(Self.self, name: "countNanoSectors4thForMatch")
        countNanoSectors1ForMatchPipelineState     = library.makeComputePipeline(Self.self, name: "countNanoSectors1ForMatch")
        countNanoSectors4to16ForMatchPipelineState = library.makeComputePipeline(Self.self, name: "countNanoSectors4to16ForMatch")
        scanNanoSectors64ForMatchPipelineState     = library.makeComputePipeline(Self.self, name: "scanNanoSectors64ForMatch")
        
        markNanoSector16to4OffsetsForMatchPipelineState = library.makeComputePipeline(Self.self, name: "markNanoSector16to4OffsetsForMatch")
        markNanoSector1OffsetsForMatchPipelineState     = library.makeComputePipeline(Self.self, name: "markNanoSector1OffsetsForMatch")
        markNanoSector16thOffsetsForMatchPipelineState  = library.makeComputePipeline(Self.self, name: "markNanoSector16thOffsetsForMatch")
        clearNanoSectorColorsPipelineState              = library.makeComputePipeline(Self.self, name: "clearNanoSectorColors")
        markNanoSectorColorsPipelineState               = library.makeComputePipeline(Self.self, name: "markNanoSectorColors")
        
        divideNanoSectorColorsPipelineState = library.makeComputePipeline(Self.self, name: "divideNanoSectorColors")
        doSecondMeshMatchPipelineState      = library.makeComputePipeline(Self.self, name: "doSecondMeshMatch")
        
        
        
        prepareThirdMeshMatchPipelineState = library.makeComputePipeline(Self.self, name: "prepareThirdMeshMatch")
        markMicroSectorColorsPipelineState = library.makeComputePipeline(Self.self, name: "markMicroSectorColors")
        doThirdMeshMatchPipelineState      = library.makeComputePipeline(Self.self, name: "doThirdMeshMatch")
    }
    
}
