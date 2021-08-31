//
//  PendulumInterfaceExtensions.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/16/21.
//

import Foundation
import simd

extension PendulumInterface {
    
    func updateResources() {
        func setMeasurementText() {
            let parameters = CachedParagraph.measurement.parameters
            var paragraph = InterfaceRenderer.createParagraph(stringSegments: [(counter.measurement, 0)],
                                                              width:     parameters.width,
                                                              pixelSize: parameters.pixelSize)
            
            InterfaceRenderer.scaleParagraph(&paragraph, scale: Self.sizeScale)
            
            interfaceElements[.measurement].characterGroups = paragraph.characterGroups
        }
        
        do {
            let newSizeScale: Float = 0.8 * renderer.userSettings.storedSettings.interfaceScale
            
            @inline(__always)
            func setNewSize() {
                Self.sizeScale = newSizeScale
                anchorDirection = simd_quatf(angle: degreesToRadians(20 * Self.sizeScale), axis: [1, 0, 0]).act([0, 0, -1])
            }
            
            if interfaceElements == nil {
                setNewSize()
                
                interfaceElements = .init(interfaceRenderer: interfaceRenderer)
                backButton        = .init(interfaceRenderer: interfaceRenderer)
                counter           = .init(pendulumInterface: self)
                
                propertyPicker        = .init(interfaceRenderer: interfaceRenderer)
                lengthPicker          = .init(interfaceRenderer: interfaceRenderer)
                massPicker            = .init(interfaceRenderer: interfaceRenderer)
                anglePicker           = .init(interfaceRenderer: interfaceRenderer)
                angularVelocityPicker = .init(interfaceRenderer: interfaceRenderer)
                
                baseInterface = .settings
                setMeasurementText()
                baseInterface = .mainInterface
            } else if Self.sizeScale != newSizeScale {
                setNewSize()
                
                interfaceElements.resetSize()
                backButton       .resetSize()
                counter          .resetSize()
                
                propertyPicker       .resetSize()
                lengthPicker         .resetSize()
                massPicker           .resetSize()
                anglePicker          .resetSize()
                angularVelocityPicker.resetSize()
                
                let previousInterface = baseInterface
                baseInterface = .settings
                setMeasurementText()
                baseInterface = previousInterface
            }
        }
        
        
        
        if let highlightedElementID = highlightedElementID {
            interfaceElements[highlightedElementID].isHighlighted = false
        }
        
        backButton.element.isHighlighted = false
        counter.resetHighlighting()
        
        for paragraphType in CachedParagraph.allCases {
            interfaceElements[paragraphType].hidden = true
        }
        
        backButton.element.hidden = true
        counter.hideAllButtons()
        
        propertyPicker.hidden = true
        lengthPicker.hidden = true
        massPicker.hidden = true
        anglePicker.hidden = true
        angularVelocityPicker.hidden = true
        
        var headPosition = cameraMeasurements.cameraSpaceRotationCenter
        
        if !doingMixedRealityRendering {
            headPosition = simd_float3(0, 0, headPosition.z)
        }
        
        headPosition = simd_make_float3(cameraToWorldTransform * .init(headPosition, 1))
        
        func makeInterface() {
            renderInterface(headPosition: headPosition)
        }
        
        
        
        switch currentAction {
        case .movingInterface:
            if renderer.pendingTap == nil {
                currentAction = .none
                makeInterface()
            }
        case .openingPicker(let pickerType):
            pickerAnimationProgress += 0.05
            
            if pickerAnimationProgress >= 1 {
                pickerAnimationProgress = 1
                currentAction = .presentingPicker(pickerType)
            }
            
            makeInterface()
        case .presentingPicker(let pickerType):
            var selectedAnElement = false
            
            if let intersectionRay = renderer.interactionRay {
                backButton.element.hidden = false
                defer { backButton.element.hidden = true }
                
                var shouldClosePicker: Bool
                
                if backButton.rayTrace(ray: intersectionRay) != nil {
                    backButton.element.isHighlighted = true
                    shouldClosePicker = renderer.pendingTap != nil && !renderer.tapAlreadyStarted
                } else {
                    shouldClosePicker = false
                    
                    switch pickerType {
                    case .property:        propertyPicker.hidden = false
                    case .length:          lengthPicker.hidden = false
                    case .mass:            massPicker.hidden = false
                    case .angle:           anglePicker.hidden = false
                    case .angularVelocity: angularVelocityPicker.hidden = false
                    }
                    
                    func rayTracePicker<T: PendulumParagraphListElement>(picker: inout Picker<T>) -> T? {
                        guard let selectedElement = picker.elements.rayTrace(ray: intersectionRay)?.element else {
                            return nil
                        }
                        
                        if renderer.pendingTap != nil, renderer.tapAlreadyStarted == false {
                            picker.selectedElement = selectedElement
                            shouldClosePicker = true
                            
                            picker.selectedElement.update(simulationPrototype: &pendulumRenderer.prototype)
                        } else {
                            picker.prepareToHighlight(element: selectedElement)
                            selectedAnElement = true
                        }
                        
                        return selectedElement
                    }
                    
                    switch pickerType {
                    case .property:        _ = rayTracePicker(picker: &propertyPicker)
                    case .length:          _ = rayTracePicker(picker: &lengthPicker)
                    case .mass:            _ = rayTracePicker(picker: &massPicker)
                    case .angle:           _ = rayTracePicker(picker: &anglePicker)
                    case .angularVelocity: _ = rayTracePicker(picker: &angularVelocityPicker)
                    }
                }
                
                if shouldClosePicker {
                    currentAction = .closingPicker(pickerType)
                }
            }
            
            makeInterface()
            
            if selectedAnElement {
                switch pickerType {
                case .property:        propertyPicker       .highlightSelectedElement()
                case .length:          lengthPicker         .highlightSelectedElement()
                case .mass:            massPicker           .highlightSelectedElement()
                case .angle:           anglePicker          .highlightSelectedElement()
                case .angularVelocity: angularVelocityPicker.highlightSelectedElement()
                }
            }
        case .closingPicker(let pickerType):
            pickerAnimationProgress -= 0.05
            
            if pickerAnimationProgress <= -1 {
                pickerAnimationProgress = -1
                currentAction = .none
                
                if pickerType == .property {
                    switch propertyPicker.selectedElement {
                    case .length:          baseInterface = .length
                    case .mass:            baseInterface = .mass
                    case .angle:           baseInterface = .angle
                    case .angularVelocity: baseInterface = .angularVelocity
                    }
                    
                    setMeasurementText()
                }
            }
            
            makeInterface()
        case .movingSimulation(let waitingOnTapEnd):
            makeInterface()
            
            if waitingOnTapEnd {
                if renderer.pendingTap == nil {
                    currentAction = .none
                }
            } else {
                if renderer.pendingTap != nil, !renderer.tapAlreadyStarted {
                    currentAction = .movingSimulation(true)
                }
            }
        case .modifyingSimulation:
            makeInterface()
        default:
            makeInterface()
            
            if let interactionRay = renderer.interactionRay {
                enum Intersection {
                    case backButton
                    case rectangularButton(CachedParagraph)
                    case circularButton(Counter.CachedParagraph)
                    case anchor
                    case simulation
                }
                
                var intersection: Intersection?
                var minProgress: Float = .greatestFiniteMagnitude
                
                if let progress = backButton.rayTrace(ray: interactionRay) {
                    minProgress  = progress
                    intersection = .backButton
                }
                
                if let (element, progress) = interfaceElements.rayTrace(ray: interactionRay), progress < minProgress {
                    minProgress  = progress
                    intersection = .rectangularButton(element)
                }
                
                if let (button, progress) = counter.elements.rayTrace(ray: interactionRay), progress < minProgress {
                    minProgress  = progress
                    intersection = .circularButton(button)
                }
                
                if let progress = anchor.buttonObject.rayTrace(ray: interactionRay), progress < minProgress {
                    minProgress  = progress
                    intersection = .anchor
                }
                
                if renderer.pendingTap != nil,
                   let progress = pendulumRenderer.rayTrace(ray: interactionRay)?.progress, progress < minProgress {
                    minProgress  = progress
                    intersection = .simulation
                }
                
                switch intersection {
                case .backButton:
                    backButton.element.isHighlighted = true
                    
                    if renderer.pendingTap != nil, !renderer.tapAlreadyStarted {
                        switch baseInterface {
                        case .length, .mass, .angle, .angularVelocity:
                            baseInterface = .settings
                            setMeasurementText()
                        case .settings:
                            baseInterface = .mainInterface
                        case .mainInterface:
                            fatalError("Back button should never be presented in the main interface!")
                        }
                    }
                case .rectangularButton(let elementID):
                    switch elementID {
                    case .numberOfPendulums, .measurement,
                         .length, .gravity, .angle, .angularVelocity:
                        break
                    default:
                        interfaceElements[elementID].isHighlighted = true
                        highlightedElementID = elementID
                        
                        if renderer.pendingTap != nil, !renderer.tapAlreadyStarted {
                            switch elementID {
                            case .startSimulation:
                                pendulumRenderer.isReplaying = true
                            case .stopSimulation:
                                pendulumRenderer.isReplaying = false
                            case .reset:
                                pendulumRenderer.isReplaying = false
                                
                                pendulumRenderer.frameUpdateSemaphore.wait()
                                pendulumRenderer.lastFrameID = 0
                                pendulumRenderer.frameUpdateSemaphore.signal()
                            default:
                                break
                            }
                        }
                    }
                    
                    func changeAction(_ target: CachedParagraph, _ action: Action) {
                        if elementID == target {
                            currentAction = action
                        }
                    }
                    
                    if renderer.pendingTap != nil, !renderer.tapAlreadyStarted {
                        if baseInterface != .mainInterface {
                            setMeasurementText()
                        }
                        
                        switch baseInterface {
                        case .mainInterface:
                            switch elementID {
                            case .moveSimulation:
                                currentAction = .movingSimulation(false)
                            case .settings:
                                baseInterface = .settings
                            default:
                                break
                            }
                        case .settings:        changeAction(.modifyProperty, .openingPicker(.property))
                            
                        case .length:          changeAction(.options,        .openingPicker(.length))
                        case .mass:            changeAction(.options,        .openingPicker(.mass))
                        case .angle:           changeAction(.options,        .openingPicker(.angle))
                        case .angularVelocity: changeAction(.options,        .openingPicker(.angularVelocity))
                        }
                    }
                case .circularButton(let button):
                    counter.highlight(button: button)
                    
                    if renderer.pendingTap != nil, !renderer.tapAlreadyStarted {
                        counter.registerValueChange(button: button)
                        counter.update(simulationPrototype: &pendulumRenderer.prototype)
                        
                        setMeasurementText()
                    }
                case .anchor:
                    if renderer.pendingTap == nil, !renderer.tapAlreadyStarted {
                        anchor.highlight()
                    } else {
                        currentAction = .movingInterface
                    }
                case .simulation:
                    let intersection = interactionRay.project(progress: minProgress)
                    var delta = intersection - pendulumRenderer.pendulumLocation
                    
                    let zAxis = pendulumRenderer.pendulumOrientation.act([0, 0, 1])
                    delta -= dot(delta, zAxis) * zAxis
                    
                    if any(abs(delta) .> 1e-4),
                       let stateToModify = pendulumRenderer.meshConstructor.statesToRender?.last! {
                        currentAction = .modifyingSimulation(interactionRay, normalize(delta),
                                                             pendulumRenderer.isReplaying, stateToModify)
                    }
                case nil:
                    break
                }
            }
        }
        
        if currentAction == .movingInterface {
            if var interactionDirection = renderer.interactionRay?.direction {
                let highestDirection: simd_float3 = normalize([0, 1, 0.04])

                if abs(interactionDirection.y) > highestDirection.y {
                    if abs(interactionDirection.x) < 1e-6, abs(interactionDirection.z) < 1e-6 {
                        interactionDirection = highestDirection
                    } else {
                        interactionDirection.y = simd_clamp(interactionDirection.y, -highestDirection.y, highestDirection.y)

                        let direction2D = normalize(simd_float2(interactionDirection.x, interactionDirection.z))
                        interactionDirection.x = direction2D.x * highestDirection.z
                        interactionDirection.z = direction2D.y * highestDirection.z
                    }
                }

                anchorDirection = interactionDirection

                renderInterface(headPosition: headPosition)
                
                anchor.highlight()
            }
        }
        
        centralRenderer.append(object:  &anchor.buttonObject,  desiredLOD: 64)
        centralRenderer.append(objects: &anchor.symbolObjects, desiredLOD: 45)
    }
    
}
