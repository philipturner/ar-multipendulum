//
//  SceneTexelManagementExecution.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 4/13/21.
//

import Metal
import simd

extension SceneTexelManager {
    
    func classifyTriangleSizes() {
        swapBuffers()
        ensureBufferCapacity(type: .triangle, capacity: preCullTriangleCount)
        
        let triangleCountPointer = bridgeBuffer[.triangleCount].assumingMemoryBound(to: UInt32.self)
        triangleCountPointer.pointee = UInt32(preCullTriangleCount)
        
        let commandBuffer1 = renderer.commandQueue.makeDebugCommandBuffer()
        commandBuffer1.optLabel = "Scene Triangle Size Classification Command Buffer 1"
        
        let num16Groups   = (preCullTriangleCount + 15) >> 4
        let num4096Groups = (preCullTriangleCount + 4095) >> 12
        
        let fillStart = num16Groups        * MemoryLayout<simd_uchar4>.stride
        let fillEnd   = num4096Groups << 8 * MemoryLayout<simd_uchar4>.stride
        
        if fillStart < fillEnd {
            let blitEncoder = commandBuffer1.makeBlitCommandEncoder()!
            blitEncoder.optLabel = "Scene Triangle Size Classification - Clear Counts 16 Buffer"
            
            blitEncoder.fill(buffer: bridgeBuffer, level: .counts16, range: fillStart..<fillEnd, value: 0)
            blitEncoder.endEncoding()
        }
        
        
        
        var computeEncoder = commandBuffer1.makeComputeCommandEncoder()!
        computeEncoder.optLabel = "Scene Triangle Size Classification - Compute Pass 1"
        
        computeEncoder.pushOptDebugGroup("Count Triangle Sizes")
        
        computeEncoder.setComputePipelineState(countTriangleSizes16PipelineState)
        computeEncoder.setBuffer(newTriangleDataBuffer,             level: .columnCount,               index: 0)
        computeEncoder.setBuffer(newRasterizationComponentBuffer,                           offset: 0, index: 1)
        computeEncoder.setBuffer(bridgeBuffer,                      level: .triangleCount,             index: 2)
        
        computeEncoder.setBuffer(bridgeBuffer,                      level: .counts16,                  index: 3)
        computeEncoder.setBuffer(triangleMarkBuffer,                level: .sizeMark,                  index: 4)
        computeEncoder.setBuffer(sceneTexelRasterizer.bridgeBuffer, level: .compressedHaveChangedMark, index: 5)
        computeEncoder.dispatchThreadgroups([ num16Groups ], threadsPerThreadgroup: 1)
        
        computeEncoder.setComputePipelineState(countTriangleSizes64PipelineState)
        computeEncoder.setBuffer(bridgeBuffer, level: .counts64, index: 4)
        computeEncoder.dispatchThreadgroups([ num4096Groups << 6 ], threadsPerThreadgroup: 1)
        
        computeEncoder.setComputePipelineState(countTriangleSizes512PipelineState)
        computeEncoder.setBuffer(bridgeBuffer, level: .counts512, index: 5)
        computeEncoder.dispatchThreadgroups([ num4096Groups << 3 ], threadsPerThreadgroup: 1)
        
        computeEncoder.setComputePipelineState(scanTriangleSizes4096PipelineState)
        computeEncoder.setBuffer(bridgeBuffer, level: .counts4096, index: 6)
        computeEncoder.setBuffer(bridgeBuffer, level: .offsets512, index: 7)
        computeEncoder.dispatchThreadgroups([ num4096Groups ], threadsPerThreadgroup: 1)
        
        computeEncoder.popOptDebugGroup()
        computeEncoder.endEncoding()
        
        commandBuffer1.commit()
        
        
        
        let commandBuffer2 = renderer.commandQueue.makeDebugCommandBuffer()
        commandBuffer2.optLabel = "Scene Triangle Size Classification Command Buffer 2"
        
        computeEncoder = commandBuffer2.makeComputeCommandEncoder()!
        computeEncoder.optLabel = "Scene Triangle Size Classification - Compute Pass 2"
        
        computeEncoder.pushOptDebugGroup("Mark Triangle Size Offsets")
        
        computeEncoder.setComputePipelineState(markTriangleSizeOffsets512PipelineState)
        computeEncoder.setBuffer(bridgeBuffer, level: .offsets512, index: 0)
        computeEncoder.setBuffer(bridgeBuffer, level: .offsets64,  index: 1)
        computeEncoder.setBuffer(bridgeBuffer, level: .counts64,   index: 2)
        computeEncoder.dispatchThreadgroups([ (preCullTriangleCount + 511) >> 9 ], threadsPerThreadgroup: 1)
        
        computeEncoder.setComputePipelineState(markTriangleSizeOffsets64PipelineState)
        computeEncoder.setBuffer(bridgeBuffer, level: .offsets16, index: 2, asOffset: true)
        computeEncoder.setBuffer(bridgeBuffer, level: .counts16,  index: 3)
        computeEncoder.dispatchThreadgroups([ (preCullTriangleCount + 63) >> 6 ], threadsPerThreadgroup: 1)
        
        let counts4096Pointer  = bridgeBuffer[.counts4096].assumingMemoryBound(to: simd_ushort4.self)
        let offsets4096Pointer = bridgeBuffer[.offsets4096].assumingMemoryBound(to: simd_uint2.self)
        
        commandBuffer1.waitUntilCompleted()
        
        
        
        var triangleOffsets = simd_uint4()
        
        for i in 0..<num4096Groups {
            offsets4096Pointer[i] = triangleOffsets.highHalf
            triangleOffsets &+= simd_uint4(truncatingIfNeeded: counts4096Pointer[i])
        }
        
        numOldSmallTriangles = numNewSmallTriangles
        numOldLargeTriangles = numNewLargeTriangles
        numNewSmallTriangles = Int(triangleOffsets[0])
        numNewLargeTriangles = Int(triangleOffsets[1])
        
        maxSmallTriangleTextureSlotID = ~31 & max(maxSmallTriangleTextureSlotID, numNewSmallTriangles + 31)
        maxLargeTriangleTextureSlotID = ~31 & max(maxLargeTriangleTextureSlotID, numNewLargeTriangles + 31)
        
        ensureBufferCapacity(type: .smallTriangleSlot, capacity: maxSmallTriangleTextureSlotID)
        ensureBufferCapacity(type: .largeTriangleSlot, capacity: maxLargeTriangleTextureSlotID)
        
        let numOpenSmallTextureSlotsPointer = smallTriangleSlotBuffer[.totalNumOpenSlots].assumingMemoryBound(to: UInt32.self)
        numOpenSmallTextureSlotsPointer.pointee = 0
        
        let numOpenLargeTextureSlotsPointer = largeTriangleSlotBuffer[.totalNumOpenSlots].assumingMemoryBound(to: UInt32.self)
        numOpenLargeTextureSlotsPointer.pointee = 0
        
        
        
        computeEncoder.popOptDebugGroup()
        computeEncoder.pushOptDebugGroup("Clear Triangle Texture Slots")
        
        computeEncoder.setComputePipelineState(clearTriangleTextureSlotsPipelineState)
        computeEncoder.setBuffer(smallTriangleSlotBuffer, level: .slot, index: 12)
        computeEncoder.dispatchThreads([ maxSmallTriangleTextureSlotID >> 5 ], threadsPerThreadgroup: 32)
        
        computeEncoder.setBuffer(largeTriangleSlotBuffer, level: .slot, index: 12)
        computeEncoder.dispatchThreads([ maxLargeTriangleTextureSlotID >> 5 ], threadsPerThreadgroup: 32)
        
        computeEncoder.popOptDebugGroup()
        computeEncoder.pushOptDebugGroup("Find Open Triangle Texture Slots")
        
        computeEncoder.setBuffer(oldTriangleMarkBuffer,   level: .textureSlotID, index: 10)
        computeEncoder.setBuffer(smallTriangleSlotBuffer, level: .slot,          index: 11)
        
        if let oldTriangleCount = oldTriangleCount {
            computeEncoder.setComputePipelineState(markTriangleTextureSlotsPipelineState)
            computeEncoder.setBuffer(sceneTexelRasterizer.bridgeBuffer, level: .matchExistsMark, index: 9)
            computeEncoder.dispatchThreadgroups([ (oldTriangleCount + 7) >> 3 ], threadsPerThreadgroup: 1)
        }
        
        computeEncoder.setComputePipelineState(findOpenTriangleTextureSlotsPipelineState)
        computeEncoder.setBuffer(smallTriangleSlotBuffer, level: .openSlotID,        index: 12)
        computeEncoder.setBuffer(smallTriangleSlotBuffer, level: .totalNumOpenSlots, index: 13)
        computeEncoder.dispatchThreads([ maxSmallTriangleTextureSlotID >> 5 ], threadsPerThreadgroup: 32)
        
        computeEncoder.setBuffer(largeTriangleSlotBuffer, level: .slot,              index: 11)
        computeEncoder.setBuffer(largeTriangleSlotBuffer, level: .openSlotID,        index: 12)
        computeEncoder.setBuffer(largeTriangleSlotBuffer, level: .totalNumOpenSlots, index: 13)
        computeEncoder.dispatchThreads([ maxLargeTriangleTextureSlotID >> 5 ], threadsPerThreadgroup: 32)
        
        computeEncoder.popOptDebugGroup()
        computeEncoder.pushOptDebugGroup("Mark Triangle Size Offsets 16")
        
        computeEncoder.setComputePipelineState(markTriangleSizeOffsets16PipelineState)
        computeEncoder.setBuffer(bridgeBuffer,                      level: .offsets4096,               index: 3, asOffset: true)
        computeEncoder.setBuffer(triangleMarkBuffer,                level: .sizeMark,                  index: 4)
        computeEncoder.setBuffer(sceneTexelRasterizer.bridgeBuffer, level: .compressedHaveChangedMark, index: 5)
        
        computeEncoder.setBuffer(bridgeBuffer,                      level: .triangleCount,             index: 6)
        computeEncoder.setBuffer(triangleMarkBuffer,                level: .textureOffset,             index: 7)
        computeEncoder.setBuffer(triangleMarkBuffer,                level: .textureSlotID,             index: 8)
        computeEncoder.setBuffer(newToOldTriangleMatchesBuffer,                             offset: 0, index: 9)
        
        computeEncoder.setBuffer(smallTriangleSlotBuffer,           level: .openSlotID,                index: 11)
        computeEncoder.dispatchThreadgroups([ num16Groups ], threadsPerThreadgroup: 1)
        
        computeEncoder.popOptDebugGroup()
        computeEncoder.endEncoding()
        
        commandBuffer2.commit()
    }
    
