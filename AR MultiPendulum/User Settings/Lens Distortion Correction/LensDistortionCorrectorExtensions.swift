//
//  LensDistortionCorrectorExtensions.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/10/21.
//

import Metal
import simd

extension LensDistortionCorrector {
    
    func updateIntermediateTexture() {
        let intermediateSideLength_f = round(Float(viewSideLength) * Float(1 + storedSettings.k1 + storedSettings.k2))
        intermediateSideLength = Int(intermediateSideLength_f)
        
        if usingVRR {
            if mutabilityState == .permanent {
                shouldCreateNewPipeline = true
                shouldUseCurrentPipeline = false
            } else {
                updatedIntermediateTextureDuringTemporaryState = true
            }
            
            let sampleCount = cameraMeasurements.cameraPlaneWidthSampleCount
            var cameraPlaneWidth: Double
            
            if sampleCount >= 24 {
                cameraPlaneWidth = cameraMeasurements.cameraPlaneWidthSum / Double(sampleCount)
            } else {
                cameraPlaneWidth = 2 * tan(degreesToRadians(64.5) * 0.5)
            }
            
            let cameraPlaneWidth_half = cameraPlaneWidth * 0.5
            let headsetFOV_half = storedSettings.headsetFOV * 0.5
            
            let headsetPlaneWidth_half = tan(degreesToRadians(headsetFOV_half))
            let cameraPlaneWidthProportion = min(1, cameraPlaneWidth_half / headsetPlaneWidth_half)
            
            let fullRateProportionX = Float(cameraPlaneWidthProportion)
            let fullRateProportionY = Float(cameraPlaneWidthProportion * 0.75)
            
            vrrMap = createVRRMap(fullRateProportionX: fullRateProportionX, fullRateProportionY: fullRateProportionY)
            
            let vrrTextureSize = vrrMap.physicalSize(layer: 0)
            intermediateTextureDimensions = .init(vrrTextureSize.width, vrrTextureSize.height)
            intermediateResolutionCompressionRatio = 1
            
            let vrrMapSize = roundUpToPowerOf2(vrrMap.parameterDataSizeAndAlign.size)
            ensureBufferCapacity(type: .uniforms, capacity: vrrMapSize)
            
            vrrMapIndex = (vrrMapIndex == Renderer.numRenderBuffers - 1) ? 0 : vrrMapIndex + 1
        } else {
            let compressedSideLength = Int(intermediateSideLength_f * 0.85)
            intermediateTextureDimensions = .init(repeating: compressedSideLength)
            intermediateResolutionCompressionRatio = Float(compressedSideLength) / intermediateSideLength_f
        }
        
        ensureTextureCapacity()
    }
    
}

extension LensDistortionCorrector: BufferExpandable {
    
    enum BufferType {
        case uniforms
    }
    
    func ensureBufferCapacity(type: BufferType, capacity: Int) {
        let newCapacity = roundUpToPowerOf2(capacity)
        
        switch type {
        case .uniforms: uniformBuffer.ensureCapacity(device: device, capacity: newCapacity)
        }
    }
    
    func ensureTextureCapacity() {
        guard mixedRealityResolveTexture == nil ||
              mixedRealityResolveTexture.width  != intermediateTextureDimensions.x ||
              mixedRealityResolveTexture.height != intermediateTextureDimensions.y else {
            return
        }
        
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.width  = intermediateTextureDimensions.x
        textureDescriptor.height = intermediateTextureDimensions.y
        
        textureDescriptor.usage = .renderTarget
        textureDescriptor.storageMode = .memoryless
        textureDescriptor.sampleCount = 4
        
        // Metal API validation throws an error when a multisample-array texture
        // is created with the memoryless storage mode. However, the Metal
        // runtime throws an error when a multisample-array texture is
        // created with anything besides memoryless on older devices.
        //
        // To solve this problem, a multisample texture with a single layer
        // is used on pre-A14 devices, as the rendering is already
        // split up into two separate render passes and thus does
        // not need to render to two multisample layers at once.
        
        if usingVertexAmplification {
            onlyForMetalAPIValidation { textureDescriptor.storageMode = .private }
            textureDescriptor.arrayLength = 2
            textureDescriptor.textureType = .type2DMultisampleArray
        } else {
            textureDescriptor.textureType = .type2DMultisample
        }
        
        textureDescriptor.pixelFormat = .depth32Float_stencil8
        mixedRealityDepthStencilTexture = device.makeTexture(descriptor: textureDescriptor)!
        mixedRealityDepthStencilTexture.optLabel = "Mixed Reality Depth-Stencil Texture"
        
        textureDescriptor.pixelFormat = .rg11b10Float
        mixedRealityMSAATexture = device.makeTexture(descriptor: textureDescriptor)!
        mixedRealityMSAATexture.optLabel = "Mixed Reality MSAA Texture"
        
        if !usingVertexAmplification {
            textureDescriptor.arrayLength = 2
        }
        
        textureDescriptor.storageMode = .private
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        textureDescriptor.textureType = .type2DArray
        textureDescriptor.sampleCount = 1
        mixedRealityResolveTexture = device.makeTexture(descriptor: textureDescriptor)!
        mixedRealityResolveTexture.optLabel = "Mixed Reality Resolve Texture"
    }
    
}
