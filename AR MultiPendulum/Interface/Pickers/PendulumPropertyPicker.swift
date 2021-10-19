//
//  PendulumPropertyPicker.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/17/21.
//

import ARHeadsetKit

extension PendulumInterface {

    enum PropertyOption: Int, PendulumPropertyOption {
        case length
        case mass
        case angle
        case angularVelocity
        
        var parameters: Parameters {
            switch self {
            case .length:          return Length.parameters
            case .mass:            return Mass.parameters
            case .angle:           return Angle.parameters
            case .angularVelocity: return AngularVelocity.parameters
            }
        }
        
        var interfaceElement: ARInterfaceElement {
            switch self {
            case .length:          return Length         .generateInterfaceElement(type: self)
            case .mass:            return Mass           .generateInterfaceElement(type: self)
            case .angle:           return Angle          .generateInterfaceElement(type: self)
            case .angularVelocity: return AngularVelocity.generateInterfaceElement(type: self)
            }
        }
        
        func update(simulationPrototype: inout PendulumSimulationPrototype) {
            var newLoadedProperty: PendulumSimulationPrototype.PropertyType
            
            switch self {
            case .length:          newLoadedProperty = .length
            case .mass:            newLoadedProperty = .mass
            case .angle:           newLoadedProperty = .angle
            case .angularVelocity: newLoadedProperty = .angularVelocity
            }
            
            simulationPrototype.loadedProperty = newLoadedProperty
        }
    }

}

fileprivate protocol PropertyPickerPanel: PendulumPickerPanel where Option == PendulumInterface.PropertyOption { }

fileprivate extension PendulumInterface {
    
    enum Length:          PropertyPickerPanel { static let label = "Length" }
    enum Mass:            PropertyPickerPanel { static let label = "Mass" }
    enum Angle:           PropertyPickerPanel { static let label = "Angle" }
    enum AngularVelocity: PropertyPickerPanel { static let label = "Angular Velocity" }
    
}
