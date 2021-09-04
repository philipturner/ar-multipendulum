//
//  RendererExtensions.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 6/11/21.
//

import MetalPerformanceShaders
import ARKit

protocol GeometryRenderer {
    func drawGeometry(renderEncoder: MTLRenderCommandEncoder, threadID: Int)
}

protocol BufferExpandable {
    associatedtype BufferType
    func ensureBufferCapacity(type: Self.BufferType, capacity: Int)
}

extension BufferExpandable {
    func ensureBufferCapacity<T: FixedWidthInteger>(type: Self.BufferType, capacity: T) {
        ensureBufferCapacity(type: type, capacity: Int(capacity))
    }
}

extension Renderer: GeometryRenderer {
    
    func updateResources(frame: ARFrame) {
        if coordinator.settingsAreShown {
            if timeSinceSettingsOpenAnimationStart < 0 {
                timeSinceSettingsOpenAnimationStart = 0
            } else {
                timeSinceSettingsOpenAnimationStart += 1
            }
        } else {
            timeSinceSettingsOpenAnimationStart = .min
        }
        
        shouldRenderToDisplay = timeSinceSettingsOpenAnimationStart < Int(MainSettingsView.openAnimationDuration * 60 * 2)
        
        if coordinator.showingAppTutorial, showingFirstAppTutorial {
            shouldRenderToDisplay = false
        } else {
            showingFirstAppTutorial = false
        }
        
        
        
        if !coordinator.settingsShouldBeAnimated {
            coordinator.settingsShouldBeAnimated = true
        }
        
        var renderingSettings: RenderingSettings { coordinator.renderingSettings }
        doingMixedRealityRendering = renderingSettings.doingMixedRealityRendering
        usingModifiedPerspective = renderingSettings.usingModifiedPerspective
        
        if UIDevice.current.userInterfaceIdiom != .phone {
            doingMixedRealityRendering = false
        }
        
        userSettings.updateResources()
        
        var storedSettings: UserSettings.StoredSettings { userSettings.storedSettings }
        allowingSceneReconstruction = storedSettings.allowingSceneReconstruction
        allowingHandReconstruction = storedSettings.allowingHandReconstruction
        
        asyncUpdateTextures(frame: frame)
        updateUniforms(frame: frame)
        
        if usingLiDAR, allowingSceneReconstruction {
            sceneRenderer.asyncUpdateResources(frame: frame)
        } else {
            sceneRenderer2D.asyncUpdateResources()
        }
        
        centralRenderer.initializeFrameData()
        updateInteractionRay(frame: frame)
        
        
        
        pendulumRenderer.updateResources()
        userSettings.lensDistortionCorrector.updateResources()
        
        if shouldRenderToDisplay {
            pendulumRenderer.meshConstructor.updateResources()
            interfaceRenderer.updateResources()
            centralRenderer.updateResources()
        }
        
        if pendingTap != nil {
            tapAlreadyStarted = true
        }
        
        pendingTap = nil
    }
    
    func drawGeometry(renderEncoder: MTLRenderCommandEncoder, threadID: Int = 0) {
        interfaceRenderer.drawOpaqueGeometry(renderEncoder: renderEncoder, threadID: threadID)
        
        renderEncoder.setDepthStencilState(depthStencilState)
        pendulumRenderer.drawGeometry(renderEncoder: renderEncoder, threadID: threadID)
        centralRenderer.drawGeometry(renderEncoder: renderEncoder, threadID: threadID)
        
        if usingLiDAR, allowingSceneReconstruction {
            sceneRenderer.updateResourcesSemaphore.wait()
            sceneRenderer.drawGeometry(renderEncoder: renderEncoder, threadID: threadID)
        } else {
            sceneRenderer2D.updateResourcesSemaphore.wait()
            sceneRenderer2D.drawGeometry(renderEncoder: renderEncoder, threadID: threadID)
        }
        
        interfaceRenderer.drawTransparentGeometry(renderEncoder: renderEncoder, threadID: threadID)
    }
    
