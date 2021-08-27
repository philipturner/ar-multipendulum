//
//  PendulumAnglePicker.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/18/21.
//

import Foundation

extension PendulumInterface {
    
    enum AngleOption: UInt8, PendulumInterfacePicker {
        case noVariation
        case random
        case staircase
        case spiral
        
        var parameters: Parameters {
            switch self {
            case .noVariation: return NoVariation.parameters
            case .random:      return Random.parameters
            case .staircase:   return Staircase.parameters
            case .spiral:      return Spiral.parameters
            }
        }
        
        var interfaceElement: InterfaceRenderer.InterfaceElement {
            switch self {
            case .noVariation: return NoVariation.generateInterfaceElement(type: self)
            case .random:      return Random     .generateInterfaceElement(type: self)
            case .staircase:   return Staircase  .generateInterfaceElement(type: self)
            case .spiral:      return Spiral     .generateInterfaceElement(type: self)
            }
        }
        
        func update(simulationPrototype: inout PendulumSimulationPrototype) {
            var shouldReset = false
            
            func ensureProperty(_ desired: PendulumSimulationPrototype.AnglePercentType) {
                if simulationPrototype.customAngleType != desired {
                    simulationPrototype.customAngleType = desired
                    shouldReset = true
                }
            }
            
            switch self {
            case .noVariation:
                if simulationPrototype.doingCustomProperties[.angle] {
                    simulationPrototype.doingCustomProperties[.angle] = false
                    shouldReset = true
                }
            case .random, .staircase, .spiral:
                if !simulationPrototype.doingCustomProperties[.angle] {
                    simulationPrototype.doingCustomProperties[.angle] = true
                    shouldReset = true
                }
                
                switch self {
                case .random:    ensureProperty(.random)
                case .staircase: ensureProperty(.staircase)
                default:         ensureProperty(.spiral)
                }
            }
            
            if shouldReset {
                simulationPrototype.shouldResetSimulation = true
            }
        }
    }
    
}

fileprivate protocol AnglePickerElement: PendulumInterface.PickerElement {
    associatedtype PickerOption
}

extension AnglePickerElement {
    typealias PickerOption = PendulumInterface.AngleOption
}

fileprivate extension PendulumInterface {
    
    enum NoVariation: AnglePickerElement { static let label = "No Variation" }
    enum Random:      AnglePickerElement { static let label = "Random" }
    enum Staircase:   AnglePickerElement { static let label = "Staircase" }
    enum Spiral:      AnglePickerElement { static let label = "Spiral" }
    
}
