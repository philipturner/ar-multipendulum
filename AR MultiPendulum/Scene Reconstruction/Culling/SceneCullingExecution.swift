//
//  SceneCullingExecution.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 4/13/21.
//

import Metal
import simd

extension SceneCuller {
    
    func determineSectorInclusions() {
        typealias VertexUniforms = SceneRenderer.VertexUniforms
        let vertexUniforms = uniformBuffer[.vertexUniform].assumingMemoryBound(to: VertexUniforms.self)[renderIndex]
        
        var sectorInclusionsPointer = smallSectorBuffer[.inclusions].assumingMemoryBound(to: Bool.self)
        sectorInclusionsPointer += smallSectorBufferOffset
        
        for i in 0..<octreeNodeCenters.count {
            let center = simd_float4(octreeNodeCenters[i], 0)
            
            func getVisibility(using transform: simd_float4x4) -> Bool {
                var lowerCorners = simd_float4x4(
                    center + simd_float4(-1, -1, -1, 1),
                    center + simd_float4(-1, -1,  1, 1),
                    center + simd_float4(-1,  1, -1, 1),
                    center + simd_float4(-1,  1,  1, 1)
                )
                
                var upperCorners = simd_float4x4(
                    center + simd_float4( 1, -1, -1, 1),
                    center + simd_float4( 1, -1,  1, 1),
                    center + simd_float4( 1,  1, -1, 1),
                    center + simd_float4( 1,  1,  1, 1)
                )
                
                func transformHalf(_ input: inout simd_float4x4) {
                    input[0] = transform * input[0]
                    input[1] = transform * input[1]
                    input[2] = transform * input[2]
                    input[3] = transform * input[3]
                }
                
                transformHalf(&lowerCorners)
                transformHalf(&upperCorners)
                
                typealias ProjectedCorners = CentralObject.ProjectedCorners
                
                let projectedCorners = ProjectedCorners(lowerCorners: lowerCorners,
                                                        upperCorners: upperCorners)
                return projectedCorners.areVisible
            }
            
            if getVisibility(using: vertexUniforms.viewProjectionTransform) {
                sectorInclusionsPointer[i] = true
                continue
            }
            
            sectorInclusionsPointer[i] = getVisibility(using: vertexUniforms.cameraProjectionTransform)
        }
    }
    
