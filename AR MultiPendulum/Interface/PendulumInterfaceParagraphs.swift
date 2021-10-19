//
//  PendulumInterfaceParagraphs.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/16/21.
//

import ARHeadsetKit

extension PendulumInterface: ARParagraphContainer {
    
    enum CachedParagraph: Int, ARParagraphListElement {
        case startSimulation
        case stopSimulation
        case reset
        case moveSimulation
        case settings
        
        case numberOfPendulums
        case modifyProperty
        
        case length
        case gravity
        case angle
        case angularVelocity
        
        case measurement
        case options
        
        var parameters: Parameters {
            switch self {
            case .startSimulation:   return StartSimulation.parameters
            case .stopSimulation:    return StopSimulation.parameters
            case .reset:             return Reset.parameters
            case .moveSimulation:    return MoveSimulation.parameters
            case .settings:          return Settings.parameters
                
            case .numberOfPendulums: return NumberOfPendulums.parameters
            case .modifyProperty:    return ModifyProperty.parameters
            
            case .length:            return Length.parameters
            case .gravity:           return Gravity.parameters
            case .angle:             return Angle.parameters
            case .angularVelocity:   return AngularVelocity.parameters
                
            case .measurement:       return Measurement.parameters
            case .options:           return Options.parameters
            }
        }
        
        var interfaceElement: ARInterfaceElement {
            switch self {
            case .startSimulation:   return StartSimulation  .generateInterfaceElement(type: self)
            case .stopSimulation:    return StopSimulation   .generateInterfaceElement(type: self)
            case .reset:             return Reset            .generateInterfaceElement(type: self)
            case .moveSimulation:    return MoveSimulation   .generateInterfaceElement(type: self)
            case .settings:          return Settings         .generateInterfaceElement(type: self)
            
            case .numberOfPendulums: return NumberOfPendulums.generateInterfaceElement(type: self)
            case .modifyProperty:    return ModifyProperty   .generateInterfaceElement(type: self)
            
            case .length:            return Length           .generateInterfaceElement(type: self)
            case .gravity:           return Gravity          .generateInterfaceElement(type: self)
            case .angle:             return Angle            .generateInterfaceElement(type: self)
            case .angularVelocity:   return AngularVelocity  .generateInterfaceElement(type: self)
            
            case .measurement:       return Measurement      .generateInterfaceElement(type: self)
            case .options:           return Options          .generateInterfaceElement(type: self)
            }
        }
    }
    
    struct ElementContainer<CachedParagraph: ARParagraphListElement>: ARTraceableParagraphContainer {
        var elements: [ARInterfaceElement]
        
        subscript(index: CachedParagraph) -> ARInterfaceElement {
            get { elements[index.rawValue] }
            set { elements[index.rawValue] = newValue }
        }
        
        init() {
            elements = .init(capacity: CachedParagraph.allCases.count)
            
            for element in CachedParagraph.allCases {
                elements.append(element.interfaceElement)
            }
        }
        
        mutating func resetSize() {
            for element in CachedParagraph.allCases {
                elements[element.rawValue] = element.interfaceElement
            }
        }
    }
    
}



fileprivate protocol PendulumInterfaceRectangularButton: ARParagraph { }

extension PendulumInterface.RectangularButton {
    
    typealias CachedParagraph = PendulumInterface.CachedParagraph
    
    static var width: Float { 0.8 * 0.34 }
    static var pixelSize: Float { 0.8 * 0.00025 }
    
    static var parameters: Parameters {
        let paragraphWidth = width - 0.8 * 0.01
        return (stringSegments: [ (label, 2) ], width: paragraphWidth, pixelSize: pixelSize)
    }
    
    static func generateInterfaceElement(type: CachedParagraph) -> ARInterfaceElement {
        var paragraph = PendulumInterface.createParagraph(type)
        let scale = PendulumInterface.interfaceScale
        
        InterfaceRenderer.scaleParagraph(&paragraph, scale: scale)
        
        let height = max(0.8 * 0.08 * scale, 0.8 * 0.02 * scale + paragraph.suggestedHeight)
        
        return .init(position: .zero, forwardDirection: [0, 0, 1], orthogonalUpDirection: [0, 1, 0],
                     width: width * scale, height: height, depth: 0.8 * 0.05 * scale,
                     radius: .greatestFiniteMagnitude,
                     
                     highlightColor: [0.6, 0.8, 1.0], highlightOpacity: 1.0,
                     surfaceColor:   [0.3, 0.5, 0.7], surfaceOpacity: 0.75,
                     characterGroups: paragraph.characterGroups)
    }
    
}

fileprivate extension PendulumInterface {
    
    typealias RectangularButton = PendulumInterfaceRectangularButton
    
    enum StartSimulation:   RectangularButton { static let label = "Start Simulation" }
    enum StopSimulation:    RectangularButton { static let label = "Stop Simulation" }
    enum Reset:             RectangularButton { static let label = "Reset" }
    enum MoveSimulation:    RectangularButton { static let label = "Move Simulation" }
    enum Settings:          RectangularButton { static let label = "Settings" }
    
    enum NumberOfPendulums: RectangularButton { static let label = "Number of Pendulums" }
    enum ModifyProperty:    RectangularButton { static let label = "Configure Other Start Conditions" }
    
    enum Length:            RectangularButton { static let label = "Length" }
    enum Gravity:           RectangularButton { static let label = "Gravity" }
    enum Angle:             RectangularButton { static let label = "Angle" }
    enum AngularVelocity:   RectangularButton { static let label = "Angular Velocity" }
    
    enum Measurement:       RectangularButton { static let label = "" }
    enum Options:           RectangularButton { static let label = "Options" }
    
}
