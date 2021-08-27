//
//  PendulumPropertyPicker.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/17/21.
//

import Foundation

extension PendulumInterface {

    enum PropertyOption: UInt8, PendulumInterfacePicker {
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
        
        var interfaceElement: InterfaceRenderer.InterfaceElement {
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

fileprivate protocol PropertyPickerElement: PendulumInterface.PickerElement {
    associatedtype PickerOption
}

extension PropertyPickerElement {
    typealias PickerOption = PendulumInterface.PropertyOption
}

fileprivate extension PendulumInterface {
    
    enum Length:          PropertyPickerElement { static let label = "Length" }
    enum Mass:            PropertyPickerElement { static let label = "Mass" }
    enum Angle:           PropertyPickerElement { static let label = "Angle" }
    enum AngularVelocity: PropertyPickerElement { static let label = "Angular Velocity" }
    
}