    func cullScene(doingColorUpdate: Bool) {
        determineSectorInclusions()
        
        let commandBuffer = renderer.commandQueue.makeDebugCommandBuffer()
        commandBuffer.optLabel = "Scene Culling Command Buffer"
        
        let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
        blitEncoder.optLabel = "Scene Culling - Clear Mark And Count Buffers"
        
        let numTriangle8Groups  = (preCullTriangleCount + 7) >> 3
        let num8192Groups       = (preCullTriangleCount + 8191) >> 13
        let num8Groups_expanded = num8192Groups << 10
        
        if numTriangle8Groups < num8Groups_expanded {
            let fillStart = numTriangle8Groups  * MemoryLayout<simd_uchar4>.stride
            let fillEnd   = num8Groups_expanded * MemoryLayout<simd_uchar4>.stride
            
            blitEncoder.fill(buffer: bridgeBuffer, level: .counts8, range: fillStart..<fillEnd, value: 0)
        }
        
        let numVertex8Groups = (preCullVertexCount + 7) >> 3
        
        let fillSize = numVertex8Groups << 3 * MemoryLayout<UInt8>.stride
        blitEncoder.fill(buffer: vertexDataBuffer, level: .inclusionData, range: 0..<fillSize,      value: 0)
        blitEncoder.fill(buffer: vertexDataBuffer, level: .mark,          range: 0..<fillSize << 1, value: 0)
        
        blitEncoder.endEncoding()
        
        
        
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.optLabel = "Scene Culling - Compute Pass"
        
        computeEncoder.setBuffer(uniformBuffer, level: .vertexUniform,        offset: vertexUniformOffset,        index: 0)
        computeEncoder.setBuffer(uniformBuffer, level: .preCullVertexCount,   offset: preCullVertexCountOffset,   index: 1)
        computeEncoder.setBuffer(uniformBuffer, level: .preCullTriangleCount, offset: preCullTriangleCountOffset, index: 2)
        computeEncoder.setBuffer(reducedVertexBuffer,                         offset: 0,                          index: 3)
        computeEncoder.setBuffer(reducedIndexBuffer,                          offset: 0,                          index: 4)
        
        computeEncoder.pushOptDebugGroup("Mark Culls")
        
        let doing8bitSectorIDs = octreeNodeCenters.count <= 255
        
        computeEncoder.setComputePipelineState(doing8bitSectorIDs ? markVertexCulls_8bitPipelineState
                                                                  : markVertexCulls_16bitPipelineState)
        computeEncoder.setBuffer(vertexDataBuffer,  level: .inclusionData,                               index: 5)
        
        computeEncoder.setBuffer(sectorIDBuffer,    level: .vertexGroupMask,                             index: 6)
        computeEncoder.setBuffer(sectorIDBuffer,    level: .vertexGroup,                                 index: 7)
        computeEncoder.setBuffer(smallSectorBuffer, level: .inclusions, offset: smallSectorBufferOffset, index: 8)
        computeEncoder.dispatchThreadgroups([ numVertex8Groups ], threadsPerThreadgroup: 1);
        
        computeEncoder.setComputePipelineState(doing8bitSectorIDs ? markTriangleCulls_8bitPipelineState
                                                                  : markTriangleCulls_16bitPipelineState)
        computeEncoder.setBuffer(sectorIDBuffer,    level: .triangleGroupMask,   index: 6, asOffset: true)
        computeEncoder.setBuffer(sectorIDBuffer,    level: .triangleGroup,       index: 7, asOffset: true)
        
        computeEncoder.setBuffer(vertexDataBuffer,  level: .mark,                index: 9)
        computeEncoder.setBuffer(bridgeBuffer,      level: .triangleInclusions8, index: 11)
        computeEncoder.dispatchThreadgroups([ numTriangle8Groups ], threadsPerThreadgroup: 1)

        computeEncoder.popOptDebugGroup()
        computeEncoder.pushOptDebugGroup("Count Culls")
        
        computeEncoder.setComputePipelineState(countCullMarks8PipelineState)
        computeEncoder.setBuffer(vertexDataBuffer, level: .inclusions8, index: 10)
        computeEncoder.setBuffer(bridgeBuffer,     level: .counts8,     index: 12)
        computeEncoder.dispatchThreadgroups([ numTriangle8Groups ], threadsPerThreadgroup: 1)

        computeEncoder.setComputePipelineState(countCullMarks32to128PipelineState)
        computeEncoder.setBuffer(bridgeBuffer, level: .counts32, index: 13)
        computeEncoder.dispatchThreadgroups([ num8192Groups << 8 ], threadsPerThreadgroup: 1)
        
        computeEncoder.setBuffer(bridgeBuffer, level: .counts32,  index: 12, asOffset: true)
        computeEncoder.setBuffer(bridgeBuffer, level: .counts128, index: 13, asOffset: true)
        computeEncoder.dispatchThreadgroups([ num8192Groups << 6 ], threadsPerThreadgroup: 1)
        
        computeEncoder.setComputePipelineState(countCullMarks512PipelineState)
        computeEncoder.setBuffer(bridgeBuffer, level: .counts512, index: 14)
        computeEncoder.dispatchThreadgroups([ num8192Groups << 4 ], threadsPerThreadgroup: 1)
        
        computeEncoder.setComputePipelineState(countCullMarks2048to8192PipelineState)
        computeEncoder.setBuffer(bridgeBuffer, level: .counts2048, index: 15)
        computeEncoder.dispatchThreadgroups([ num8192Groups << 2 ], threadsPerThreadgroup: 1)
        
        computeEncoder.setBuffer(bridgeBuffer, level: .counts2048, index: 14, asOffset: true)
        computeEncoder.setBuffer(bridgeBuffer, level: .counts8192, index: 15, asOffset: true)
        computeEncoder.dispatchThreadgroups([ num8192Groups ], threadsPerThreadgroup: 1)
        
        computeEncoder.popOptDebugGroup()
        computeEncoder.pushOptDebugGroup("Scan Culls")

        computeEncoder.setComputePipelineState(scanSceneCullsPipelineState)
        computeEncoder.setBuffer(bridgeBuffer,  level: .offsets8192,         index: 16)
        computeEncoder.setBuffer(uniformBuffer, level: .triangleVertexCount, index: 17)
        computeEncoder.dispatchThreadgroups(1, threadsPerThreadgroup: 1)
        
        computeEncoder.popOptDebugGroup()
        computeEncoder.pushOptDebugGroup("Mark Cull Offsets")
            
        computeEncoder.setComputePipelineState(markCullOffsets8192to2048PipelineState)
        computeEncoder.setBuffer(bridgeBuffer, level: .offsets2048, index: 15, asOffset: true)
        computeEncoder.dispatchThreadgroups([ num8192Groups ], threadsPerThreadgroup: 1)
        
        computeEncoder.setBuffer(bridgeBuffer, level: .offsets2048, index: 16, asOffset: true)
        computeEncoder.setBuffer(bridgeBuffer, level: .offsets512,  index: 15, asOffset: true)
        computeEncoder.setBuffer(bridgeBuffer, level: .counts512,   index: 14, asOffset: true)
        computeEncoder.dispatchThreadgroups([ (preCullTriangleCount + 2047) >> 11 ], threadsPerThreadgroup: 1)
        
        computeEncoder.setComputePipelineState(markCullOffsets512to32PipelineState)
        computeEncoder.setBuffer(bridgeBuffer, level: .offsets128, index: 14, asOffset: true)
        computeEncoder.dispatchThreadgroups([ (preCullTriangleCount + 511) >> 9 ], threadsPerThreadgroup: 1)
        
        computeEncoder.setBuffer(bridgeBuffer, level: .offsets128, index: 15, asOffset: true)
        computeEncoder.setBuffer(bridgeBuffer, level: .offsets32,  index: 14, asOffset: true)
        computeEncoder.setBuffer(bridgeBuffer, level: .counts32,   index: 13, asOffset: true)
        computeEncoder.dispatchThreadgroups([ (preCullTriangleCount + 127) >> 7 ], threadsPerThreadgroup: 1)
        
        computeEncoder.setBuffer(bridgeBuffer, level: .offsets32, index: 15, asOffset: true)
        computeEncoder.setBuffer(bridgeBuffer, level: .offsets8,  index: 14, asOffset: true)
        computeEncoder.setBuffer(bridgeBuffer, level: .counts8,   index: 13, asOffset: true)
        computeEncoder.dispatchThreadgroups([ (preCullTriangleCount + 31) >> 5 ], threadsPerThreadgroup: 1)
        
        computeEncoder.popOptDebugGroup()
        computeEncoder.pushOptDebugGroup("Condense Geometry")
        
        if doingMixedRealityRendering {
            computeEncoder.setComputePipelineState(condenseMRVerticesPipelineState)
            computeEncoder.setBuffer(uniformBuffer, level: .mixedRealityUniform, offset: mixedRealityUniformOffset, index: 1)
        } else {
            computeEncoder.setComputePipelineState(condenseVerticesPipelineState)
        }
        computeEncoder.setBuffer(vertexDataBuffer, level: .renderOffset,    index: 5, asOffset: true)
        computeEncoder.setBuffer(vertexDataBuffer, level: .occlusionOffset, index: 9, asOffset: true)
        
        computeEncoder.setBuffer(vertexBuffer,     level: .renderVertex,    index: 6)
        computeEncoder.setBuffer(vertexBuffer,     level: .occlusionVertex, index: 7)
        computeEncoder.setBuffer(vertexBuffer,     level: .videoFrameCoord, index: 8)
        computeEncoder.dispatchThreadgroups([ numVertex8Groups ], threadsPerThreadgroup: 1)
        
        if doingColorUpdate {
            computeEncoder.setComputePipelineState(condenseTrianglesForColorUpdatePipelineState)
        } else {
            computeEncoder.setComputePipelineState(condenseTrianglesPipelineState)
        }
        computeEncoder.setBuffer(renderTriangleIDBuffer,    offset: 0, index: 0)
        computeEncoder.setBuffer(occlusionTriangleIDBuffer, offset: 0, index: 1)
        computeEncoder.dispatchThreadgroups([ numTriangle8Groups ], threadsPerThreadgroup: 1)
        
        computeEncoder.popOptDebugGroup()
        computeEncoder.endEncoding()

        commandBuffer.commit()
    }
    
}
