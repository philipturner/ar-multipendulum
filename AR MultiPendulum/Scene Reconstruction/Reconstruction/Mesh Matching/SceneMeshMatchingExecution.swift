//
//  SceneMeshMatchingExecution.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 4/13/21.
//

import Metal
import simd

extension SceneMeshMatcher {
    
    func matchMeshes() {
        prepareForMeshMatch()
        sceneTexelRasterizer.ensureBufferCapacity(type: .triangle, capacity: preCullTriangleCount)
        
        let commandBuffer1 = renderer.commandQueue.makeDebugCommandBuffer()
        
        guard shouldDoMatch else {
            commandBuffer1.optLabel = "First Scene Mesh Match Command Buffer"
            
            let blitEncoder = commandBuffer1.makeBlitCommandEncoder()!
            blitEncoder.optLabel = "First Scene Mesh Match - Clear Reduced Color Buffer"
            
            let fillSize = preCullTriangleCount * MemoryLayout<UInt32>.stride
            blitEncoder.fill(buffer: newReducedColorBuffer,         range: 0..<fillSize, value: 0)
            blitEncoder.fill(buffer: newToOldTriangleMatchesBuffer, range: 0..<fillSize, value: 255)
            blitEncoder.endEncoding()
            
            commandBuffer1.commit()
            initializeOldBuffers()
            
            return
        }
        
        commandBuffer1.optLabel = "First Scene Mesh Match Command Buffer 1"
            
        let blitEncoder = commandBuffer1.makeBlitCommandEncoder()!
        blitEncoder.optLabel = "First Scene Mesh Match - Clear Vertex Match Counts 16 Buffer"
        
        let numVertex16Groups   = (preCullVertexCount + 15) >> 4
        let numVertex4096Groups = (preCullVertexCount + 4095) >> 12
        
        let fillSize = (preCullVertexCount + 1) >> 1 * MemoryLayout<UInt8>.stride
        blitEncoder.fill(buffer: vertexMatchBuffer, level: .count, range: 0..<fillSize, value: 0x11)
        
        let fillStart = numVertex16Groups * MemoryLayout<UInt8>.stride
        let fillEnd   = numVertex4096Groups << 8 * MemoryLayout<UInt8>.stride
        if fillStart < fillEnd {
            blitEncoder.fill(buffer: vertexMatchBuffer, level: .counts16, range: fillStart..<fillEnd, value: 0)
        }
        
        let fillRange = 0..<(~7 & (oldTriangleCount + 7)) * MemoryLayout<Bool>.stride
        blitEncoder.fill(buffer: sceneTexelRasterizer.bridgeBuffer, level: .matchExistsMark, range: fillRange, value: 0)
        blitEncoder.endEncoding()
        
        
        
        var computeEncoder = commandBuffer1.makeComputeCommandEncoder()!
        computeEncoder.optLabel = "First Scene Mesh Match - Compute Pass 1"
        
        computeEncoder.pushOptDebugGroup("Map Small Sectors")
        
        computeEncoder.setComputePipelineState(mapMeshSmallSectorsPipelineState)
        computeEncoder.setBuffer(oldSmallSectorBuffer, level: .sortedHashMappings, index: 0)
        computeEncoder.setBuffer(oldSmallSectorBuffer, level: .sortedHashes,       index: 1)
        computeEncoder.setBuffer(oldSmallSectorBuffer, level: .numSectorsMinus1,   index: 2)
        
        computeEncoder.setBuffer(newSmallSectorBuffer, level: .mappings,           index: 3)
        computeEncoder.setBuffer(newSmallSectorBuffer, level: .hashes,             index: 4)
        computeEncoder.dispatchThreadgroups([ octreeAsArray.count ], threadsPerThreadgroup: 1)
        
        computeEncoder.popOptDebugGroup()
        computeEncoder.pushOptDebugGroup("Match Mesh Vertices")
            
        computeEncoder.setComputePipelineState(matchMeshVerticesPipelineState)
        computeEncoder.setBuffer(newReducedVertexBuffer,                                      offset: 0, index: 0)
        computeEncoder.setBuffer(sourceVertexDataBuffer,       level: .nanoSectorMappings,               index: 2)
        computeEncoder.setBuffer(thirdSorterMicroSectorBuffer, level: .microSectorToSmallSectorMappings, index: 4)
        computeEncoder.setBuffer(thirdSorterMicroSectorBuffer, level: .microSectorIDsInSmallSectors,     index: 5)
        
        computeEncoder.setBuffer(oldReducedVertexBuffer,                                      offset: 0, index: 6)
        computeEncoder.setBuffer(oldMicroSector512thBuffer,    level: .offsets,                          index: 7)
        computeEncoder.setBuffer(oldMicroSector512thBuffer,    level: .counts,                           index: 8)
        computeEncoder.setBuffer(oldNanoSector512thBuffer,     level: .offsets64,                        index: 9)
        
        computeEncoder.setBuffer(oldNanoSector512thBuffer,     level: .offsets512th,                     index: 10)
        computeEncoder.setBuffer(oldNanoSector512thBuffer,     level: .counts512th,                      index: 11)
        computeEncoder.setBuffer(oldComparisonIDBuffer,                                       offset: 0, index: 12)
        
        computeEncoder.setBuffer(vertexMatchBuffer,            level: .count,                            index: 13)
        computeEncoder.setBuffer(newSmallSectorBuffer,         level: .preCullVertexCount,               index: 14)
        computeEncoder.setBuffer(vertexMatchBuffer,            level: .counts16,                         index: 15)
        computeEncoder.setBuffer(vertexMatchBuffer,            level: .offset,                           index: 16)
        computeEncoder.dispatchThreadgroups([ numVertex16Groups ], threadsPerThreadgroup: 1)
        
        computeEncoder.popOptDebugGroup()
        computeEncoder.pushOptDebugGroup("Count Matched Vertices")
        
        computeEncoder.setComputePipelineState(countMatchedVertices64PipelineState)
        computeEncoder.setBuffer(vertexMatchBuffer, level: .counts64, index: 1)
        computeEncoder.dispatchThreadgroups([ numVertex4096Groups << 6 ], threadsPerThreadgroup: 1)
        
        computeEncoder.setComputePipelineState(countMatchedVertices512PipelineState)
        computeEncoder.setBuffer(vertexMatchBuffer, level: .counts512, index: 0)
        computeEncoder.dispatchThreadgroups([ numVertex4096Groups << 3 ], threadsPerThreadgroup: 1)
        
        computeEncoder.setComputePipelineState(sceneMeshReducer.scanSubmeshVertices4096PipelineState)
        computeEncoder.setBuffer(vertexMatchBuffer, level: .counts4096, index: 1, asOffset: true)
        computeEncoder.setBuffer(vertexMatchBuffer, level: .offsets512, index: 2)
        computeEncoder.dispatchThreadgroups([ numVertex4096Groups ], threadsPerThreadgroup: 1)
        
        computeEncoder.popOptDebugGroup()
        computeEncoder.endEncoding()
        
        commandBuffer1.commit()
        
        
        
        let commandBuffer2 = renderer.commandQueue.makeDebugCommandBuffer()
        commandBuffer2.optLabel = "First Scene Mesh Match Command Buffer 2"
            
        computeEncoder = commandBuffer2.makeComputeCommandEncoder()!
        computeEncoder.optLabel = "First Scene Mesh Match - Compute Pass 2"
        
        computeEncoder.pushOptDebugGroup("Mark Matched Vertex Offsets")
        
        computeEncoder.setComputePipelineState(markMatchedVertexOffsets512PipelineState)
        computeEncoder.setBuffer(vertexMatchBuffer, level: .offsets512, index: 2)
        computeEncoder.setBuffer(vertexMatchBuffer, level: .counts64,   index: 0)
        computeEncoder.setBuffer(vertexMatchBuffer, level: .offsets64,  index: 1)
        computeEncoder.dispatchThreadgroups([ (preCullVertexCount + 511) >> 9 ], threadsPerThreadgroup: 1)
        
        computeEncoder.setComputePipelineState(sceneMeshReducer.markSubmeshVertexOffsets64to16PipelineState)
        computeEncoder.setBuffer(vertexMatchBuffer, level: .counts16,  index: 0, asOffset: true)
        computeEncoder.setBuffer(vertexMatchBuffer, level: .offsets16, index: 2, asOffset: true)
        computeEncoder.dispatchThreadgroups([ (preCullVertexCount + 63) >> 6 ], threadsPerThreadgroup: 1)
        
        computeEncoder.popOptDebugGroup()
        computeEncoder.pushOptDebugGroup("Write Matched Mesh Vertices")
        
        computeEncoder.setComputePipelineState(writeMatchedMeshVerticesPipelineState)
        computeEncoder.setBuffer(vertexMatchBuffer,            level: .count,                            index: 0, asOffset: true)
        computeEncoder.setBuffer(vertexMatchBuffer,            level: .offset,                           index: 1, asOffset: true)
        computeEncoder.setBuffer(vertexMatchBuffer,            level: .offsets4096,                      index: 3)
        computeEncoder.setBuffer(newSmallSectorBuffer,         level: .preCullVertexCount,               index: 4)
        
        computeEncoder.setBuffer(newReducedVertexBuffer,                                      offset: 0, index: 5)
        computeEncoder.setBuffer(sourceVertexDataBuffer,       level: .nanoSectorMappings,               index: 7)
        computeEncoder.setBuffer(newSmallSectorBuffer,         level: .mappings,                         index: 8)
        computeEncoder.setBuffer(thirdSorterMicroSectorBuffer, level: .microSectorToSmallSectorMappings, index: 9)
        computeEncoder.setBuffer(thirdSorterMicroSectorBuffer, level: .microSectorIDsInSmallSectors,     index: 10)
        
        computeEncoder.setBuffer(oldReducedVertexBuffer,                                      offset: 0, index: 11)
        computeEncoder.setBuffer(oldMicroSector512thBuffer,    level: .offsets,                          index: 12)
        computeEncoder.setBuffer(oldMicroSector512thBuffer,    level: .counts,                           index: 13)
        computeEncoder.setBuffer(oldNanoSector512thBuffer,     level: .offsets64,                        index: 14)
        
        computeEncoder.setBuffer(oldNanoSector512thBuffer,     level: .offsets512th,                     index: 15)
        computeEncoder.setBuffer(oldNanoSector512thBuffer,     level: .counts512th,                      index: 16)
        computeEncoder.setBuffer(oldComparisonIDBuffer,                                       offset: 0, index: 17)
        
        var bridgeBuffer: MultiLevelBuffer<SceneTexelRasterizer.BridgeLevel> { sceneTexelRasterizer.bridgeBuffer }
        computeEncoder.setBuffer(newToOldMatchWindingBuffer,                                  offset: 0, index: 18)
        computeEncoder.setBuffer(bridgeBuffer,                 level: .matchExistsMark,                  index: 19)
        
        let vertexMatchCounts4096Pointer  = vertexMatchBuffer[.counts4096].assumingMemoryBound(to: UInt16.self)
        let vertexMatchOffsets4096Pointer = vertexMatchBuffer[.offsets4096].assumingMemoryBound(to: UInt32.self)
        
        commandBuffer1.waitUntilCompleted()
        
        
        
        var vertexMatchOffset: UInt32 = 0
        
        for i in 0..<numVertex4096Groups {
            vertexMatchOffsets4096Pointer[i] = vertexMatchOffset
            vertexMatchOffset += UInt32(vertexMatchCounts4096Pointer[i])
        }
        
        ensureBufferCapacity(type: .vertexMatch, capacity: vertexMatchOffset)
        
        computeEncoder.setBuffer(newToOldVertexMatchesBuffer, offset: 0, index: 6)
        computeEncoder.dispatchThreadgroups([ numVertex16Groups ], threadsPerThreadgroup: 1)
        
        computeEncoder.popOptDebugGroup()
        computeEncoder.pushOptDebugGroup("Match Mesh Triangles")
            
        computeEncoder.setComputePipelineState(matchMeshTrianglesPipelineState)
        computeEncoder.setBuffer(newReducedIndexBuffer,         offset: 0, index: 4)
        computeEncoder.setBuffer(newToOldTriangleMatchesBuffer, offset: 0, index: 7)
        
        computeEncoder.setBuffer(oldReducedIndexBuffer,         offset: 0, index: 8)
        computeEncoder.setBuffer(oldVertexMapBuffer,    level: .mapCounts, index: 9)
        computeEncoder.setBuffer(oldVertexMapBuffer,    level: .maps,      index: 10)
        computeEncoder.dispatchThreadgroups([ preCullTriangleCount ], threadsPerThreadgroup: 1)
        
        computeEncoder.popOptDebugGroup()
        computeEncoder.endEncoding()
        
        commandBuffer2.commit()
    }
    
}
