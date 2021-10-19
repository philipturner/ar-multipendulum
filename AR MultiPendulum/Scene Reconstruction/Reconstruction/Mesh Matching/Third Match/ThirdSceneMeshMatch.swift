//
//  ThirdSceneMeshMatch.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 6/17/21.
//

import Metal
import simd

extension SceneMeshMatcher {
    
    func doThirdMeshMatch() {
        let shouldDoThirdMatchPointer = newSmallSectorBuffer[.shouldDoThirdMatch].assumingMemoryBound(to: Bool.self)
        guard shouldDoThirdMatchPointer.pointee else {
            doingThirdMatch = false
            oldTriangleCount = preCullTriangleCount
            return
        }
        
        doingThirdMatch = true
        
        ensureBufferCapacity(type: .superNanoSector, capacity: numMicroSectors << 6)
        
        
        
        let commandBuffer = renderer.commandQueue.makeDebugCommandBuffer()
        commandBuffer.optLabel = "Third Scene Mesh Match Command Buffer"
            
        let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
        blitEncoder.optLabel = "Third Scene Mesh Match - Clear Sector Marks"
        
        var fillSize = octreeAsArray.count * MemoryLayout<UInt32>.stride
        blitEncoder.fill(buffer: oldSmallSectorBuffer, level: .mark, range: 0..<fillSize, value: 0)
        
        fillSize = numMicroSectors * MemoryLayout<UInt8>.stride
        blitEncoder.fill(buffer: oldMicroSectorBuffer, level: .microSectorMark,     range: 0..<fillSize,      value: 0)
        blitEncoder.fill(buffer: oldMicroSectorBuffer, level: .subMicroSectorMark,  range: 0..<fillSize,      value: 0)
        blitEncoder.fill(buffer: oldMicroSectorBuffer, level: .superNanoSectorMark, range: 0..<fillSize << 3, value: 0)
        
        fillSize = numMicroSectors * MemoryLayout<simd_half4>.stride
        blitEncoder.fill(buffer: oldMicroSectorBuffer, level: .microSectorColor,    range: 0..<fillSize,      value: 0)
        blitEncoder.fill(buffer: oldMicroSectorBuffer, level: .subMicroSectorColor, range: 0..<fillSize << 3, value: 0)
        blitEncoder.fill(buffer: nanoSectorColorAlias, level: .subsectorData,       range: 0..<fillSize << 6, value: 0)
        
        blitEncoder.endEncoding()
        
        
        
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.optLabel = "Third Scene Mesh Match - Compute Pass"
        
        computeEncoder.pushOptDebugGroup("Prepare Third Mesh Match")
        
        computeEncoder.setComputePipelineState(prepareThirdMeshMatchPipelineState)
        computeEncoder.setBuffer(newReducedIndexBuffer,                      offset: 0, index: 1)
        computeEncoder.setBuffer(newReducedVertexBuffer,                     offset: 0, index: 2)
        computeEncoder.setBuffer(newToOldTriangleMatchesBuffer,              offset: 0, index: 3)
        
        computeEncoder.setBuffer(newSmallSectorBuffer,      level: .numSectorsMinus1,    index: 7)
        computeEncoder.setBuffer(newSmallSectorBuffer,      level: .mappings,            index: 8)
        computeEncoder.setBuffer(newSmallSectorBuffer,      level: .sortedHashes,        index: 9)
        computeEncoder.setBuffer(newSmallSectorBuffer,      level: .sortedHashMappings,  index: 10)
        
        computeEncoder.setBuffer(oldMicroSector512thBuffer, level: .offsets,             index: 13)
        computeEncoder.setBuffer(oldMicroSector512thBuffer, level: .counts,              index: 14)
        
        computeEncoder.setBuffer(oldSmallSectorBuffer,      level: .mark,                index: 15)
        computeEncoder.setBuffer(oldMicroSectorBuffer,      level: .microSectorMark,     index: 16)
        computeEncoder.setBuffer(oldMicroSectorBuffer,      level: .subMicroSectorMark,  index: 17)
        computeEncoder.setBuffer(oldMicroSectorBuffer,      level: .superNanoSectorMark, index: 18)
        computeEncoder.dispatchThreadgroups([ preCullTriangleCount ], threadsPerThreadgroup: 1)
        
        computeEncoder.popOptDebugGroup()
        computeEncoder.pushOptDebugGroup("Mark Micro Sector Colors")
        
        computeEncoder.setComputePipelineState(markMicroSectorColorsPipelineState)
        computeEncoder.setBuffer(oldReducedColorBuffer,                      offset: 0, index: 4)
        computeEncoder.setBuffer(oldReducedIndexBuffer,                      offset: 0, index: 5)
        computeEncoder.setBuffer(oldReducedVertexBuffer,                     offset: 0, index: 6)

        computeEncoder.setBuffer(oldSmallSectorBuffer, level: .using8bitSmallSectorIDs, index: 11)
        computeEncoder.setBuffer(oldTransientSectorIDBuffer,                 offset: 0, index: 12)

        computeEncoder.setBuffer(oldMicroSectorBuffer, level: .microSectorColor,        index: 19)
        computeEncoder.setBuffer(oldMicroSectorBuffer, level: .subMicroSectorColor,     index: 20)
        computeEncoder.setBuffer(nanoSectorColorAlias, level: .subsectorData,           index: 21)
        computeEncoder.dispatchThreads([ oldTriangleCount ], threadsPerThreadgroup: 1)
        
        computeEncoder.popOptDebugGroup()
        computeEncoder.pushOptDebugGroup("Do Third Mesh Match")
        
        computeEncoder.setComputePipelineState(doThirdMeshMatchPipelineState)
        computeEncoder.setBuffer(newReducedColorBuffer, offset: 0, index: 0)
        computeEncoder.dispatchThreadgroups([ preCullTriangleCount ], threadsPerThreadgroup: 1)
        
        computeEncoder.popOptDebugGroup()
        
        computeEncoder.endEncoding()
        commandBuffer.commit()
        
        oldTriangleCount = preCullTriangleCount
    }
    
}
