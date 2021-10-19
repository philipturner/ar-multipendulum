//
//  DeviceMeasurementProtocols.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/10/21.
//

import DeviceKit
import simd

enum DeviceBackCameraPosition {
    case topLeft
    case bottomLeft
    case topRight
    case middleRight
    case bottomRight
}

protocol DeviceMeasurementProvider {
    var deviceSize: simd_double3! { get }
    var screenSize: simd_double2! { get }
    var isFullScreen: Bool! { get }
    
    var wideCameraOffset: simd_double3! { get }
    var wideCameraID: DeviceBackCameraPosition! { get }
}
