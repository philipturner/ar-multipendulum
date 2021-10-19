//
//  PendulumInterfaceExtensions.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/16/21.
//

import ARHeadsetKit

extension PendulumInterface {
    
    func updateResources() {
        func setMeasurementText() {
            let parameters = CachedParagraph.measurement.parameters
            var paragraph = InterfaceRenderer.createParagraph(stringSegments: [(counter.measurement, 0)],
                                                              width:     parameters.width,
                                                              pixelSize: parameters.pixelSize)
            
            InterfaceRenderer.scaleParagraph(&paragraph, scale: interfaceScale)
            
            interfaceElements[.measurement].characterGroups = paragraph.characterGroups
        }
        
        @inline(__always)
        func setNewSize() {
            Self.interfaceScale = interfaceScale
            anchorDirection = simd_quatf(angle: degreesToRadians(16 * interfaceScale), axis: [1, 0, 0]).act([0, 0, -1])
        }
        
        if interfaceElements == nil {
            setNewSize()
            
            interfaceElements = .init()
            backButton        = .init()
            counter           = .init(pendulumInterface: self)
            
            propertyPicker        = .init()
            lengthPicker          = .init()
            massPicker            = .init()
            anglePicker           = .init()
            angularVelocityPicker = .init()
            
            baseInterface = .settings
            setMeasurementText()
            baseInterface = .mainInterface
        } else if interfaceScaleChanged {
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
            
            if previousInterface == .mainInterface {
                baseInterface = .settings
            }
            
            setMeasurementText()
            baseInterface = previousInterface
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
        
        var renderedInterface = false
        
        func renderInterface() {
            guard !renderedInterface else { return }
            renderedInterface = true
            
            internalRenderInterface()
        }
        
        switch currentAction {
        case .movingInterface:
            if !renderer.touchingScreen {
                currentAction = .none
                adjustInterface(headPosition: interfaceCenter)
            }
        case .openingPicker(let pickerType):
            pickerAnimationProgress += 0.05
            
            if pickerAnimationProgress >= 1 {
                pickerAnimationProgress = 1
                currentAction = .presentingPicker(pickerType)
            }
            
            adjustInterface(headPosition: interfaceCenter)
        case .presentingPicker(let pickerType):
            executePresentingPicker(pickerType: pickerType)
        case .closingPicker(let pickerType):
            pickerAnimationProgress -= 0.05
            
            if pickerAnimationProgress <= -1 {
                pickerAnimationProgress = -1
                currentAction = .none
                
                if pickerType == .property {
                    switch propertyPicker.selectedPanel {
                    case .length:          baseInterface = .length
                    case .mass:            baseInterface = .mass
                    case .angle:           baseInterface = .angle
                    case .angularVelocity: baseInterface = .angularVelocity
                    }
                    
                    setMeasurementText()
                }
            }
            
            adjustInterface(headPosition: interfaceCenter)
        case .movingSimulation(let waitingOnTapEnd):
            adjustInterface(headPosition: interfaceCenter)
            
            if waitingOnTapEnd {
                if !renderer.touchingScreen {
                    currentAction = .none
                }
            } else {
                if renderer.shortTappingScreen {
                    currentAction = .movingSimulation(true)
                }
            }
        case .modifyingSimulation:
            adjustInterface(headPosition: interfaceCenter)
        default:
            adjustInterface(headPosition: interfaceCenter)
            
            executeNoAction(renderInterface, setMeasurementText)
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
                
                adjustInterface(headPosition: interfaceCenter)
                
                anchor.highlight()
            }
        }
        
        centralRenderer.render(object:  anchor.buttonObject,  desiredLOD: 64)
        centralRenderer.render(objects: anchor.symbolObjects, desiredLOD: 45)
        
        
        
        renderInterface()
    }
    
    @inline(__always)
    private func internalRenderInterface() {
        let presentedInterface = self.presentedInterface

        switch presentedInterface {
        case .picker(let pickerType):
            interfaceRenderer.render(element: backButton.element)

            @inline(__always)
            func renderPicker<T: PendulumPropertyOption>(_ picker: Picker<T>) {
                interfaceRenderer.render(elements: picker.panels)
            }

            switch pickerType {
            case .property:        renderPicker(propertyPicker)
            case .length:          renderPicker(lengthPicker)
            case .mass:            renderPicker(massPicker)
            case .angle:           renderPicker(anglePicker)
            case .angularVelocity: renderPicker(angularVelocityPicker)
            }
        default:
            for button in presentedInterface.rectangularButtons {
                interfaceRenderer.render(element: interfaceElements[button])
            }

            switch presentedInterface {
            case .mainInterface:
                break
            default:
                interfaceRenderer.render(element: backButton.element)

                let buttonConfiguration = counter.mode.buttonConfiguration

                for button in buttonConfiguration.0 { interfaceRenderer.render(element: counter[button]) }
                for button in buttonConfiguration.1 { interfaceRenderer.render(element: counter[button]) }
            }
        }
    }
    
}

