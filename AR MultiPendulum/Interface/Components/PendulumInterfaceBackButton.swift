//
//  PendulumInterfaceBackButton.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/18/21.
//

import ARHeadsetKit

extension PendulumInterface {
    
    struct BackButton: RayTraceable {
        var element = CachedParagraph.backButton.interfaceElement
        
        mutating func resetSize() {
            element = CachedParagraph.backButton.interfaceElement
        }
        
        func trace(ray worldSpaceRay: RayTracing.Ray) -> Float? {
            element.trace(ray: worldSpaceRay)
        }
    }
    
}

extension PendulumInterface.BackButton: ARParagraph, ARParagraphContainer {
    
    enum CachedParagraph: Int, ARParagraphListElement {
        case backButton
        
        var parameters: Parameters {
            PendulumInterface.BackButton.parameters
        }
        
        var interfaceElement: ARInterfaceElement {
            PendulumInterface.BackButton.generateInterfaceElement(type: self)
        }
    }
    
    static let label = "Back"
    
    fileprivate static let width: Float = 0.8 * 0.15
    fileprivate static let pixelSize: Float = 0.8 * 0.00025
    
    static var parameters: Parameters {
        let paragraphWidth = width - 0.8 * 0.02
        return (stringSegments: [ (label, 2) ], width: paragraphWidth, pixelSize: pixelSize)
    }
    
    fileprivate static func generateInterfaceElement(type: CachedParagraph) -> ARInterfaceElement {
        var paragraph = Self.createParagraph(type)
        let scale = PendulumInterface.interfaceScale
        
        InterfaceRenderer.scaleParagraph(&paragraph, scale: scale)
        
        return .init(position: .zero, forwardDirection: [0, 0, 1], orthogonalUpDirection: [0, 1, 0],
                     width: width * scale, height: 0.8 * 0.08 * scale, depth: 0.8 * 0.05 * scale,
                     radius: .greatestFiniteMagnitude,
                     
                     highlightColor: [0.6, 0.8, 1.0], highlightOpacity: 1.0,
                     surfaceColor:   [0.3, 0.5, 0.7], surfaceOpacity: 0.75,
                     characterGroups: paragraph.characterGroups)
    }
    
}