    func transferColorDataToTexture() {
        let commandBuffer = renderer.commandQueue.makeDebugCommandBuffer()
        commandBuffer.optLabel = "Scene Color Data Transfer Command Buffer 2"
        
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.optLabel = "Scene Color Data Transfer - Compute Pass 2"
        
        computeEncoder.setComputePipelineState(transferColorDataToTexturePipelineState)
        computeEncoder.setBuffer(triangleMarkBuffer,                level: .textureOffset,    index: 0)
        computeEncoder.setBuffer(sceneTexelRasterizer.bridgeBuffer, level: .haveChangedMark,  index: 1)
        
        computeEncoder.setBuffer(sceneTexelRasterizer.texelBuffer,  level: .luma,             index: 2)
        computeEncoder.setBuffer(sceneTexelRasterizer.texelBuffer,  level: .chroma,           index: 3)
        computeEncoder.setBuffer(newTriangleDataBuffer,             level: .columnCount,      index: 4)
        
        computeEncoder.setBuffer(newTriangleDataBuffer,             level: .texelOffset,      index: 5)
        computeEncoder.setBuffer(newTriangleDataBuffer,             level: .columnOffset,     index: 6)
        computeEncoder.setBuffer(newTriangleDataBuffer,             level: .texelOffsets256,  index: 7)
        computeEncoder.setBuffer(newTriangleDataBuffer,             level: .columnOffsets256, index: 8)
        computeEncoder.setBuffer(sceneTexelRasterizer.expandedColumnOffsetBuffer,  offset: 0, index: 9)
        
        computeEncoder.setBuffer(smallTriangleColorBuffer,          level: .luma,             index: 10)
        computeEncoder.setBuffer(largeTriangleColorBuffer,          level: .luma,             index: 11)
        computeEncoder.setBuffer(smallTriangleColorBuffer,          level: .chroma,           index: 12)
        computeEncoder.setBuffer(largeTriangleColorBuffer,          level: .chroma,           index: 13)
        computeEncoder.dispatchThreadgroups([ preCullTriangleCount ], threadsPerThreadgroup: 1)
        
        computeEncoder.endEncoding()
        commandBuffer.commit()
    }
    
}
