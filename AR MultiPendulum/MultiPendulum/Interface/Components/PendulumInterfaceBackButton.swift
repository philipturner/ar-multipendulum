//
//  PendulumInterfaceBackButton.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/18/21.
//

import simd

extension PendulumInterface {
    
    struct BackButton: RayTraceable {
        private var interfaceRenderer: InterfaceRenderer
        private var index: Int
        
        var element: InterfaceRenderer.InterfaceElement {
            get { interfaceRenderer.interfaceElements[index] }
            set { interfaceRenderer.interfaceElements[index] = newValue }
        }
        
        init(interfaceRenderer: InterfaceRenderer) {
            self.interfaceRenderer = interfaceRenderer
            index = interfaceRenderer.interfaceElements.count
            
            interfaceRenderer.interfaceElements.append(CachedParagraph.backButton.interfaceElement)
        }
        
        func rayTrace(ray worldSpaceRay: RayTracing.Ray) -> Float? {
            element.rayTrace(ray: worldSpaceRay)
        }
    }
    
}

extension PendulumInterface.BackButton: PendulumInterfaceElement, InterfaceParagraphContainer {
    
    enum CachedParagraph: UInt8, PendulumParagraphList {
        case backButton
        
        var parameters: Parameters {
            PendulumInterface.BackButton.parameters
        }
        
        var interfaceElement: InterfaceRenderer.InterfaceElement {
            PendulumInterface.BackButton.generateInterfaceElement(type: self)
        }
    }
    
    static let label = "Back"
    
    fileprivate static let width: Float = 0.15
    fileprivate static let pixelSize: Float = 0.00025
    
    static var parameters: Parameters {
        let paragraphWidth = width - 0.02
        return (stringSegments: [ (label, 1) ], width: paragraphWidth, pixelSize: pixelSize)
    }
    
    fileprivate static func generateInterfaceElement(type: CachedParagraph) -> InterfaceRenderer.InterfaceElement {
        let paragraph = Self.createParagraph(type)
        
        return .init(position: .zero, forwardDirection: [0, 0, 1], orthogonalUpDirection: [0, 1, 0],
                     width: width, height: 0.08, depth: 0.05, radius: .greatestFiniteMagnitude,
                     
                     highlightColor: [0.5, 0.7, 0.9],
                     surfaceColor:   [0.3, 0.5, 0.7], surfaceOpacity: 0.75,
                     characterGroups: paragraph.characterGroups)
        
        
    }
    
}
