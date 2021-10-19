//
//  PendulumInterfacePicker.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/17/21.
//

import ARHeadsetKit

protocol PendulumPropertyOption: ARParagraphListElement {
    func update(simulationPrototype: inout PendulumSimulationPrototype)
}

protocol PendulumPickerPanel: ARParagraph {
    associatedtype Option: PendulumPropertyOption
}

fileprivate let panelWidth: Float = 0.24
fileprivate let panelHeight: Float = 0.07

extension PendulumPickerPanel {
    
    static var width: Float { 0.8 * panelWidth }
    static var pixelSize: Float { 0.8 * 0.0002 }
    
    static var parameters: Parameters {
        let paragraphWidth = width - 0.8 * 0.002
        return (stringSegments: [ (label, 0) ], width: paragraphWidth, pixelSize: pixelSize)
    }
    
    static func generateInterfaceElement(type: Option) -> ARInterfaceElement {
        var paragraph = PendulumInterface.Picker<Option>.createParagraph(type)
        let scale = PendulumInterface.interfaceScale
        
        InterfaceRenderer.scaleParagraph(&paragraph, scale: scale)
        
        return .init(position: .zero, forwardDirection: [0, 0, 1], orthogonalUpDirection: [0, 1, 0],
                     width:       width * scale, height: 0.8 * panelHeight * scale,
                     depth: 0.8 * 0.001 * scale, radius: 0,
                     
                     highlightColor: [0.6, 0.8, 1.0], highlightOpacity: 1.0,
                     surfaceColor:   [0.3, 0.5, 0.7], surfaceOpacity: 0.75,
                     characterGroups: paragraph.characterGroups)
    }
    
}

extension PendulumInterface {
    
    struct Picker<CachedParagraph: PendulumPropertyOption>: ARTraceableParagraphContainer {
        var panels: [ARInterfaceElement]
        var selectedPanel: CachedParagraph = .init(rawValue: 0)!
        
        subscript(index: CachedParagraph) -> ARInterfaceElement {
            get { panels[index.rawValue] }
            set { panels[index.rawValue] = newValue }
        }
        
        private var _hidden = false
        var hidden: Bool {
            get { _hidden }
            set {
                if _hidden != newValue {
                    _hidden = newValue
                    
                    for paragraphType in CachedParagraph.allCases {
                        self[paragraphType].hidden = newValue
                    }
                }
            }
        }
        
        private var highlightedPanel: CachedParagraph?
        private var panelToHighlight: CachedParagraph?
        
        fileprivate var boundingObject: ARObject!
        var sideObjects: [ARObject] = []
        var separatorObjects: [ARObject] = []
        
        init() {
            panels = .init(capacity: CachedParagraph.allCases.count)
            
            for panel in CachedParagraph.allCases {
                panels.append(panel.interfaceElement)
            }
        }
        
        mutating func resetSize() {
            for panel in CachedParagraph.allCases {
                self[panel] = panel.interfaceElement
            }
        }
        