    func asyncUpdateTextures(frame: ARFrame) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            @inline(never)
            func fallbackCreateTexture(_ pixelBuffer: CVPixelBuffer, to reference: inout MTLTexture!, _ label: String,
                                       _ pixelFormat: MTLPixelFormat, _ width: Int, _ height: Int, _ planeIndex: Int = 0)
            {
                reference = textureCache.createMTLTexture(pixelBuffer, pixelFormat,
                                                          CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex),
                                                          CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex), planeIndex)
                
                guard reference != nil else {
                    usleep(10_000)
                    return
                }
                
                if usingLiDAR {
                    let commandBuffer = commandQueue.makeDebugCommandBuffer()
                    let kernel = MPSNNResizeBilinear(device: device, resizeWidth: width, resizeHeight: height, alignCorners: false)
                    
                    let textureDescriptor = MTLTextureDescriptor()
                    textureDescriptor.width = width
                    textureDescriptor.height = height
                    textureDescriptor.pixelFormat = pixelFormat
                    textureDescriptor.usage = [.shaderRead, .shaderWrite]
                    let output = device.makeTexture(descriptor: textureDescriptor)!
                    
                    let numFeatureChannels: Int = {
                        switch pixelFormat {
                        case .r8Unorm:  return 1
                        case .r32Float: return 1
                        case .rg8Unorm: return 2
                        default: fatalError("This case should never happen!")
                        }
                    }()
                    
                    let sourceImage = MPSImage(texture: reference, featureChannels: numFeatureChannels)
                    let destinationImage = MPSImage(texture: output, featureChannels: numFeatureChannels)
                    
                    kernel.encode(commandBuffer: commandBuffer, sourceImage: sourceImage,
                                  destinationImage: destinationImage)
                    commandBuffer.commit()
                    
                    reference = destinationImage.texture
                }
            }
            
            @inline(__always)
            func bind(_ pixelBuffer: CVPixelBuffer?, to reference: inout MTLTexture!, _ label: String,
                      _ pixelFormat: MTLPixelFormat, _ width: Int, _ height: Int, _ planeIndex: Int = 0)
            {
                guard let pixelBuffer = pixelBuffer else {
                    reference = nil
                    return
                }
                
                reference = textureCache.createMTLTexture(pixelBuffer, pixelFormat, width, height, planeIndex)
                
                while reference == nil {
                    fallbackCreateTexture(pixelBuffer, to: &reference, label, pixelFormat, width, height, planeIndex)
                }
                
                reference.optLabel = label
            }
            
            if usingLiDAR, allowingHandReconstruction || allowingSceneReconstruction {
                bind(frame.segmentationBuffer, to: &segmentationTexture, "Segmentation Texture", .r8Unorm, 256, 192)
                bind(frame.sceneDepth?.depthMap, to: &sceneDepthTexture, "Scene Depth Texture", .r32Float, 256, 192)
                
                if allowingHandReconstruction {
                    handRenderer.segmentationTextureSemaphore.signal()
                }
                
                if allowingSceneReconstruction {
                    sceneRenderer.segmentationTextureSemaphore.signal()
                }
            }
            
            bind(frame.capturedImage, to: &colorTextureY,    "Color Texture (Y)",    .r8Unorm, 1920, 1440)
            bind(frame.capturedImage, to: &colorTextureCbCr, "Color Texture (CbCr)", .rg8Unorm, 960,  720, 1)
            
            if usingLiDAR {
                if allowingHandReconstruction {
                    handRenderer.colorTextureSemaphore.signal()
                }
                
                if allowingSceneReconstruction {
                    sceneRenderer.colorTextureSemaphore.signal()
                } else {
                    sceneRenderer2D.colorTextureSemaphore.signal()
                }
            } else {
                sceneRenderer2D.colorTextureSemaphore.signal()
            }
        }
    }
    
    func updateUniforms(frame: ARFrame) {
        renderIndex = (renderIndex == Renderer.numRenderBuffers - 1) ? 0 : renderIndex + 1
        
        timeSinceLastTap += 1
        timeSinceCurrentTap += 1
        
        if !usingModifiedPerspective {
            alreadyStartedUsingModifiedPerspective = false
        }
        
        if pendingTap == nil {
            tapAlreadyStarted = false
        } else if !tapAlreadyStarted {
            timeSinceLastTap = timeSinceCurrentTap
            timeSinceCurrentTap = 0
            
            if usingModifiedPerspective, alreadyStartedUsingModifiedPerspective,
               timeSinceLastTap - timeSinceCurrentTap < 30, !lastTapDirectionWasSwitch
            {
                flyingDirectionIsForward = !flyingDirectionIsForward
                lastTapDirectionWasSwitch = true
            } else {
                lastTapDirectionWasSwitch = false
            }
        } else {
            if usingModifiedPerspective, alreadyStartedUsingModifiedPerspective {
                if timeSinceCurrentTap >= 30 {
                    cameraMeasurements.modifiedPerspectiveAdjustMode = .move
                }
            }
        }
        
        if usingModifiedPerspective {
            if !alreadyStartedUsingModifiedPerspective {
                alreadyStartedUsingModifiedPerspective = true
                
                cameraMeasurements.modifiedPerspectiveAdjustMode = .start
            }
        }
        
        let lightEstimate = frame.lightEstimate!
        let convertedColor = kelvinToRGB(Double(lightEstimate.ambientColorTemperature))
        let ambientIntensity = Float(lightEstimate.ambientIntensity) * (0.6 / 1000)
        
        ambientLightColor     = simd_half3(convertedColor * ambientIntensity)
        directionalLightColor = simd_half3(simd_float3(repeating: ambientIntensity))
        
        cameraMeasurements.updateResources(frame: frame)
    }
    
    private func updateInteractionRay(frame: ARFrame) {
        if userSettings.storedSettings.usingHandForSelection {
            if usingLiDAR, allowingHandReconstruction {
                handRenderer.updateResources(frame: frame)
                interactionRay = handRenderer.handRay
            } else {
                handRenderer2D.updateResources(frame: frame)
                interactionRay = handRenderer2D.handRay
                
                if let interactionRay = interactionRay, userSettings.storedSettings.showingHandPosition {
                    let direction = normalize(interactionRay.direction)
                    let handPositionDistance = pendulumRenderer.pendulumInterface.interfaceDepth
                    let handPosition = fma(direction, handPositionDistance, interactionRay.origin)
                    
                    var handPositionObject = CentralObject(shapeType: .sphere,
                                                           position: handPosition,
                                                           scale: [0.017, 0.017, 0.017],
                                                           
                                                           color: [0.9, 0.9, 0.9])
                    
                    centralRenderer.append(object: &handPositionObject)
                }
            }
        } else {
            if usingLiDAR, allowingHandReconstruction {
                handRenderer.updateResources(frame: frame)
            }
            
            var rayOrigin: simd_float3
            
            if doingMixedRealityRendering {
                let headPosition = simd_float4(cameraMeasurements.cameraSpaceHeadPosition, 1)
                rayOrigin = simd_make_float3(cameraMeasurements.cameraToWorldTransform * headPosition)
            } else {
                rayOrigin = simd_make_float3(cameraMeasurements.cameraToWorldTransform[3])
            }
            
            let rayDirection = -simd_make_float3(cameraMeasurements.cameraToWorldTransform[2])
            interactionRay = .init(origin: rayOrigin, direction: rayDirection)
        }
        
        if usingModifiedPerspective {
            interactionRay = nil
        }
    }
    
}
