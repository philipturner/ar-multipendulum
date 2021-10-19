//
//  SceneTexelRasterizationExecution.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 4/13/21.
//

import Metal
import simd

extension SceneTexelRasterizer {
    
    func swapTexelBuffers() {
        swap(&oldTriangleDataBuffer, &triangleDataBuffer)
        
        debugLabel {
            triangleDataBuffer.label    = "New " + TriangleDataLevel.bufferLabel
            oldTriangleDataBuffer.label = "Old " + TriangleDataLevel.bufferLabel
        }
        
        swap(&oldRasterizationComponentBuffer, &rasterizationComponentBuffer)
        swap(&oldExpandedColumnOffsetBuffer,   &expandedColumnOffsetBuffer)
        
        debugLabel {
            rasterizationComponentBuffer.label    =       "Scene Texel Rasterizer Rasterization Component Buffer"
            oldRasterizationComponentBuffer.label = "(Old) Scene Texel Rasterizer Rasterization Component Buffer"
            
            expandedColumnOffsetBuffer.label    =       "Scene Texel Rasterizer Expanded Column Offset Buffer"
            oldExpandedColumnOffsetBuffer.label = "(Old) Scene Texel Rasterizer Expanded Column Offset Buffer"
        }
    }
    
    func rasterizeTexels() {
        swapTexelBuffers()
        ensureBufferCapacity(type: .triangleData, capacity: preCullTriangleCount)
        
        let triangleCountBufferPointer = bridgeBuffer[.triangleCount].assumingMemoryBound(to: UInt32.self)
        triangleCountBufferPointer.pointee = UInt32(preCullTriangleCount)
        
        let commandBuffer1 = renderer.commandQueue.makeDebugCommandBuffer()
        commandBuffer1.optLabel = "Scene Texel Rasterization Command Buffer 1"
            
        let num16Groups   = (preCullTriangleCount + 15) >> 4
        let num4096Groups = (preCullTriangleCount + 4095) >> 12
        
        let fillStart = num16Groups        * MemoryLayout<UInt16>.stride
        let fillEnd   = num4096Groups << 8 * MemoryLayout<UInt16>.stride
        
        if fillStart < fillEnd {
            let blitEncoder = commandBuffer1.makeBlitCommandEncoder()!
            blitEncoder.optLabel = "Scene Texel Rasterization - Clear Counts 16 Buffers"
            
            blitEncoder.fill(buffer: bridgeBuffer, level: .texelCounts16,  range: fillStart..<fillEnd, value: 0)
            blitEncoder.fill(buffer: bridgeBuffer, level: .columnCounts16, range: fillStart..<fillEnd, value: 0)
            
            blitEncoder.endEncoding()
        }
        
        
        
        var computeEncoder = commandBuffer1.makeComputeCommandEncoder()!
        computeEncoder.optLabel = "Scene Texel Rasterization - Compute Pass 1"
        
        computeEncoder.pushOptDebugGroup("Rasterize Texels")
        
        computeEncoder.setComputePipelineState(rasterizeTexelsPipelineState)
        computeEncoder.setBuffer(newReducedIndexBuffer,                      offset: 0, index: 0)
        computeEncoder.setBuffer(newReducedVertexBuffer,                     offset: 0, index: 1)
        computeEncoder.setBuffer(bridgeBuffer,       level: .triangleCount,             index: 2)
        
        computeEncoder.setBuffer(triangleDataBuffer, level: .texelCount,                index: 3)
        computeEncoder.setBuffer(triangleDataBuffer, level: .columnCount,               index: 4)
        computeEncoder.setBuffer(bridgeBuffer,       level: .texelCounts16,             index: 5)
        computeEncoder.setBuffer(bridgeBuffer,       level: .columnCounts16,            index: 6)
        
        computeEncoder.setBuffer(bridgeBuffer,       level: .haveChangedMark,           index: 7)
        computeEncoder.setBuffer(bridgeBuffer,       level: .compressedHaveChangedMark, index: 8)
        computeEncoder.setBuffer(rasterizationComponentBuffer,               offset: 0, index: 9)
        
        computeEncoder.setBuffer(newToOldTriangleMatchesBuffer,              offset: 0, index: 10)
        computeEncoder.setBuffer(oldRasterizationComponentBuffer,            offset: 0, index: 11)
        computeEncoder.setBuffer(newToOldMatchWindingBuffer,                 offset: 0, index: 12)
        computeEncoder.dispatchThreadgroups([ num16Groups ], threadsPerThreadgroup: 1)
        
        computeEncoder.popOptDebugGroup()
        computeEncoder.pushOptDebugGroup("Count Texels")
        
        computeEncoder.setComputePipelineState(countTexels64PipelineState)
        computeEncoder.setBuffer(bridgeBuffer, level: .texelCounts64,  index: 7, asOffset: true)
        computeEncoder.setBuffer(bridgeBuffer, level: .columnCounts64, index: 8, asOffset: true)
        computeEncoder.dispatchThreadgroups([ num4096Groups << 6 ], threadsPerThreadgroup: 1)
        
        computeEncoder.setComputePipelineState(scanTexels256PipelineState)
        computeEncoder.setBuffer(bridgeBuffer, level: .texelCounts256,  index: 9)
        computeEncoder.setBuffer(bridgeBuffer, level: .columnCounts256, index: 10)
        
        computeEncoder.setBuffer(bridgeBuffer, level: .texelOffsets64,  index: 11)
        computeEncoder.setBuffer(bridgeBuffer, level: .columnOffsets64, index: 12)
        computeEncoder.dispatchThreadgroups([ num4096Groups << 4 ], threadsPerThreadgroup: 1)
        
        computeEncoder.setComputePipelineState(countTexels1024PipelineState)
        computeEncoder.setBuffer(bridgeBuffer, level: .texelCounts1024,  index: 11, asOffset: true)
        computeEncoder.setBuffer(bridgeBuffer, level: .columnCounts1024, index: 12, asOffset: true)
        computeEncoder.dispatchThreadgroups([ num4096Groups << 2 ], threadsPerThreadgroup: 1)
        
        computeEncoder.setComputePipelineState(countTexels4096PipelineState)
        computeEncoder.setBuffer(bridgeBuffer, level: .texelCounts4096,  index: 13)
        computeEncoder.setBuffer(bridgeBuffer, level: .columnCounts4096, index: 14)
        computeEncoder.dispatchThreadgroups([ num4096Groups ], threadsPerThreadgroup: 1)
        
        computeEncoder.popOptDebugGroup()
        computeEncoder.endEncoding()
        
        commandBuffer1.commit()
        
        
        
        let commandBuffer2 = renderer.commandQueue.makeDebugCommandBuffer()
        commandBuffer2.optLabel = "Scene Texel Rasterization Command Buffer 2"
            
        computeEncoder = commandBuffer2.makeComputeCommandEncoder()!
        computeEncoder.optLabel = "Scene Texel Rasterization - Compute Pass 2"
        
        computeEncoder.pushOptDebugGroup("Mark Texel Offsets")
        
        computeEncoder.setComputePipelineState(markTexelOffsets4096PipelineState)
        computeEncoder.setBuffer(bridgeBuffer, level: .texelCounts1024,   index: 0)
        computeEncoder.setBuffer(bridgeBuffer, level: .columnCounts1024,  index: 1)
        
        computeEncoder.setBuffer(bridgeBuffer, level: .texelOffsets4096,  index: 2)
        computeEncoder.setBuffer(bridgeBuffer, level: .columnOffsets4096, index: 3)
        
        computeEncoder.setBuffer(bridgeBuffer, level: .texelOffsets1024,  index: 4)
        computeEncoder.setBuffer(bridgeBuffer, level: .columnOffsets1024, index: 5)
        computeEncoder.dispatchThreadgroups([ num4096Groups ], threadsPerThreadgroup: 1)
        
        computeEncoder.setComputePipelineState(markTexelOffsets1024PipelineState)
        computeEncoder.setBuffer(bridgeBuffer,       level: .texelCounts256,   index: 2, asOffset: true)
        computeEncoder.setBuffer(bridgeBuffer,       level: .columnCounts256,  index: 3, asOffset: true)
        
        computeEncoder.setBuffer(triangleDataBuffer, level: .columnOffsets256, index: 6)
        computeEncoder.setBuffer(triangleDataBuffer, level: .texelOffsets256,  index: 7)
        computeEncoder.dispatchThreadgroups([ (preCullTriangleCount + 1023) >> 10 ], threadsPerThreadgroup: 1)
        
        computeEncoder.setComputePipelineState(markTexelOffsets64PipelineState)
        computeEncoder.setBuffer(bridgeBuffer, level: .texelCounts16,   index: 0, asOffset: true)
        computeEncoder.setBuffer(bridgeBuffer, level: .columnCounts16,  index: 1, asOffset: true)
        
        computeEncoder.setBuffer(bridgeBuffer, level: .texelOffsets64,  index: 2, asOffset: true)
        computeEncoder.setBuffer(bridgeBuffer, level: .columnOffsets64, index: 3, asOffset: true)
        
        computeEncoder.setBuffer(bridgeBuffer, level: .texelOffsets16,  index: 4, asOffset: true)
        computeEncoder.setBuffer(bridgeBuffer, level: .columnOffsets16, index: 5, asOffset: true)
        computeEncoder.dispatchThreadgroups([ (preCullTriangleCount + 63) >> 6 ], threadsPerThreadgroup: 1)
        
        computeEncoder.setComputePipelineState(markTexelOffsets16PipelineState)
        computeEncoder.setBuffer(triangleDataBuffer, level: .texelCount,    index: 0)
        computeEncoder.setBuffer(triangleDataBuffer, level: .columnCount,   index: 1)
        computeEncoder.setBuffer(triangleDataBuffer, level: .texelOffset,   index: 2)
        computeEncoder.setBuffer(triangleDataBuffer, level: .columnOffset,  index: 3)
        
        computeEncoder.setBuffer(newReducedIndexBuffer,          offset: 0, index: 8)
        computeEncoder.setBuffer(newReducedVertexBuffer,         offset: 0, index: 9)
        computeEncoder.setBuffer(bridgeBuffer,       level: .triangleCount, index: 10)
        computeEncoder.setBuffer(rasterizationComponentBuffer,   offset: 0, index: 11)
        
        let texelCounts4096Pointer    = bridgeBuffer[.texelCounts4096].assumingMemoryBound(to: UInt32.self)
        let columnCounts4096Pointer   = bridgeBuffer[.columnCounts4096].assumingMemoryBound(to: UInt32.self)
        
        let texelOffsets4096Pointer   = bridgeBuffer[.texelOffsets4096].assumingMemoryBound(to: UInt32.self)
        let columnOffsets4096Pointer  = bridgeBuffer[.columnOffsets4096].assumingMemoryBound(to: UInt32.self)
        
        commandBuffer1.waitUntilCompleted()
        
        
        
        var texelOffset:  UInt32 = 0
        var columnOffset: UInt32 = 0
        
        for i in 0..<num4096Groups {
            texelOffsets4096Pointer[i]  = texelOffset
            columnOffsets4096Pointer[i] = columnOffset
            
            texelOffset  += UInt32(texelCounts4096Pointer[i])
            columnOffset += UInt32(columnCounts4096Pointer[i])
        }
        
        ensureBufferCapacity(type: .column, capacity: columnOffset)
        ensureBufferCapacity(type: .texel,  capacity: texelOffset)
        
        computeEncoder.setBuffer(expandedColumnOffsetBuffer, offset: 0, index: 7)
        computeEncoder.dispatchThreadgroups([ num16Groups ], threadsPerThreadgroup: 1)
        
        computeEncoder.popOptDebugGroup()
        computeEncoder.endEncoding()
        
        commandBuffer2.commit()
    }
    
