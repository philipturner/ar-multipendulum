//
//  FutureDeviceMeasurements.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/10/21.
//

import DeviceKit
import simd

// Estimates of measurements for devices that may be
// released before the app updates to account for them

enum FutureDevice: DeviceMeasurementProvider {
    case iPhone13Mini
    case iPhone13
    case iPhone13Pro
    case iPhone13ProMax
    case iPhoneSE3
    
    var closestDevice: Device {
        switch self {
        case .iPhone13Mini:   return .iPhone12Mini
        case .iPhone13:       return .iPhone12
        case .iPhone13Pro:    return .iPhone12Pro
        case .iPhone13ProMax: return .iPhone12ProMax
        case .iPhoneSE3:      return .iPhoneSE2
        }
    }
    
    var deviceSize: simd_double3! {
        switch self {
        case .iPhone13Mini:   return [131.50, 64.21, 7.65]
        case .iPhone13:       return [146.71, 71.52, 7.65]
        case .iPhone13Pro:    return [146.71, 71.52, 7.65]
        case .iPhone13ProMax: return [160.84, 78.07, 7.65]
        case .iPhoneSE3:      return [138.44, 67.27, 7.31]
        }
    }
    
    var screenSize: simd_double2! {
        switch self {
        case .iPhone13Mini:   return [124.96, 57.67]
        case .iPhone13:       return [139.77, 64.58]
        case .iPhone13Pro:    return [139.77, 64.58]
        case .iPhone13ProMax: return [153.90, 71.13]
        case .iPhoneSE3:      return [104.05, 58.50]
        }
    }
    
    var isFullScreen: Bool! { true }
    
    var wideCameraOffset: simd_double3! {
        switch self {
        case .iPhone13Mini:   return [24.00, 24.00, 5.91]
        case .iPhone13:       return [24.00, 24.00, 5.91]
        case .iPhone13Pro:    return [30.90, 13.43, 5.91]
        case .iPhone13ProMax: return [30.90, 13.43, 5.91]
        case .iPhoneSE3:      return [10.24, 10.44, 5.31]
        }
    }
    
    var wideCameraID: DeviceBackCameraPosition! {
        switch self {
        case .iPhone13Mini:   return .bottomRight
        case .iPhone13:       return .bottomRight
        case .iPhone13Pro:    return .bottomLeft
        case .iPhone13ProMax: return .bottomLeft
        case .iPhoneSE3:      return .topLeft
        }
    }
}
