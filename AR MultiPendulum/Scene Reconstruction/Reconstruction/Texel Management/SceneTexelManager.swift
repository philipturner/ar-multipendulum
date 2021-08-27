//
//  SceneTexelManager.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 4/13/21.
//

import Metal
import simd

protocol SceneTexelManagerSlotLevelName {
    static var name: String { get }
}

protocol SceneTexelManagerColorLevelName {
    static var name: String { get }
}

final class SceneTexelManager: DelegateSceneRenderer {
    var sceneRenderer: SceneRenderer
    
    var preCullTriangleCount: Int { sceneMeshReducer.preCullTriangleCount }
    var newRasterizationComponentBuffer: MTLBuffer { sceneTexelRasterizer.rasterizationComponentBuffer }
    var oldRasterizationComponentBuffer: MTLBuffer { sceneTexelRasterizer.oldRasterizationComponentBuffer }
    var newToOldTriangleMatchesBuffer: MTLBuffer { sceneMeshMatcher.newToOldTriangleMatchesBuffer }
    
    typealias TriangleDataLevel = SceneTexelRasterizer.TriangleDataLevel
    var newTriangleDataBuffer: MultiLevelBuffer<TriangleDataLevel> { sceneTexelRasterizer.triangleDataBuffer }
    var oldTriangleDataBuffer: MultiLevelBuffer<TriangleDataLevel> { sceneTexelRasterizer.oldTriangleDataBuffer }
    
    var oldTriangleCount: Int!
    var maxSmallTriangleTextureSlotID = 1024
    var maxLargeTriangleTextureSlotID = 1024
    
    var numOldSmallTriangles = -1
    var numOldLargeTriangles = -1
    var numNewSmallTriangles = 0
    var numNewLargeTriangles = 0
    
    enum TriangleMarkLevel: UInt8, MultiLevelBufferLevel {
        case sizeMark
        case textureSlotID
        case textureOffset
        
        case tempDebugCount
        
        static let bufferLabel = "Scene Texel Manager Triangle Mark Buffer"
        
        func getSize(capacity: Int) -> Int {
            switch self {
            case .sizeMark:      return capacity >> 4 * MemoryLayout<UInt16>.stride
            case .textureSlotID: return capacity * MemoryLayout<UInt32>.stride
            case .textureOffset: return capacity * MemoryLayout<simd_ushort2>.stride
            
            case .tempDebugCount: return 16
            }
        }
    }
    
    enum BridgeLevel: UInt8, MultiLevelBufferLevel {
        case counts16
        case counts64
        case counts512
        case counts4096
        
        case offsets4096
        case offsets512
        case offsets64
        case offsets16
        
        case triangleCount
        
        static let bufferLabel = "Scene Texel Manager Bridge Buffer"
        
        func getSize(capacity: Int) -> Int {
            switch self {
            case .counts16:      return capacity >> 4 * MemoryLayout<simd_uchar4>.stride
            case .counts64:      return capacity >> 6 * MemoryLayout<simd_uchar4>.stride
            case .counts512:     return capacity >> 9 * MemoryLayout<simd_ushort4>.stride
            case .counts4096:    return capacity >> 12 * MemoryLayout<simd_ushort4>.stride
            
            case .offsets4096:   return capacity >> 12 * MemoryLayout<simd_uint2>.stride
            case .offsets512:    return capacity >> 9 * MemoryLayout<simd_ushort2>.stride
            case .offsets64:     return capacity >> 6 * MemoryLayout<simd_ushort2>.stride
            case .offsets16:     return capacity >> 4 * MemoryLayout<simd_ushort2>.stride
            
            case .triangleCount: return MemoryLayout<UInt32>.stride
            }
        }
    }
    
    enum SmallSlotName: SceneTexelManagerSlotLevelName { static let name = "Small Triangle Texture Slot" }
    enum LargeSlotName: SceneTexelManagerSlotLevelName { static let name = "Large Triangle Texture Slot" }
    
    typealias SmallSlotLevel = SlotLevel<SmallSlotName>
    typealias LargeSlotLevel = SlotLevel<LargeSlotName>
    
    enum SlotLevel<Name: SceneTexelManagerSlotLevelName>: UInt8, MultiLevelBufferLevel {
        case slot
        case openSlotID
        case totalNumOpenSlots
        
        static var bufferLabel: String { "Scene Texel Manager \(Name.name) Buffer" }
        
