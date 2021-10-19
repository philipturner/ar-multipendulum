//
//  PendulumLengthPicker.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/18/21.
//

import ARHeadsetKit

extension PendulumInterface {

    enum LengthOption: Int, PendulumPropertyOption {
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
        
        var interfaceElement: ARInterfaceElement {
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

fileprivate protocol LengthPickerPanel: PendulumPickerPanel where Option == PendulumInterface.LengthOption { }

fileprivate extension PendulumInterface {
    
    enum NoVariation: LengthPickerPanel { static let label = "No Variation" }
    enum Random:      LengthPickerPanel { static let label = "Random" }
    enum LongEnd:     LengthPickerPanel { static let label = "Long End" }
    enum ShortEnd:    LengthPickerPanel { static let label = "Short End" }
    
}
