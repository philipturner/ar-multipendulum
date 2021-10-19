//
//  LensDistortionCorrectionExecution.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/10/21.
//

import Metal
import simd

extension LensDistortionCorrector {
    
    // NOTE: VR headset parameter fine-tuning will be implemented
    // through a holographic augmented reality interface a future release.
    
    func updateResources() {
        if !waitingOnInitialCameraMeasurements {
            timeSinceLastIntermediateTextureUpdate += 1
        }
        
        if !doingMixedRealityRendering || !pendingStoredSettings.viewportMatches(storedSettings) {
            framebufferReferences.removeAll(keepingCapacity: true)
        }
        
        if mutabilityState == .permanent {
            if pendingStoredSettings != storedSettings {
                shouldSaveSettings = true
            }
            
            if !savingSettings, shouldSaveSettings {
                let pendingStoredSettingsCopy = pendingStoredSettings
                savingSettings = true
                shouldSaveSettings = false
                
                DispatchQueue.global(qos: .background).async {
                    Self.saveSettings(pendingStoredSettingsCopy)
                    self.savingSettings = false
                }
            }
            
            if !updatingLensDistortionPipeline, justCreatedNewPipeline {
                justCreatedNewPipeline = false
                if !shouldCreateNewPipeline { shouldUseCurrentPipeline = true }
                
                optimizedCorrectLensDistortionPipelineState = newOptimizedCorrectLensDistortionPipelineState
            }
        }
        
        storedSettings = pendingStoredSettings
        
        
        
        if waitingOnInitialCameraMeasurements, cameraMeasurements.cameraPlaneWidthSampleCount >= 24 {
            waitingOnInitialCameraMeasurements = false
            updatingIntermediateTexture = true
        }
        
        if updatingIntermediateTexture, doingMixedRealityRendering {
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                updateIntermediateTexture()
                intermediateTextureUpdateSemaphore.signal()
            }
            
            if mutabilityState == .permanent {
                timeSinceLastIntermediateTextureUpdate = 0
            }
        }
        