        mutating func setProperties(position: simd_float3, orientation: simd_quatf,
                                    selectedPanel: CachedParagraph, animationProgress: Float)
        {
            sideObjects.removeAll(keepingCapacity: true)
            separatorObjects.removeAll(keepingCapacity: true)
            
            if let highlightedPanel = highlightedPanel {
                self[highlightedPanel].isHighlighted = false
            }
            
            let panelArcAngle: Float = degreesToRadians(60)
            
            let xAxis = orientation.act([1, 0, 0])
            let radius = (panelHeight * 0.4 / sin(panelArcAngle / 2) + 0.008) * PendulumInterface.interfaceScale
            let diameter = radius + radius
            
            var boundingObjectEnds: simd_float2x3 = .init(.zero, .zero)
            
            for i in 0..<2 {
                let delta = i == 0 ? xAxis : -xAxis
                let objectStart = fma((panelWidth * 0.4 - 8e-4)  * PendulumInterface.interfaceScale, delta, position)
                let objectEnd   = fma((panelWidth * 0.4 + 0.016) * PendulumInterface.interfaceScale, delta, position)
                
                if animationProgress == -1 {
                    boundingObjectEnds[i] = objectEnd
                }
                
                sideObjects.append(ARObject(roundShapeType: .cylinder,
                                            bottomPosition: objectStart,
                                            topPosition:    objectEnd,
                                            diameter: diameter,
                                            
                                            color: [0.3, 0.3, 0.3])!)
            }
            
            if animationProgress == -1 {
                boundingObject = ARObject(roundShapeType: .cylinder,
                                          bottomPosition: boundingObjectEnds[0],
                                          topPosition:    boundingObjectEnds[1],
                                          diameter: diameter)
            } else {
                boundingObject = nil
            }
            
            
            
            var panelPositions: [(simd_float2, simd_float2)] = .init(repeating: (.zero, .zero), count: CachedParagraph.allCases.count)
            let panelHeightHalf = (panelHeight * 0.8 / 2) * PendulumInterface.interfaceScale
            
            let baseUpper = simd_float2(0,  panelHeightHalf)
            let baseLower = simd_float2(0, -panelHeightHalf)
            panelPositions[selectedPanel.rawValue] = (baseLower, baseUpper)
            
            let angleDelta = simd_clamp(-animationProgress, 0, 1) * panelArcAngle
            var rotationDelta = simd_quatf(angle: angleDelta, axis: [0, 0, 1])
            let panelHeightFull = panelHeightHalf + panelHeightHalf
            
            do {
                var currentPanelDelta = simd_float2(0, panelHeightFull)
                var currentPanelLower = baseUpper
                var i = selectedPanel.rawValue - 1
                
                while i >= 0 {
                    currentPanelDelta = simd_make_float2(rotationDelta.act(.init(currentPanelDelta, 0)))
                    
                    let currentPanelUpper = currentPanelLower + currentPanelDelta
                    panelPositions[i] = (currentPanelLower, currentPanelUpper)
                    
                    currentPanelLower = currentPanelUpper
                    i -= 1
                }
            }
            
            rotationDelta = rotationDelta.conjugate
            
            do {
                var currentPanelDelta = simd_float2(0, -panelHeightFull)
                var currentPanelUpper = baseLower
                var i = selectedPanel.rawValue + 1
                
                while i < CachedParagraph.allCases.count {
                    currentPanelDelta = simd_make_float2(rotationDelta.act(.init(currentPanelDelta, 0)))
                    
                    let currentPanelLower = currentPanelUpper + currentPanelDelta
                    panelPositions[i] = (currentPanelLower, currentPanelUpper)
                    
                    currentPanelUpper = currentPanelLower
                    i += 1
                }
            }
            
            var allSeparatorEnds: [(simd_float3, simd_float3)] = .init(capacity: CachedParagraph.allCases.count + 1)
            
            let yAxis = orientation.act([0, 1, 0])
            let zAxis = orientation.act([0, 0, 1])
            let clampedProgress = simd_clamp(animationProgress, 0, 1)
            
            
            
            let maximumOffsetY = Float(CachedParagraph.allCases.count - 1) * 0.5
            var offsetY = maximumOffsetY - Float(selectedPanel.rawValue)
            offsetY *= clampedProgress * panelHeightFull
            
            let offsetZ = (clampedProgress * 0.04 + (panelHeight * 0.4 / tan(panelArcAngle / 2))) * PendulumInterface.interfaceScale
            
            var origin = fma(yAxis, offsetY, position)
            origin     = fma(zAxis, offsetZ, origin)
            
            @inline(__always)
            func makeSeparatorEnds(modelSpaceCoords: simd_float2) -> (simd_float3, simd_float3) {
                var center = fma(modelSpaceCoords.x, zAxis, origin)
                center     = fma(modelSpaceCoords.y, yAxis, center)
                
                let left = fma((-panelWidth * 0.4 - 8e-4) * PendulumInterface.interfaceScale, xAxis, center)
                let right = fma((panelWidth * 0.4 + 8e-4) * PendulumInterface.interfaceScale, xAxis, center)
                
                return (left, right)
            }
            
            var cachedSeparatorEnds = makeSeparatorEnds(modelSpaceCoords: panelPositions[0].1)
            allSeparatorEnds.append(cachedSeparatorEnds)
            
            for i in 0..<CachedParagraph.allCases.count {
                let currentSeparatorEnds = makeSeparatorEnds(modelSpaceCoords: panelPositions[i].0)
                allSeparatorEnds.append(currentSeparatorEnds)
                
                var panelPosition = currentSeparatorEnds.0 + currentSeparatorEnds.1
                panelPosition += cachedSeparatorEnds.0 + cachedSeparatorEnds.1
                panelPosition *= 0.25
                
                let panelYAxis = normalize(cachedSeparatorEnds.0 - currentSeparatorEnds.0)
                let panelZAxis = cross(xAxis, panelYAxis)
                let orientation = simd_quatf(simd_float3x3(xAxis, panelYAxis, panelZAxis))
                
                let panel = CachedParagraph(rawValue: i)!
                self[panel].setProperties(position: panelPosition, orientation: orientation)
                
                cachedSeparatorEnds = currentSeparatorEnds
            }
            
            for separatorEnds in allSeparatorEnds {
                separatorObjects.append(ARObject(roundShapeType: .cylinder,
                                                 bottomPosition: separatorEnds.0,
                                                 topPosition:    separatorEnds.1,
                                                 diameter: 0.8 * 0.01 * PendulumInterface.interfaceScale,
                                                 
                                                 color: [0.5, 0.5, 0.5])!)
            }
        }
        
        mutating func prepareToHighlight(panel: CachedParagraph) {
            panelToHighlight = panel
        }
        
        mutating func highlightSelectedPanel() {
            guard let panelToHighlight = panelToHighlight else {
                fatalError("Must ensure a panel is highlighted before calling this method")
            }
            
            highlightedPanel = panelToHighlight
            
            self.panelToHighlight = nil
            self[panelToHighlight].isHighlighted = true
        }
    }
    
}
