//
//  UserSettingsSerialization.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/21/21.
//

import Foundation
import simd
import ZippyJSON

extension UserSettings {
    
    func updateResources() {
        let coordinator = renderer.coordinator
        
        var newStoredSettings = storedSettings
        newStoredSettings.transferData(from: coordinator.renderingSettings)
        newStoredSettings.transferData(from: coordinator.interactionSettings)
        newStoredSettings.transferData(from: coordinator.lidarEnabledSettings)
        
        lensDistortionCorrector.pendingStoredSettings.caseSize = renderer.coordinator.caseSize
        
        if newStoredSettings != storedSettings {
            shouldSaveSettings = true
            storedSettings = newStoredSettings
        }
        
        if !savingSettings, shouldSaveSettings {
            savingSettings = true
            shouldSaveSettings = false
            
            let storedSettingsCopy = storedSettings
            
            DispatchQueue.global(qos: .background).async {
                Self.saveSettings(storedSettingsCopy)
                self.savingSettings = false
            }
        }
    }
    
}

extension UserSettings {
    
    struct StoredSettings: Codable, Equatable {
        var isFirstAppLaunch: Bool
        
        var doingMixedRealityRendering: Bool
        var renderingViewSeparator: Bool
        var doingTwoSidedPendulums: Bool
        
        enum Handedness: Int, Codable {
            case none = 0
            case left = 1
            case right = 2
        }
        
        var canHideSettingsIcon: Bool
        var usingHandForSelection: Bool
        var showingHandPosition: Bool
        
        var allowingSceneReconstruction: Bool
        var allowingHandReconstruction: Bool
        var handheldHandedness: Handedness
        var headsetHandedness: Handedness
        
        static let defaultSettings = Self(
            isFirstAppLaunch: true,
            
            doingMixedRealityRendering: false,
            renderingViewSeparator: true,
            doingTwoSidedPendulums: false,
            
            canHideSettingsIcon: false,
            usingHandForSelection: true,
            showingHandPosition: false,
            
            allowingSceneReconstruction: true,
            allowingHandReconstruction: true,
            handheldHandedness: .none,
            headsetHandedness: .left
        )
        
        mutating func transferData(from settings: RenderingSettings) {
            doingMixedRealityRendering = settings.doingMixedRealityRendering
            renderingViewSeparator     = settings.renderingViewSeparator
            doingTwoSidedPendulums     = settings.doingTwoSidedPendulums
        }
        
        mutating func transferData(from settings: InteractionSettings) {
            canHideSettingsIcon   = settings.canHideSettingsIcon
            usingHandForSelection = settings.usingHandForSelection
            showingHandPosition   = settings.showingHandPosition
        }
        
        mutating func transferData(from settings: LiDAREnabledSettings) {
            allowingSceneReconstruction = settings.allowingSceneReconstruction
            allowingHandReconstruction  = settings.allowingHandReconstruction
            handheldHandedness          = settings.handheldHandedness
        }
    }
    
    static func retrieveSettings() -> StoredSettings? {
        guard let jsonData = try? Data(contentsOf: settingsURL) else {
            return nil
        }
        
        do {
            return try ZippyJSONDecoder().decode(StoredSettings.self, from: jsonData)
        } catch {
            debugLabel { print("Error deserializing user settings: \(error.localizedDescription)") }
            return nil
        }
    }
    
    static func saveSettings(_ settings: StoredSettings) {
        var jsonData: Data
        
        do {
            jsonData = try JSONEncoder().encode(settings)
        } catch {
            debugLabel { print("Error serializing user settings: \(error.localizedDescription)") }
            return
        }
        
        try! jsonData.write(to: settingsURL, options: .atomic)
    }
    
    private static let settingsURL: URL = {
        var directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory.appendPathComponent("User Settings", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        return directory.appendingPathComponent("settings.json", isDirectory: false)
    }()
    
}
