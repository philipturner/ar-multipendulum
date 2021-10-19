//
//  CameraMeasurementsExtensions.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/11/21.
//

import Metal
import ARKit

extension CameraMeasurements {
    
    func updateResources(frame: ARFrame) {
        currentPixelWidth = simd_fast_recip(Double(frame.camera.intrinsics[0][0]))
        cameraPlaneWidthSampleCount += 1
        
        if cameraPlaneWidthSampleCount > 0 {
            cameraPlaneWidthSum = fma(Double(imageResolution.width), currentPixelWidth, cameraPlaneWidthSum)
        }
        
        var headsetProjectionScale: Float!
        
        var pendingStoredSettings: LensDistortionCorrector.StoredSettings { lensDistortionCorrector.pendingStoredSettings }
        var storedSettings: LensDistortionCorrector.StoredSettings { lensDistortionCorrector.storedSettings }
        
        @inline(__always)
        func generateHeadsetProjectionScale() {
            let headsetPlaneSize = tan(degreesToRadians(pendingStoredSettings.headsetFOV) * 0.5)
            headsetProjectionScale = Float(simd_fast_recip(headsetPlaneSize))
        }
        
        if !pendingStoredSettings.eyePositionMatches(storedSettings) || headsetProjectionTransform == nil {
            let cameraSpaceHeadsetOrigin = simd_float3(.init(
                (deviceSize.x * 0.5) - wideCameraOffset.x,
                -deviceSize.y + wideCameraOffset.y - pendingStoredSettings.caseThickness,
                wideCameraOffset.z + pendingStoredSettings.caseProtrusionDepth
            ))
            
            let bezelSize = (deviceSize.y - screenSize.y) * 0.5
            let viewCenterToMiddleDistance = pendingStoredSettings.eyeOffsetX
            let viewCenterToBottomDistance = pendingStoredSettings.eyeOffsetY - bezelSize - pendingStoredSettings.caseThickness
            
            let pixelsPerMeter = lensDistortionCorrector.pixelsPerMeter
            lensDistortionCorrector.viewCenterToMiddleDistance = Int(viewCenterToMiddleDistance * pixelsPerMeter)
            lensDistortionCorrector.viewCenterToBottomDistance = Int(viewCenterToBottomDistance * pixelsPerMeter)
            
            var viewSideLength = ~1 & (Int(round(pendingStoredSettings.viewportDiameter * pixelsPerMeter)) + 1)
            viewSideLength = min(2048, viewSideLength)
            lensDistortionCorrector.viewSideLength = viewSideLength
            
            let viewTopToBottomDistance = viewSideLength >> 1 + lensDistortionCorrector.viewCenterToBottomDistance
            let dispatchSizeY = min(viewSideLength, viewTopToBottomDistance)
            lensDistortionCorrector.correctLensDistortionDispatchSize = [ viewSideLength, dispatchSizeY ]
            
            var headsetSpaceEyePosition = simd_float3(.init(
                pendingStoredSettings.eyeOffsetX,
                pendingStoredSettings.eyeOffsetY,
                pendingStoredSettings.eyeOffsetZ
            ))
            
            cameraSpaceRightEyePosition = cameraSpaceHeadsetOrigin + headsetSpaceEyePosition
            
            headsetSpaceEyePosition.x = -headsetSpaceEyePosition.x
            var cameraSpaceEyePosition = cameraSpaceHeadsetOrigin + headsetSpaceEyePosition
            cameraSpaceLeftEyePosition = cameraSpaceEyePosition
            
            
            
            cameraSpaceEyePosition.x = cameraSpaceHeadsetOrigin.x
            cameraSpaceBetweenEyesPosition = cameraSpaceEyePosition
            
            generateHeadsetProjectionScale()
            cameraSpaceEyePosition.z = fma(headsetProjectionScale, -headsetSpaceEyePosition.x, cameraSpaceEyePosition.z)
            cameraSpaceMixedRealityCullOrigin = cameraSpaceEyePosition
        }
        
        if !pendingStoredSettings.intermediateTextureMatches(storedSettings) || headsetProjectionTransform == nil {
            if headsetProjectionTransform != nil {
                lensDistortionCorrector.updatingIntermediateTexture = true
            }
            
            if headsetProjectionScale == nil { generateHeadsetProjectionScale() }
            headsetProjectionTransform = matrix4x4_perspective(xs: headsetProjectionScale,
                                                               ys: headsetProjectionScale, nearZ: 1000, farZ: 0.001)
        }
        
        if headsetProjectionScale != nil {
            cameraToLeftClipTransform         = headsetProjectionTransform.prependingTranslation(-cameraSpaceLeftEyePosition)
            cameraToRightClipTransform        = headsetProjectionTransform.prependingTranslation(-cameraSpaceRightEyePosition)
            cameraToMixedRealityCullTransform = headsetProjectionTransform.prependingTranslation(-cameraSpaceMixedRealityCullOrigin)
        }
        
        
        
        cameraToWorldTransform = frame.camera.transform
        worldToCameraTransform = cameraToWorldTransform.inverseRotationTranslation
        
        if doingMixedRealityRendering {
            cameraSpaceRotationCenter = cameraSpaceBetweenEyesPosition
            cameraSpaceRotationCenter.z += 0.023
            cameraSpaceHeadPosition = cameraSpaceRotationCenter
        } else {
            cameraSpaceRotationCenter = simd_float3(cameraSpaceScreenCenter + .init(0, 0, 0.25))
            cameraSpaceHeadPosition = [0, 0, 0]
        }
        
        if usingModifiedPerspective {
            switch modifiedPerspectiveAdjustMode {
            case .none:
                break
            case .move:
                let delta = cameraToWorldTransform[2] * (renderer.flyingDirectionIsForward ? -1.0 / 60 : 1.0 / 60)
                modifiedPerspectivePosition += simd_make_float3(delta)
            case .start:
                modifiedPerspectivePosition = simd_make_float3(cameraToWorldTransform * .init(cameraSpaceRotationCenter, 1))
            }
            
            modifiedPerspectiveAdjustMode = .none
            
            modifiedPerspectiveToWorldTransform = cameraToWorldTransform.replacingTranslation(with: modifiedPerspectivePosition)
            modifiedPerspectiveToWorldTransform = modifiedPerspectiveToWorldTransform.prependingTranslation(-cameraSpaceRotationCenter)
            
            worldToModifiedPerspectiveTransform = modifiedPerspectiveToWorldTransform.inverseRotationTranslation
        } else {
            modifiedPerspectivePosition = nil
        }
        
        let worldToCameraTransform = usingModifiedPerspective ? worldToModifiedPerspectiveTransform
                                                              : self.worldToCameraTransform
        
        if doingMixedRealityRendering {
            worldToMixedRealityCullTransform = cameraToMixedRealityCullTransform * worldToCameraTransform
            worldToLeftClipTransform         = cameraToLeftClipTransform         * worldToCameraTransform
            worldToRightClipTransform        = cameraToRightClipTransform        * worldToCameraTransform
            
            let cameraToWorldTransform = usingModifiedPerspective ? modifiedPerspectiveToWorldTransform
                                                                  : self.cameraToWorldTransform
            
            leftEyePosition  = simd_make_float3(cameraToWorldTransform * .init(cameraSpaceLeftEyePosition,  1))
            rightEyePosition = simd_make_float3(cameraToWorldTransform * .init(cameraSpaceRightEyePosition, 1))
        } else {
            var screenProjectionTransform = frame.camera.projectionMatrix(for: .landscapeRight,
                                                                          viewportSize: imageResolution,
                                                                          zNear: 1000, zFar: 0.001)
            screenProjectionTransform[0] *= cameraToScreenAspectRatioMultiplier
            
            worldToScreenClipTransform = screenProjectionTransform * worldToCameraTransform
        }
    }
    
}
