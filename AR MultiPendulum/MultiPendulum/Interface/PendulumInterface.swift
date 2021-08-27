//
//  PendulumInterface.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/16/21.
//

import Metal
import simd

final class PendulumInterface: DelegateRenderer {
    var renderer: Renderer
    var pendulumRenderer: PendulumRenderer { renderer.pendulumRenderer }
    var cameraMeasurements: CameraMeasurements { renderer.cameraMeasurements }
    
    enum PickerType {
        case property
        case length
        case mass
        case angle
        case angularVelocity
    }
    
    enum Action: Equatable {
        case none
        case movingInterface
        
        case openingPicker(PickerType)
        case presentingPicker(PickerType)
        case closingPicker(PickerType)
        
        case movingSimulation(Bool)
        case modifyingSimulation(RayTracing.Ray, simd_float3, Bool, PendulumState)
    }
    
    enum BaseInterface {
        case mainInterface
        case settings
        
        case length
        case mass
        case angle
        case angularVelocity
    }
    
    enum PresentedInterface {
        case mainInterface
        case settings
        
        case length
        case mass
        case angle
        case angularVelocity
        
        case picker(PickerType)
        
        var rectangularButtons: [CachedParagraph] {
            switch self {
            case .mainInterface:   return [.startSimulation, .stopSimulation, .reset, .moveSimulation, .settings]
            case .settings:        return [.numberOfPendulums, .measurement, .modifyProperty]
            
            case .length:          return [.length,          .measurement, .options]
            case .mass:            return [.gravity,         .measurement, .options]
            case .angle:           return [.angle,           .measurement, .options]
            case .angularVelocity: return [.angularVelocity, .measurement, .options]
                
            case .picker:          return []
            }
        }
    }
    
    var currentAction: Action = .none
    var baseInterface: BaseInterface = .mainInterface
    
    var presentedInterface: PresentedInterface {
        switch currentAction {
        case .none, .movingInterface, .modifyingSimulation:
            switch baseInterface {
            case .mainInterface:   return .mainInterface
            case .settings:        return .settings
            
            case .length:          return .length
            case .mass:            return .mass
            case .angle:           return .angle
            case .angularVelocity: return .angularVelocity
            }
        case .openingPicker   (let pickerType),
             .presentingPicker(let pickerType),
             .closingPicker   (let pickerType):
            return .picker(pickerType)
        case .movingSimulation:
            return .mainInterface
        }
    }
    
    var pickerAnimationProgress: Float = -1
    var highlightedElementID: CachedParagraph?
    
    var interfaceDepth: Float = 0.7
    var anchorDirection: simd_float3 = normalize([0, 1, -1])
    
    var anchor: Anchor!
    var backButton: BackButton!
    var interfaceElements: ParagraphIndexContainer<CachedParagraph>!
    var counter: Counter!
    
    var propertyPicker: Picker<PropertyOption>!
    var lengthPicker: Picker<LengthOption>!
    var massPicker: Picker<MassOption>!
    var anglePicker: Picker<AngleOption>!
    var angularVelocityPicker: Picker<AngularVelocityOption>!
    
    init(renderer: Renderer, library: MTLLibrary) {
        self.renderer = renderer
        
        Self.cacheParagraphs()
        BackButton.cacheParagraphs()
        Counter.cacheParagraphs()
        
        Picker<PropertyOption>.cacheParagraphs()
        Picker<LengthOption>.cacheParagraphs()
        Picker<MassOption>.cacheParagraphs()
        Picker<AngleOption>.cacheParagraphs()
        Picker<AngularVelocityOption>.cacheParagraphs()
    }
}
