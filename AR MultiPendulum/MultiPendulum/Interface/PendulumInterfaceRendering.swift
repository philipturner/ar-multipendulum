//
//  PendulumInterfaceRendering.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/18/21.
//

import Foundation
import simd

extension PendulumInterface {
    
    func renderInterface(headPosition: simd_float3) {
        typealias InterfaceElement = InterfaceRenderer.InterfaceElement
        
        let rotationAxis = normalize(cross([0, 1, 0], anchorDirection))
        
        let anchorPosition = fma(anchorDirection, interfaceDepth, headPosition)
        let anchorUpDirection = cross(anchorDirection, rotationAxis)
        let anchorOrientation = InterfaceElement.createOrientation(forwardDirection: -anchorDirection,
                                                                   orthogonalUpDirection: anchorUpDirection)
        
        anchor = Anchor(position: anchorPosition, orientation: anchorOrientation)
        
        func renderBackButton() {
            backButton.element.hidden = false
            
            let elementDirection = simd_quatf(angle: degreesToRadians(12 * Self.sizeScale), axis: rotationAxis).act(anchorDirection)
            let upDirection = cross(elementDirection, rotationAxis)
            
            let position = fma(elementDirection, interfaceDepth, headPosition)
            let orientation = InterfaceElement.createOrientation(forwardDirection: -elementDirection,
                                                                 orthogonalUpDirection: upDirection)
            
            backButton.element.setProperties(position: position, orientation: orientation)
        }
        
        @inline(__always)
        func renderCircularButtons(direction: simd_float3) {
            var separationAngle: Float = -degreesToRadians(10 * Self.sizeScale)
            var separationAngleHalf = separationAngle / 2
            
            let upDirection = cross(direction, rotationAxis)
            let buttonConfiguration = counter.mode.buttonConfiguration
            
            for i in 0..<2 {
                let buttons = i == 0 ? buttonConfiguration.1 : buttonConfiguration.0.reversed()
                
                if i == 1 {
                    separationAngleHalf = -separationAngleHalf
                    separationAngle     = -separationAngle
                }
                
                var buttonAngle = separationAngleHalf
                
                for button in buttons {
                    let buttonRotation = simd_quatf(angle: buttonAngle, axis: upDirection)
                    let buttonDirection = buttonRotation.act(direction)
                    
                    let position = fma(buttonDirection, interfaceDepth, headPosition)
                    let orientation = InterfaceElement.createOrientation(forwardDirection: -buttonDirection,
                                                                         orthogonalUpDirection: upDirection)
                    
                    counter.elements[button].hidden = false
                    counter.elements[button].setProperties(position: position, orientation: orientation)
                    
                    buttonAngle += separationAngle
                }
            }
        }
        
        switch presentedInterface {
        case .mainInterface:
            var elementDirection = simd_quatf(angle: degreesToRadians(12 * Self.sizeScale), axis: rotationAxis).act(anchorDirection)
            let elementSeparationRotation = simd_quatf(angle: degreesToRadians(9 * Self.sizeScale), axis: rotationAxis)
            
            for button in PresentedInterface.mainInterface.rectangularButtons {
                let position = fma(elementDirection, interfaceDepth, headPosition)
                let upDirection = cross(elementDirection, rotationAxis)
                let orientation = InterfaceElement.createOrientation(forwardDirection: -elementDirection,
                                                                     orthogonalUpDirection: upDirection)
                
                interfaceElements[button].setProperties(position: position, orientation: orientation)
                interfaceElements[button].hidden = false
                
                elementDirection = elementSeparationRotation.act(elementDirection)
            }
        case .settings, .length, .mass, .angle, .angularVelocity:
            renderBackButton()
            
            let buttons = presentedInterface.rectangularButtons
            var directionAngle: Float
            var separationAngle: Float
            
            if case .settings = presentedInterface {
                directionAngle = degreesToRadians(12 + 10)
                separationAngle = degreesToRadians(10)
            } else {
                directionAngle = degreesToRadians(12 + 9.5)
                separationAngle = degreesToRadians(9.5)
            }
            
            var elementDirection = simd_quatf(angle: directionAngle * Self.sizeScale, axis: rotationAxis).act(anchorDirection)
            let elementSeparationRotation = simd_quatf(angle: separationAngle * Self.sizeScale, axis: rotationAxis)
            
            func renderRectangularButton(_ button: CachedParagraph) {
                let position = fma(elementDirection, interfaceDepth, headPosition)
                let upDirection = cross(elementDirection, rotationAxis)
                let orientation = InterfaceElement.createOrientation(forwardDirection: -elementDirection,
                                                                     orthogonalUpDirection: upDirection)
                
                interfaceElements[button].setProperties(position: position, orientation: orientation)
                interfaceElements[button].hidden = false
                
                elementDirection = elementSeparationRotation.act(elementDirection)
            }
            
            for button in buttons[0..<buttons.count - 1] {
                renderRectangularButton(button)
            }
            
            renderCircularButtons(direction: elementDirection)
            elementDirection = elementSeparationRotation.act(elementDirection)
            
            renderRectangularButton(buttons.last!)
        case .picker(let pickerType):
            renderBackButton()
            
            func renderPicker<T: PendulumParagraphListElement>(picker: inout Picker<T>) {
                picker.hidden = false
                
                let pickerDirection = simd_quatf(angle: degreesToRadians(33 * Self.sizeScale), axis: rotationAxis).act(anchorDirection)
                
                let pickerPosition = fma(pickerDirection, interfaceDepth, headPosition)
                let pickerUpDirection = cross(pickerDirection, rotationAxis)
                let pickerOrientation = InterfaceElement.createOrientation(forwardDirection: -pickerDirection,
                                                                           orthogonalUpDirection: pickerUpDirection)
                
                var t = pickerAnimationProgress
                
                if t < 0 {
                    t = simd_smoothstep(-1, 1, t) * 2 - 1
                }
                
                let selectedElement = picker.selectedElement
                picker.setProperties(position: pickerPosition, orientation: pickerOrientation,
                                     selectedElement: selectedElement, animationProgress: t)
                
                centralRenderer.append(objects: &picker.sideObjects)
                centralRenderer.append(objects: &picker.separatorObjects)
            }
            
            switch pickerType {
            case .property:        renderPicker(picker: &propertyPicker)
            case .length:          renderPicker(picker: &lengthPicker)
            case .mass:            renderPicker(picker: &massPicker)
            case .angle:           renderPicker(picker: &anglePicker)
            case .angularVelocity: renderPicker(picker: &angularVelocityPicker)
            }
        }
    }
    
}
