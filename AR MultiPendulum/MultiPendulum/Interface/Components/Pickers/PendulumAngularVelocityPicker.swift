//
//  PendulumAngularVelocityPicker.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/18/21.
//

import Foundation

extension PendulumInterface {
    
    enum AngularVelocityOption: UInt8, PendulumInterfacePicker {
        case noVariation
        case random
        
        var parameters: Parameters {
            switch self {
            case .noVariation: return NoVariation.parameters
            case .random:      return Random.parameters
            }
        }
        
        var interfaceElement: InterfaceRenderer.InterfaceElement {
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

fileprivate protocol AngularVelocityPickerElement: PendulumInterface.PickerElement {
    associatedtype PickerOption
}

extension AngularVelocityPickerElement {
    typealias PickerOption = PendulumInterface.AngularVelocityOption
}

fileprivate extension PendulumInterface {
    
    enum NoVariation: AngularVelocityPickerElement { static let label = "No Variation" }
    enum Random:      AngularVelocityPickerElement { static let label = "Random" }
    
}