    func transferColorDataToBuffer() {
        let commandBuffer = renderer.commandQueue.makeDebugCommandBuffer()
        commandBuffer.optLabel = "Scene Color Data Transfer Command Buffer 1"
            
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.optLabel = "Scene Color Data Transfer - Compute Pass 1"
        
        computeEncoder.setComputePipelineState(transferColorDataToBufferPipelineState)
        computeEncoder.setBuffer(newToOldTriangleMatchesBuffer,           offset: 0, index: 0)
        computeEncoder.setBuffer(bridgeBuffer,             level: .haveChangedMark,  index: 1)
        computeEncoder.setBuffer(texelBuffer,              level: .luma,             index: 2)
        computeEncoder.setBuffer(texelBuffer,              level: .chroma,           index: 3)
        
        computeEncoder.setBuffer(newReducedColorBuffer,                   offset: 0, index: 4)
        computeEncoder.setBuffer(triangleDataBuffer,       level: .texelCount,       index: 5)
        computeEncoder.setBuffer(triangleDataBuffer,       level: .columnCount,      index: 6)
        computeEncoder.setBuffer(triangleDataBuffer,       level: .texelOffset,      index: 7)
        computeEncoder.setBuffer(triangleDataBuffer,       level: .columnOffset,     index: 8)
        computeEncoder.setBuffer(triangleDataBuffer,       level: .texelOffsets256,  index: 9)
        computeEncoder.setBuffer(triangleDataBuffer,       level: .columnOffsets256, index: 10)
        computeEncoder.setBuffer(expandedColumnOffsetBuffer,              offset: 0, index: 11)
        computeEncoder.setBuffer(rasterizationComponentBuffer,            offset: 0, index: 12)
        
        computeEncoder.setBuffer(oldReducedColorBuffer,                   offset: 0, index: 13)
        computeEncoder.setBuffer(oldTriangleMarkBuffer,    level: .textureOffset,    index: 14)
        computeEncoder.setBuffer(oldTriangleDataBuffer,    level: .columnCount,      index: 15)
        computeEncoder.setBuffer(oldTriangleDataBuffer,    level: .columnOffset,     index: 16)
        computeEncoder.setBuffer(oldTriangleDataBuffer,    level: .columnOffsets256, index: 17)
        computeEncoder.setBuffer(oldExpandedColumnOffsetBuffer,           offset: 0, index: 18)
        
        computeEncoder.setBuffer(smallTriangleColorBuffer, level: .luma,             index: 19)
        computeEncoder.setBuffer(largeTriangleColorBuffer, level: .luma,             index: 20)
        computeEncoder.setBuffer(smallTriangleColorBuffer, level: .chroma,           index: 21)
        computeEncoder.setBuffer(largeTriangleColorBuffer, level: .chroma,           index: 22)
        computeEncoder.dispatchThreads([ preCullTriangleCount ], threadsPerThreadgroup: 1)
        
        computeEncoder.endEncoding()
        commandBuffer.commit()
        
        sceneTexelManager.ensureBufferCapacity(type: .smallTriangle, capacity: sceneTexelManager.numNewSmallTriangles)
        sceneTexelManager.ensureBufferCapacity(type: .largeTriangle, capacity: sceneTexelManager.numNewLargeTriangles)
    }
    
}