        func getSize(capacity: Int) -> Int {
            switch self {
            case .slot:              return capacity * MemoryLayout<Bool>.stride
            case .openSlotID:        return capacity * MemoryLayout<UInt32>.stride
            case .totalNumOpenSlots: return MemoryLayout<UInt32>.stride
            }
        }
    }
    
    enum SmallColorName: SceneTexelManagerColorLevelName { static let name = "Small Triangle Color" }
    enum LargeColorName: SceneTexelManagerColorLevelName { static let name = "Small Triangle Color" }
    
    typealias SmallColorLevel = ColorLevel<SmallColorName>
    typealias LargeColorLevel = ColorLevel<LargeColorName>
    
    enum ColorLevel<Name: SceneTexelManagerColorLevelName>: UInt8, MultiLevelBufferLevel {
        case luma
        case chroma
        
        static var bufferLabel: String { "Scene Texel Manager \(Name.name) Backing Buffer" }
        
        func getSize(capacity numLumaRows: Int) -> Int {
            switch self {
            case .luma:   return numLumaRows *  16384      * MemoryLayout<UInt8>.stride
            case .chroma: return numLumaRows * (8192 >> 1) * MemoryLayout<simd_uchar2>.stride
            }
        }
    }
    
    enum RowHeightLevel: UInt8, MultiLevelBufferLevel {
        case mark
        case reducedSize
        
        static let bufferLabel = "Scene Texel Manager Color Copying Row Height Buffer"
        
        func getSize(capacity: Int) -> Int {
            switch self {
            case .mark:        return capacity * 8 * MemoryLayout<UInt32>.stride
            case .reducedSize: return capacity * MemoryLayout<UInt8>.stride
            }
        }
    }
    
    var triangleMarkBuffer: MultiLevelBuffer<TriangleMarkLevel>
    var oldTriangleMarkBuffer: MultiLevelBuffer<TriangleMarkLevel>
    var bridgeBuffer: MultiLevelBuffer<BridgeLevel>
    
    var smallTriangleSlotBuffer: MultiLevelBuffer<SmallSlotLevel>
    var largeTriangleSlotBuffer: MultiLevelBuffer<LargeSlotLevel>
    
    var smallTriangleColorBuffer: MultiLevelBuffer<SmallColorLevel>
    var largeTriangleColorBuffer: MultiLevelBuffer<LargeColorLevel>
    var colorCopyingRowHeightBuffer: MultiLevelBuffer<RowHeightLevel>
    
    var smallTriangleLumaTexture: MTLTexture
    var largeTriangleLumaTexture: MTLTexture
    var smallTriangleChromaTexture: MTLTexture
    var largeTriangleChromaTexture: MTLTexture
    
    var countTriangleSizes16PipelineState: MTLComputePipelineState
    var countTriangleSizes64PipelineState: MTLComputePipelineState
    var countTriangleSizes512PipelineState: MTLComputePipelineState
    var scanTriangleSizes4096PipelineState: MTLComputePipelineState
    
    var markTriangleSizeOffsets512PipelineState: MTLComputePipelineState
    var markTriangleSizeOffsets64PipelineState: MTLComputePipelineState
    var markTriangleSizeOffsets16PipelineState: MTLComputePipelineState
    
    var clearTriangleTextureSlotsPipelineState: MTLComputePipelineState
    var markTriangleTextureSlotsPipelineState: MTLComputePipelineState
    var findOpenTriangleTextureSlotsPipelineState: MTLComputePipelineState
    
    var markColorCopyingRowSizesPipelineState: MTLComputePipelineState
    var reduceColorCopyingRowSizesPipelineState: MTLComputePipelineState
    var transferColorDataToTexturePipelineState: MTLComputePipelineState
    
