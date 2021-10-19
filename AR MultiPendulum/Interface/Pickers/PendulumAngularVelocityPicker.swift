//
//  PendulumAngularVelocityPicker.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/18/21.
//

import ARHeadsetKit

extension PendulumInterface {
    
    enum AngularVelocityOption: Int, PendulumPropertyOption {
        case noVariation
        case random
        
        var parameters: Parameters {
            switch self {
            case .noVariation: return NoVariation.parameters
            case .random:      return Random.parameters
            }
        }
        
        var interfaceElement: ARInterfaceElement {
            switch self {
            case .noVariation: return NoVariation.generateInterfaceElement(type: self)
            case .random:      return Random     .generateInterfaceElement(type: self)
            }
        }
        
        func update(simulationPrototype: inout PendulumSimulationPrototype) {
            var shouldReset = false
            
            func ensureProperty(_ desired: PendulumSimulationPrototype.AngularVelocityType) {
                if simulationPrototype.customAngularVelocityType != desired {
                    simulationPrototype.customAngularVelocityType = desired
                    shouldReset = true
                }
            }
            
            switch self {
            case .noVariation:
                if simulationPrototype.doingCustomProperties[.angularVelocity] {
                    simulationPrototype.doingCustomProperties[.angularVelocity] = false
                    shouldReset = true
                }
            case .random:
                if !simulationPrototype.doingCustomProperties[.angularVelocity] {
                    simulationPrototype.doingCustomProperties[.angularVelocity] = true
                    shouldReset = true
                }
                
                switch self {
                default: ensureProperty(.random)
                }
            }
            
            if shouldReset {
                simulationPrototype.shouldResetSimulation = true
            }
        }
    }
    
}

fileprivate protocol AngularVelocityPickerPanel: PendulumPickerPanel where Option == PendulumInterface.AngularVelocityOption { }

fileprivate extension PendulumInterface {
    
    enum NoVariation: AngularVelocityPickerPanel { static let label = "No Variation" }
    enum Random:      AngularVelocityPickerPanel { static let label = "Random" }
    
}