extension PendulumInterface {
    
    fileprivate func executePresentingPicker(pickerType: PickerType) {
        var selectedAPanel = false
        
        if let intersectionRay = renderer.interactionRay {
            backButton.element.hidden = false
            defer { backButton.element.hidden = true }
            
            var shouldClosePicker: Bool
            
            func tracePicker<T: PendulumPropertyOption>(picker: inout Picker<T>) {
                picker.hidden = false
                
                guard let panelID = picker.panels.trace(ray: intersectionRay)?.elementID,
                      let selectedPanel = T(rawValue: panelID) else {
                    return
                }
                
                if renderer.shortTappingScreen {
                    picker.selectedPanel = selectedPanel
                    shouldClosePicker = true
                    
                    picker.selectedPanel.update(simulationPrototype: &pendulumRenderer.prototype)
                } else {
                    picker.prepareToHighlight(panel: selectedPanel)
                    selectedAPanel = true
                }
            }
            
            if backButton.trace(ray: intersectionRay) != nil {
                backButton.element.isHighlighted = true
                shouldClosePicker = renderer.shortTappingScreen
            } else {
                shouldClosePicker = false
                
                switch pickerType {
                case .property:        tracePicker(picker: &propertyPicker)
                case .length:          tracePicker(picker: &lengthPicker)
                case .mass:            tracePicker(picker: &massPicker)
                case .angle:           tracePicker(picker: &anglePicker)
                case .angularVelocity: tracePicker(picker: &angularVelocityPicker)
                }
            }
            
            if shouldClosePicker {
                currentAction = .closingPicker(pickerType)
            }
        }
        
        adjustInterface(headPosition: interfaceCenter)
        
        if selectedAPanel {
            switch pickerType {
            case .property:        propertyPicker       .highlightSelectedPanel()
            case .length:          lengthPicker         .highlightSelectedPanel()
            case .mass:            massPicker           .highlightSelectedPanel()
            case .angle:           anglePicker          .highlightSelectedPanel()
            case .angularVelocity: angularVelocityPicker.highlightSelectedPanel()
            }
        }
    }
    
    fileprivate func executeNoAction(_ renderInterface: () -> Void, _ setMeasurementText: () -> Void) {
        guard let interactionRay = renderer.interactionRay,
              let (intersection, minProgress) = getIntersection(ray: interactionRay) else {
            return
        }
        
        switch intersection {
        case .backButton:
            backButton.element.isHighlighted = true
            
            if renderer.shortTappingScreen {
                switch baseInterface {
                case .length, .mass, .angle, .angularVelocity:
                    renderInterface()
                    baseInterface = .settings
                    setMeasurementText()
                case .settings:
                    renderInterface()
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
                
                if renderer.shortTappingScreen {
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
            
            if renderer.shortTappingScreen {
                if baseInterface != .mainInterface {
                    setMeasurementText()
                }
                
                switch baseInterface {
                case .mainInterface:
                    switch elementID {
                    case .moveSimulation:
                        currentAction = .movingSimulation(false)
                    case .settings:
                        renderInterface()
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
            
            if renderer.shortTappingScreen {
                counter.registerValueChange(button: button)
                counter.update(simulationPrototype: &pendulumRenderer.prototype)
                
                setMeasurementText()
            }
        case .anchor:
            if renderer.touchingScreen {
                currentAction = .movingInterface
            } else {
                anchor.highlight()
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
        }
    }
    
    fileprivate enum Intersection {
        case backButton
        case rectangularButton(CachedParagraph)
        case circularButton(Counter.CachedParagraph)
        case anchor
        case simulation
    }
    
    fileprivate func getIntersection(ray: RayTracing.Ray) -> (Intersection, Float)? {
        var intersection: Intersection?
        var minProgress: Float = .greatestFiniteMagnitude
        
        if let progress = backButton.trace(ray: ray) {
            minProgress  = progress
            intersection = .backButton
        }
        
        if let (element, progress) = interfaceElements.trace(ray: ray), progress < minProgress {
            minProgress  = progress
            intersection = .rectangularButton(element)
        }
        
        if let (button, progress) = counter.trace(ray: ray), progress < minProgress {
            minProgress  = progress
            intersection = .circularButton(button)
        }
        
        if let progress = anchor.buttonObject.trace(ray: ray), progress < minProgress {
            minProgress  = progress
            intersection = .anchor
        }
        
        if renderer.touchingScreen, let progress = pendulumRenderer.trace(ray: ray)?.progress, progress < minProgress {
            minProgress  = progress
            intersection = .simulation
        }
        
        guard let intersection = intersection else {
            return nil
        }
        
        return (intersection, minProgress)
    }
    
}