    init(sceneRenderer: SceneRenderer, library: MTLLibrary) {
        self.sceneRenderer = sceneRenderer
        let device = sceneRenderer.device
        
        let triangleCapacity      = 65536
        let smallTriangleCapacity = 32768
        let largeTriangleCapacity = 16384
        
        triangleMarkBuffer    = device.makeMultiLevelBuffer(capacity: triangleCapacity)
        oldTriangleMarkBuffer = device.makeMultiLevelBuffer(capacity: triangleCapacity)
        bridgeBuffer          = device.makeMultiLevelBuffer(capacity: triangleCapacity, options: .storageModeShared)
        
        smallTriangleSlotBuffer = device.makeMultiLevelBuffer(capacity: smallTriangleCapacity, options: .storageModeShared)
        largeTriangleSlotBuffer = device.makeMultiLevelBuffer(capacity: largeTriangleCapacity, options: .storageModeShared)
        
        let smallTriangleLumaTextureHeight = smallTriangleCapacity >> 6 - smallTriangleCapacity >> 9
        let largeTriangleLumaTextureHeight = largeTriangleCapacity >> 4 - largeTriangleCapacity >> 7
        smallTriangleColorBuffer = device.makeMultiLevelBuffer(capacity: smallTriangleLumaTextureHeight)
        largeTriangleColorBuffer = device.makeMultiLevelBuffer(capacity: largeTriangleLumaTextureHeight)
        
        colorCopyingRowHeightBuffer = device.makeMultiLevelBuffer(capacity: 16384 / 14, options: .storageModeShared)
        
        
        
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.usage = [.shaderWrite, .shaderRead]
        textureDescriptor.storageMode = .private
        
        textureDescriptor.width = 16384
        textureDescriptor.pixelFormat = .r8Unorm
        
        textureDescriptor.height = smallTriangleLumaTextureHeight
        smallTriangleLumaTexture = smallTriangleColorBuffer.makeTexture(descriptor: textureDescriptor, level: .luma,
                                                                        bytesPerRow: 16384 * MemoryLayout<UInt8>.stride)
        smallTriangleLumaTexture.optLabel = "Scene Small Triangle Luma Texture"
        
        textureDescriptor.height = largeTriangleLumaTextureHeight
        largeTriangleLumaTexture = largeTriangleColorBuffer.makeTexture(descriptor: textureDescriptor, level: .luma,
                                                                        bytesPerRow: 16384 * MemoryLayout<UInt8>.stride)
        largeTriangleLumaTexture.optLabel = "Scene Large Triangle Luma Texture"
        
        textureDescriptor.width = 8192
        textureDescriptor.pixelFormat = .rg8Unorm
        
        textureDescriptor.height = smallTriangleLumaTextureHeight >> 1
        smallTriangleChromaTexture = smallTriangleColorBuffer.makeTexture(descriptor: textureDescriptor, level: .chroma,
                                                                          bytesPerRow: 8192 * MemoryLayout<simd_uchar2>.stride)
        smallTriangleChromaTexture.optLabel = "Scene Small Triangle Chroma Texture"
        
        textureDescriptor.height = largeTriangleLumaTextureHeight >> 1
        largeTriangleChromaTexture = largeTriangleColorBuffer.makeTexture(descriptor: textureDescriptor, level: .chroma,
                                                                          bytesPerRow: 8192 * MemoryLayout<simd_uchar2>.stride)
        largeTriangleChromaTexture.optLabel = "Scene Large Triangle Chroma Texture"
        
        
        
        countTriangleSizes16PipelineState  = library.makeComputePipeline(Self.self, name: "countTriangleSizes16")
        countTriangleSizes64PipelineState  = library.makeComputePipeline(Self.self, name: "countTriangleSizes64")
        countTriangleSizes512PipelineState = library.makeComputePipeline(Self.self, name: "countTriangleSizes512")
        scanTriangleSizes4096PipelineState = library.makeComputePipeline(Self.self, name: "scanTriangleSizes4096")
        
        markTriangleSizeOffsets512PipelineState = library.makeComputePipeline(Self.self, name: "markTriangleSizeOffsets512")
        markTriangleSizeOffsets64PipelineState  = library.makeComputePipeline(Self.self, name: "markTriangleSizeOffsets64")
        markTriangleSizeOffsets16PipelineState  = library.makeComputePipeline(Self.self, name: "markTriangleSizeOffsets16")
        
        let computePipelineDescriptor = MTLComputePipelineDescriptor()
        computePipelineDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = true
        
        computePipelineDescriptor.computeFunction = library.makeFunction(name: "clearTriangleTextureSlots")!
        clearTriangleTextureSlotsPipelineState = device.makeComputePipelineState(descriptor: computePipelineDescriptor)
        markTriangleTextureSlotsPipelineState = library.makeComputePipeline(Self.self, name: "markTriangleTextureSlots")
        
        computePipelineDescriptor.computeFunction = library.makeFunction(name: "findOpenTriangleTextureSlots")!
        findOpenTriangleTextureSlotsPipelineState = device.makeComputePipelineState(descriptor: computePipelineDescriptor)
        
        markColorCopyingRowSizesPipelineState   = library.makeComputePipeline(Self.self, name: "markColorCopyingRowSizes")
        reduceColorCopyingRowSizesPipelineState = library.makeComputePipeline(Self.self, name: "reduceColorCopyingRowSizes")
        transferColorDataToTexturePipelineState = library.makeComputePipeline(Self.self, name: "transferColorDataToTexture")
    }
}