        if mutabilityState == .permanent, timeSinceLastIntermediateTextureUpdate >= 1 {
            assert(!waitingOnInitialCameraMeasurements)
            
            if shouldCreateNewPipeline {
                updatingLensDistortionPipeline = true
                
                DispatchQueue.global(qos: .utility).async { [self] in
                    createOptimizedLensDistortionPipeline()
                    
                    justCreatedNewPipeline = true
                    updatingLensDistortionPipeline = false
                }
                
                shouldCreateNewPipeline = false
                shouldUseCurrentPipeline = false
            }
        }
    }
    
    func doRenderPass(commandBuffer: MTLCommandBuffer) {
        if updatingIntermediateTexture {
            updatingIntermediateTexture = false
            intermediateTextureUpdateSemaphore.wait()
            
            vrrMap?.copyParameterData(buffer: uniformBuffer, level: .vrrMap, offset: vrrMapOffset)
        }
        
        if userSettings.shouldRenderToDisplay {
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = mixedRealityMSAATexture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].storeAction = .multisampleResolve
            renderPassDescriptor.colorAttachments[0].resolveTexture = mixedRealityResolveTexture
            renderPassDescriptor.depthAttachment.texture = mixedRealityDepthStencilTexture
            renderPassDescriptor.depthAttachment.clearDepth = 0
            renderPassDescriptor.stencilAttachment.texture = mixedRealityDepthStencilTexture
            renderPassDescriptor.rasterizationRateMap = vrrMap
            
            if renderer.interfaceRenderer.numRenderedElements == 0 {
                renderPassDescriptor.stencilAttachment.loadAction = .dontCare
            }
            
            var renderEncoder: MTLRenderCommandEncoder
            
            @inline(__always)
            func setEyeDeltas(_ renderEncoder: MTLRenderCommandEncoder) {
                var eyeDirectionDelta = cameraMeasurements.rightEyePosition - cameraMeasurements.leftEyePosition
                renderEncoder.setVertexBytes(&eyeDirectionDelta, length: 16, index: 28)
                
                var positionDelta = cameraMeasurements.worldToRightClipTransform[3].x
                                  - cameraMeasurements.worldToLeftClipTransform[3].x
                renderEncoder.setVertexBytes(&positionDelta, length: 4, index: 29)
            }
            
            if usingVertexAmplification {
                renderPassDescriptor.renderTargetArrayLength = 2
                
                renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
                renderEncoder.optLabel = "Render Pass"
                renderEncoder.setVertexAmplificationCount(2, viewMappings: nil)
            } else {
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    let commandBuffer = renderer.commandQueue.makeDebugCommandBuffer()
                    commandBuffer.optLabel = "Render Command Buffer (Right)"
                    
                    let renderPassDescriptorCopy = renderPassDescriptor.copy() as! MTLRenderPassDescriptor
                    renderPassDescriptorCopy.colorAttachments[0].resolveSlice = 1
                    
                    let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptorCopy)!
                    renderEncoder.optLabel = "Render Pass (Right)"
                    renderEncoder.setFrontFacing(.counterClockwise)
                    
                    var amplificationID = 1
                    renderEncoder.setVertexBytes(&amplificationID, length: 2, index: 30)
                    
                    setEyeDeltas(renderEncoder)
                    renderer.drawGeometry(renderEncoder: renderEncoder, threadID: 1)
                    renderEncoder.endEncoding()
                    
                    commandBuffer.commit()
                    renderingCoordinationSemaphore.signal()
                }
                
                renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
                renderEncoder.optLabel = "Render Pass (Left)"
                
                var amplificationID = 0
                renderEncoder.setVertexBytes(&amplificationID, length: 2, index: 30)
            }
            
            renderEncoder.setFrontFacing(.counterClockwise)
            
            setEyeDeltas(renderEncoder)
            renderer.drawGeometry(renderEncoder: renderEncoder)
            renderEncoder.endEncoding()
            
            
            
            if usingVRR {
                let blitEncoder = commandBuffer.makeBlitCommandEncoder()!
                blitEncoder.optLabel = "Render Pass - Fill Missing Pixels from VRR"
                
                var sourceOrigin      = MTLOriginMake(Int(intermediateTextureDimensions.x - 2), 0, 0)
                var destinationOrigin = MTLOriginMake(                     sourceOrigin.x + 1,  0, 0)
                var sourceSize: MTLSize = [ 1, Int(intermediateTextureDimensions.y - 1) ]
                
                @inline(__always)
                func fillEdges() {
                    for i in 0..<2 {
                        blitEncoder.copy(from: mixedRealityResolveTexture, sourceSlice: i,
                                         sourceLevel: 0, sourceOrigin: sourceOrigin, sourceSize: sourceSize,
                                         
                                         to: mixedRealityResolveTexture, destinationSlice: i,
                                         destinationLevel: 0, destinationOrigin: destinationOrigin)
                    }
                }
                
                fillEdges()
                
                sourceOrigin      = MTLOriginMake(0, Int(intermediateTextureDimensions.y - 2), 0)
                destinationOrigin = MTLOriginMake(0,                      sourceOrigin.y + 1,  0)
                sourceSize = [ Int(intermediateTextureDimensions.x), 1 ]
                
                fillEdges()
                
                blitEncoder.endEncoding()
            }
        }
        
        
        
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.optLabel = "Correct Lens Distortion"
        
        let drawable = renderer.view.currentDrawable!
        computeEncoder.setTexture(mixedRealityResolveTexture, index: 0)
        computeEncoder.setTexture(drawable.texture,           index: 1)
        
        let shouldClear = !framebufferReferences.contains(where: { $0 === drawable.texture })
        var lensDistortionUniforms = LensDistortionUniforms(corrector: self, clearingFramebuffer: shouldClear)
        computeEncoder.setBytes(&lensDistortionUniforms, length: MemoryLayout<LensDistortionUniforms>.stride, index: 0)
        
        if shouldClear {
            framebufferReferences.append(drawable.texture)
            
            computeEncoder.setComputePipelineState(clearFramebufferPipelineState)
            
            if usingThreadgroups {
                computeEncoder.dispatchThreads(clearFramebufferDispatchSize, threadsPerThreadgroup: [16, 16])
            } else {
                computeEncoder.dispatchThreadgroups(clearFramebufferDispatchSize, threadsPerThreadgroup: 1)
            }
        }
        
        if shouldClear || userSettings.shouldRenderToDisplay {
            if mutabilityState == .permanent ? shouldUseCurrentPipeline : !updatedIntermediateTextureDuringTemporaryState,
               let optimizedCorrectLensDistortionPipelineState = optimizedCorrectLensDistortionPipelineState {
                computeEncoder.setComputePipelineState(optimizedCorrectLensDistortionPipelineState)
            } else {
                computeEncoder.setComputePipelineState(genericCorrectLensDistortionPipelineState)
                
                if usingVRR {
                    computeEncoder.setBuffer(uniformBuffer, level: .vrrMap, offset: vrrMapOffset, index: 1)
                }
            }
            
            if usingThreadgroups {
                computeEncoder.dispatchThreads(correctLensDistortionDispatchSize, threadsPerThreadgroup: [16, 16])
            } else {
                computeEncoder.dispatchThreadgroups(correctLensDistortionDispatchSize, threadsPerThreadgroup: 1)
            }
        }
        
        computeEncoder.endEncoding()
        commandBuffer.present(drawable)
        
        if !usingVertexAmplification, userSettings.shouldRenderToDisplay {
            renderingCoordinationSemaphore.wait()
        }
    }
    
}
