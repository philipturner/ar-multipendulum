//
//  UserSettings.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 6/13/21.
//

import Metal
import ARKit

final class UserSettings: DelegateRenderer {
    var renderer: Renderer
    
    var savingSettings = false
    var shouldSaveSettings = false
    
    var storedSettings: StoredSettings
    
    var cameraMeasurements: CameraMeasurements!
    var lensDistortionCorrector: LensDistortionCorrector!
    
    init(renderer: Renderer, library: MTLLibrary) {
        self.renderer = renderer
        
        storedSettings = Self.retrieveSettings() ?? .defaultSettings
        
        if storedSettings.isFirstAppLaunch {
            shouldSaveSettings = true
        }
        
        cameraMeasurements      = CameraMeasurements     (userSettings: self, library: library)
        lensDistortionCorrector = LensDistortionCorrector(userSettings: self, library: library)
    }
}

protocol DelegateUserSettings {
    var userSettings: UserSettings { get }
    
    init(userSettings: UserSettings, library: MTLLibrary)
}

extension DelegateUserSettings {
    var renderer: Renderer { userSettings.renderer }
    var device: MTLDevice { userSettings.device }
    var renderIndex: Int { userSettings.renderIndex }
    var usingVertexAmplification: Bool { renderer.usingVertexAmplification }
    
    var doingMixedRealityRendering: Bool { renderer.doingMixedRealityRendering }
    var usingModifiedPerspective: Bool { renderer.usingModifiedPerspective }
    
    var cameraMeasurements: CameraMeasurements { userSettings.cameraMeasurements }
    var lensDistortionCorrector: LensDistortionCorrector { userSettings.lensDistortionCorrector }
}
