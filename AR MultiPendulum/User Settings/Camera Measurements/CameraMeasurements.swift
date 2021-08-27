//
//  CameraMeasurements.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/11/21.
//

import ARKit
import UIKit
import DeviceKit

final class CameraMeasurements: DelegateUserSettings {
    var userSettings: UserSettings
    
    enum ModifiedPerspectiveAdjustMode {
        case none
        case move
        case start
    }
    
    var modifiedPerspectiveAdjustMode: ModifiedPerspectiveAdjustMode = .none
    
    var deviceSize: simd_double3
    var screenSize: simd_double2
    var wideCameraOffset: simd_double3
    
    var cameraSpaceScreenCenter: simd_double3
    var cameraToScreenAspectRatioMultiplier: Float
    
    var cameraToWorldTransform = simd_float4x4(1)
    var worldToCameraTransform = simd_float4x4(1)
    var modifiedPerspectiveToWorldTransform = simd_float4x4(1)
    var worldToModifiedPerspectiveTransform = simd_float4x4(1)
    
    var worldToScreenClipTransform = simd_float4x4(1)
    var worldToMixedRealityCullTransform = simd_float4x4(1)
    var worldToLeftClipTransform = simd_float4x4(1)
    var worldToRightClipTransform = simd_float4x4(1)
    
    var handheldEyePosition: simd_float3 {
        simd_make_float3(usingModifiedPerspective ? modifiedPerspectiveToWorldTransform[3] : cameraToWorldTransform[3])
    }
    
    var modifiedPerspectivePosition: simd_float3!
    var cameraSpaceRotationCenter = simd_float3.zero
    var cameraSpaceHeadPosition = simd_float3.zero
    var leftEyePosition = simd_float3.zero
    var rightEyePosition = simd_float3.zero
    
    var cameraSpaceLeftEyePosition = simd_float3.zero
    var cameraSpaceRightEyePosition = simd_float3.zero
    var cameraSpaceBetweenEyesPosition = simd_float3.zero
    var cameraSpaceMixedRealityCullOrigin = simd_float3.zero
    
    var headsetProjectionTransform: simd_float4x4!
    var cameraToLeftClipTransform = simd_float4x4(1)
    var cameraToRightClipTransform = simd_float4x4(1)
    var cameraToMixedRealityCullTransform = simd_float4x4(1)
    
    var cameraPlaneWidthSum: Double = 0
    var cameraPlaneWidthSampleCount: Int = -12
    var currentPixelWidth: Double = 0
    
    init(userSettings: UserSettings, library: MTLLibrary) {
        self.userSettings = userSettings
        
        var device = Device.current
        let possibleDeviceSize = device.deviceSize
        
        let nativeBounds = UIScreen.main.nativeBounds
        let screenBounds = CGSize(width: nativeBounds.height, height: nativeBounds.width)
        cameraToScreenAspectRatioMultiplier = Float((4.0 / 3) * screenBounds.height / screenBounds.width)
        
        if possibleDeviceSize == nil, UIDevice.current.userInterfaceIdiom == .phone {
            var device: FutureDevice
            
            if screenBounds.width >= 2778 || screenBounds.height >= 1284 {
                device = .iPhone13ProMax
            } else if screenBounds.width >= 2532 || screenBounds.height >= 1170 {
                if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                    device = .iPhone13Pro
                } else {
                    device = .iPhone13
                }
            } else if screenBounds.width >= 2340 || screenBounds.height >= 1080 {
                device = .iPhone13Mini
            } else {
                device = .iPhoneSE3
            }
            
            deviceSize = device.deviceSize
            screenSize = device.screenSize
            wideCameraOffset = device.wideCameraOffset
        } else {
            if let possibleDeviceSize = possibleDeviceSize {
                deviceSize = possibleDeviceSize
            } else {
                if screenBounds.width >= 2732 || screenBounds.height >= 2048 {
                    device = .iPadPro12Inch5
                } else if screenBounds.width >= 2388 || screenBounds.height >= 1668 {
                    device = .iPadPro11Inch3
                } else if screenBounds.width >= 2360 || screenBounds.height >= 1640 {
                    device = .iPadAir4
                } else if screenBounds.width >= 2160 || screenBounds.height >= 1620 {
                    device = .iPad8
                } else {
                    device = .iPadMini5
                }
                
                deviceSize = device.deviceSize
            }
            
            screenSize = device.screenSize
            wideCameraOffset = device.wideCameraOffset
        }
        
        cameraSpaceScreenCenter = simd_double3(fma(simd_double2(deviceSize.x, deviceSize.y), [0.5, -0.5],
                                                   simd_double2(-wideCameraOffset.x, wideCameraOffset.y)), wideCameraOffset.z)
    }
}
