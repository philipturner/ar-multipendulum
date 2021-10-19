//
//  PendulumInterfaceRendering.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/18/21.
//

import ARHeadsetKit

extension PendulumInterface {
    
    func adjustInterface(headPosition: simd_float3) {
        let rotationAxis = normalize(cross([0, 1, 0], anchorDirection))
        
        let anchorPosition = fma(anchorDirection, interfaceDepth, headPosition)
        let anchorUpDirection = cross(anchorDirection, rotationAxis)
        let anchorOrientation = ARInterfaceElement.createOrientation(forwardDirection: -anchorDirection,
                                                                     orthogonalUpDirection: anchorUpDirection)
        
        anchor = Anchor(position: anchorPosition, orientation: anchorOrientation)
        
        func adjustBackButton() {
            backButton.element.hidden = false
            
            let elementDirection = simd_quatf(angle: degreesToRadians(0.8 * 12 * interfaceScale), axis: rotationAxis).act(anchorDirection)
            let upDirection = cross(elementDirection, rotationAxis)
            
            let position = fma(elementDirection, interfaceDepth, headPosition)
            let orientation = ARInterfaceElement.createOrientation(forwardDirection: -elementDirection,
                                                                   orthogonalUpDirection: upDirection)
            
            backButton.element.setProperties(position: position, orientation: orientation)
        }
        
        @inline(__always)
        func adjustCircularButtons(direction: simd_float3) {
            var separationAngle: Float = -degreesToRadians(0.8 * 10 * interfaceScale)
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
                    let orientation = ARInterfaceElement.createOrientation(forwardDirection: -buttonDirection,
                                                                           orthogonalUpDirection: upDirection)
                    
                    counter[button].setProperties(position: position, orientation: orientation)
                    counter[button].hidden = false
                    
                    buttonAngle += separationAngle
                }
            }
        }
        
        switch presentedInterface {
        case .mainInterface:
            var elementDirection = simd_quatf(angle: degreesToRadians(0.8 * 12 * interfaceScale), axis: rotationAxis).act(anchorDirection)
            let elementSeparationRotation = simd_quatf(angle: degreesToRadians(0.8 * 9 * interfaceScale), axis: rotationAxis)
            
            for button in PresentedInterface.mainInterface.rectangularButtons {
                let position = fma(elementDirection, interfaceDepth, headPosition)
                let upDirection = cross(elementDirection, rotationAxis)
                let orientation = ARInterfaceElement.createOrientation(forwardDirection: -elementDirection,
                                                                       orthogonalUpDirection: upDirection)
                
                interfaceElements[button].setProperties(position: position, orientation: orientation)
                interfaceElements[button].hidden = false
                
                elementDirection = elementSeparationRotation.act(elementDirection)
            }
        case .settings, .length, .mass, .angle, .angularVelocity:
            adjustBackButton()
            
            let buttons = presentedInterface.rectangularButtons
            var directionAngle: Float
            var separationAngle: Float
            
            if case .settings = presentedInterface {
                directionAngle = 0.8 * degreesToRadians(12 + 10)
                separationAngle = 0.8 * degreesToRadians(10)
            } else {
                directionAngle = 0.8 * degreesToRadians(12 + 9.5)
                separationAngle = 0.8 * degreesToRadians(9.5)
            }
            
            var elementDirection = simd_quatf(angle: directionAngle * interfaceScale, axis: rotationAxis).act(anchorDirection)
            let elementSeparationRotation = simd_quatf(angle: separationAngle * interfaceScale, axis: rotationAxis)
            
            func adjustRectangularButton(_ button: CachedParagraph) {
                let position = fma(elementDirection, interfaceDepth, headPosition)
                let upDirection = cross(elementDirection, rotationAxis)
                let orientation = ARInterfaceElement.createOrientation(forwardDirection: -elementDirection,
                                                                       orthogonalUpDirection: upDirection)
                
                interfaceElements[button].setProperties(position: position, orientation: orientation)
                interfaceElements[button].hidden = false
                
                elementDirection = elementSeparationRotation.act(elementDirection)
            }
            
            for button in buttons[0..<buttons.count - 1] {
                adjustRectangularButton(button)
            }
            
            adjustCircularButtons(direction: elementDirection)
            elementDirection = elementSeparationRotation.act(elementDirection)
            
            adjustRectangularButton(buttons.last!)
        case .picker(let pickerType):
            adjustBackButton()
            
            func adjustPicker<T: PendulumPropertyOption>(picker: inout Picker<T>) {
                picker.hidden = false
                
                let pickerDirection = simd_quatf(angle: degreesToRadians(0.8 * 33 * interfaceScale), axis: rotationAxis).act(anchorDirection)
                
                let pickerPosition = fma(pickerDirection, interfaceDepth, headPosition)
                let pickerUpDirection = cross(pickerDirection, rotationAxis)
                let pickerOrientation = ARInterfaceElement.createOrientation(forwardDirection: -pickerDirection,
                                                                             orthogonalUpDirection: pickerUpDirection)
                
                var t = pickerAnimationProgress
                
                if t < 0 {
                    t = simd_smoothstep(-1, 1, t) * 2 - 1
                }
                
                let selectedPanel = picker.selectedPanel
                picker.setProperties(position: pickerPosition, orientation: pickerOrientation,
                                     selectedPanel: selectedPanel, animationProgress: t)
                
                centralRenderer.render(objects: picker.sideObjects)
                centralRenderer.render(objects: picker.separatorObjects)
            }
            
            switch pickerType {
            case .property:        adjustPicker(picker: &propertyPicker)
            case .length:          adjustPicker(picker: &lengthPicker)
            case .mass:            adjustPicker(picker: &massPicker)
            case .angle:           adjustPicker(picker: &anglePicker)
            case .angularVelocity: adjustPicker(picker: &angularVelocityPicker)
            }
        }
    }
    
}
