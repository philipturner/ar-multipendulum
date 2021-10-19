//
//  PendulumMassPicker.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/18/21.
//

import Foundation

extension PendulumInterface {
    
    enum MassOption: UInt8, PendulumInterfacePicker {
        case noVariation
        case random
        case heavyEnd
        case lightEnd
        
        var parameters: Parameters {
            switch self {
            case .noVariation: return NoVariation.parameters
            case .random:      return Random.parameters
            case .heavyEnd:    return HeavyEnd.parameters
            case .lightEnd:    return LightEnd.parameters
            }
        }
        
        var interfaceElement: InterfaceRenderer.InterfaceElement {
            switch self {
            case .noVariation: return NoVariation.generateInterfaceElement(type: self)
            case .random:      return Random     .generateInterfaceElement(type: self)
            case .heavyEnd:    return HeavyEnd   .generateInterfaceElement(type: self)
            case .lightEnd:    return LightEnd   .generateInterfaceElement(type: self)
            }
        }
        
        func update(simulationPrototype: inout PendulumSimulationPrototype) {
            var shouldReset = false
            
            func ensureProperty(_ desired: PendulumSimulationPrototype.MassType) {
                if simulationPrototype.customMassType != desired {
                    simulationPrototype.customMassType = desired
                    shouldReset = true
                }
            }
            
            switch self {
            case .noVariation:
                if simulationPrototype.doingCustomProperties[.mass] {
                    simulationPrototype.doingCustomProperties[.mass] = false
                    shouldReset = true
                }
            case .random, .heavyEnd, .lightEnd:
                if !simulationPrototype.doingCustomProperties[.mass] {
                    simulationPrototype.doingCustomProperties[.mass] = true
                    shouldReset = true
                }
                
                switch self {
                case .random:   ensureProperty(.random)
                case .heavyEnd: ensureProperty(.endIsHeavier)
                default:        ensureProperty(.endIsLighter)
                }
            }
            
            if shouldReset {
                simulationPrototype.shouldResetSimulation = true
            }
        }
    }
    
}

fileprivate protocol MassPickerElement: PendulumInterface.PickerElement {
    associatedtype PickerOption
}

extension MassPickerElement {
    typealias PickerOption = PendulumInterface.MassOption
}

fileprivate extension PendulumInterface {
    
    enum NoVariation: MassPickerElement { static let label = "No Variation" }
    enum Random:      MassPickerElement { static let label = "Random" }
    enum HeavyEnd:    MassPickerElement { static let label = "Heavy End" }
    enum LightEnd:    MassPickerElement { static let label = "Light End" }
    
}
