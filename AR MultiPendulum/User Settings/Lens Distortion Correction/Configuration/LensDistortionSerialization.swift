//
//  LensDistortionSerialization.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/21/21.
//

import Foundation
import simd
import ZippyJSON

extension LensDistortionCorrector {
    
    struct StoredSettings: Codable, Equatable {
        var headsetFOV: Double // in degrees
        var viewportDiameter: Double // in meters
        
        enum CaseSize: Int, Codable {
            case none = 0
            case small = 1
            case large = 2
            
            var thickness: Double { // in meters
                switch self {
                case .none:  return 0
                case .small: return 0.001 * 1.5
                case .large: return 0.001 * 5.0
                }
            }
            
            var protrusionDepth: Double { // in meters
                switch self {
                case .none:  return 0
                case .small: return 0.001 * 1.0
                case .large: return 0.001 * 3.5
                }
            }
        }
        
        var caseSize: CaseSize
        var caseThickness: Double { caseSize.thickness }
        var caseProtrusionDepth: Double { caseSize.protrusionDepth }
        
        var eyeOffsetX: Double // in meters
        var eyeOffsetY: Double // in meters
        var eyeOffsetZ: Double // in meters
        
        var k1: Float // for green light
        var k2: Float // for green light
        var k1_proportions: simd_float2 // for red and blue relative to green
        
        // The sum of k1 and k2 happen to be the same for every color
        // when fine-tuned correctly. To make fine-tuning easier,
        // `k2_proportions` is automatically calculated from green's
        // k1 and k2, and the k1 of red and blue.
        //
        // In addition, when k1 of blue is greater than the k1 of red and green,
        // blue always maps to an area closer to the center of the final texture
        // during lens distortion. Thus, the custom implementation of mapping
        // between VRR resolutions does not break (see ../Kernels.metal for a
        // more thorough explanation). So, k1 of each color is constrained
        // so that k1 (red) < k1 (green) < k1 (blue).
        
        var k2_proportions: simd_float2 {
            let k_sum = k1 + k2
            let remaining_k = fma(k1, -k1_proportions, k_sum)
            return remaining_k * Float(simd_fast_recip(Double(k2)))
        }
        
        static let defaultSettings = Self(
            headsetFOV: 80.0,
            viewportDiameter: 0.001 * 58,
            
            caseSize: .small,
            eyeOffsetX: 0.001 * 31,
            eyeOffsetY: 0.001 * 34,
            eyeOffsetZ: 0.001 * 77,
            
            k1: 0.135,
            k2: 0.185,
            k1_proportions: [0.70, 1.31]
        )
        
        func eyePositionMatches(_ other: Self) -> Bool {
            caseThickness == other.caseThickness &&
            caseProtrusionDepth == other.caseProtrusionDepth &&
                
            eyeOffsetX == other.eyeOffsetX &&
            eyeOffsetY == other.eyeOffsetY &&
            eyeOffsetZ == other.eyeOffsetZ
        }
        
        func viewportMatches(_ other: Self) -> Bool {
            eyePositionMatches(other) &&
            viewportDiameter == other.viewportDiameter
        }
        
        func intermediateTextureMatches(_ other: Self) -> Bool {
            headsetFOV == other.headsetFOV &&
            viewportDiameter == other.viewportDiameter &&
                
            k1 == other.k1 && k2 == other.k2 &&
            k1_proportions == other.k1_proportions
        }
    }
    
    static func retrieveSettings() -> StoredSettings? {
        guard let jsonData = try? Data(contentsOf: settingsURL) else {
            return nil
        }
        
        do {
            return try ZippyJSONDecoder().decode(StoredSettings.self, from: jsonData)
        } catch {
            debugLabel { print("Error deserializing lens distortion settings: \(error.localizedDescription)") }
            return nil
        }
    }
    
    static func saveSettings(_ settings: StoredSettings) {
        var jsonData: Data
        
        do {
            jsonData = try JSONEncoder().encode(settings)
        } catch {
            debugLabel { print("Error serializing lens distortion settings: \(error.localizedDescription)") }
            return
        }
        
        try! jsonData.write(to: settingsURL, options: .atomic)
    }
    
    private static let settingsURL: URL = {
        var directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory.appendPathComponent("User Settings/Lens Distortion Correction", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        return directory.appendingPathComponent("settings.json", isDirectory: false)
    }()
    
}
