//
//  PendulumLengthPicker.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/18/21.
//

import Foundation

extension PendulumInterface {

    enum LengthOption: UInt8, PendulumInterfacePicker {
        case noVariation
        case random
        case longEnd
        case shortEnd
        
        var parameters: Parameters {
            switch self {
            case .noVariation: return NoVariation.parameters
            case .random:      return Random.parameters
            case .longEnd:     return LongEnd.parameters
            case .shortEnd:    return ShortEnd.parameters
            }
        }
        
        var interfaceElement: InterfaceRenderer.InterfaceElement {
            switch self {
            case .noVariation: return NoVariation.generateInterfaceElement(type: self)
            case .random:      return Random     .generateInterfaceElement(type: self)
            case .longEnd:     return LongEnd    .generateInterfaceElement(type: self)
            case .shortEnd:    return ShortEnd   .generateInterfaceElement(type: self)
            }
        }
        
        func update(simulationPrototype: inout PendulumSimulationPrototype) {
            var shouldReset = false
            
            func ensureProperty(_ desired: PendulumSimulationPrototype.LengthType) {
                if simulationPrototype.customLengthType != desired {
                    simulationPrototype.customLengthType = desired
                    shouldReset = true
                }
            }
            
            switch self {
            case .noVariation:
                if simulationPrototype.doingCustomProperties[.length] {
                    simulationPrototype.doingCustomProperties[.length] = false
                    shouldReset = true
                }
            case .random, .longEnd, .shortEnd:
                if !simulationPrototype.doingCustomProperties[.length] {
                    simulationPrototype.doingCustomProperties[.length] = true
                    shouldReset = true
                }
                
                switch self {
                case .random:  ensureProperty(.random)
                case .longEnd: ensureProperty(.endIsLonger)
                default:       ensureProperty(.endIsShorter)
                }
            }
            
            if shouldReset {
                simulationPrototype.shouldResetSimulation = true
            }
        }
    }

}

fileprivate protocol LengthPickerElement: PendulumInterface.PickerElement {
    associatedtype PickerOption
}

extension LengthPickerElement {
    typealias PickerOption = PendulumInterface.LengthOption
}

fileprivate extension PendulumInterface {
    
    enum NoVariation: LengthPickerElement { static let label = "No Variation" }
    enum Random:      LengthPickerElement { static let label = "Random" }
    enum LongEnd:     LengthPickerElement { static let label = "Long End" }
    enum ShortEnd:    LengthPickerElement { static let label = "Short End" }
    
}
