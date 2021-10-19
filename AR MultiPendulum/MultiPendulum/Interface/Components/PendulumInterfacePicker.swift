//
//  PendulumInterfacePicker.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/17/21.
//

import simd

protocol PendulumInterfacePicker: PendulumParagraphListElement {
    func update(simulationPrototype: inout PendulumSimulationPrototype)
}

protocol PendulumInterfacePickerElement: PendulumInterfaceElement {
    associatedtype PickerOption: PendulumInterfacePicker
}

fileprivate let panelWidth: Float = 0.24
fileprivate let panelHeight: Float = 0.07

extension PendulumInterface.PickerElement {
    
    typealias Picker = PendulumInterface.Picker
    
    static var width: Float { panelWidth }
    static var pixelSize: Float { 0.0002 }
    
    static var parameters: Parameters {
        let paragraphWidth = width - 0.002
        return (stringSegments: [ (label, 0) ], width: paragraphWidth, pixelSize: pixelSize)
    }
    
    static func generateInterfaceElement(type: PickerOption) -> InterfaceRenderer.InterfaceElement {
        var paragraph = Picker<PickerOption>.createParagraph(type)
        let scale = PendulumInterface.sizeScale
        
        InterfaceRenderer.scaleParagraph(&paragraph, scale: scale)
        
        return .init(position: .zero, forwardDirection: [0, 0, 1], orthogonalUpDirection: [0, 1, 0],
                     width: width * scale, height: panelHeight * scale,
                     depth: 0.001 * scale, radius: 0,
                     
                     highlightColor: [0.6, 0.8, 1.0], highlightOpacity: 1.0,
                     surfaceColor:   [0.3, 0.5, 0.7], surfaceOpacity: 0.75,
                     characterGroups: paragraph.characterGroups)
    }
    
}

extension PendulumInterface {
    
    typealias PickerElement = PendulumInterfacePickerElement
    
    struct Picker<ListElement: PendulumInterfacePicker>: PendulumIndexContainer, InterfaceParagraphContainer {
        typealias CachedParagraph = ListElement
        var elements: ParagraphIndexContainer<ListElement>
        var selectedElement: CachedParagraph
        
        private var _hidden = false
        var hidden: Bool {
            get { _hidden }
            set {
                if _hidden != newValue {
                    _hidden = newValue
                    
                    for paragraphType in ListElement.allCases {
                        elements[paragraphType].hidden = newValue
                    }
                }
            }
        }
        
        private var highlightedElement: CachedParagraph?
        private var elementToHighlight: CachedParagraph?
        
        fileprivate var boundingObject: CentralObject!
        var sideObjects: [CentralObject] = []
        var separatorObjects: [CentralObject] = []
        
        init(interfaceRenderer: InterfaceRenderer) {
            elements = .init(interfaceRenderer: interfaceRenderer)
            selectedElement = CachedParagraph(rawValue: 0)!
        }
        
        mutating func resetSize() {
            elements.resetSize()
            
            for paragraphType in ListElement.allCases {
                elements[paragraphType].hidden = true
            }
        }
        
        mutating func setProperties(position: simd_float3, orientation: simd_quatf,
                                    selectedElement: CachedParagraph, animationProgress: Float) {
            sideObjects.removeAll(keepingCapacity: true)
            separatorObjects.removeAll(keepingCapacity: true)
            
            if let highlightedElement = highlightedElement {
                elements[highlightedElement].isHighlighted = false
            }
            
            let panelArcAngle: Float = degreesToRadians(60)
            
            let xAxis = orientation.act([1, 0, 0])
            let radius = (panelHeight / 2 / sin(panelArcAngle / 2) + 0.01) * PendulumInterface.sizeScale
            let diameter = radius + radius
            
            var boundingObjectEnds: simd_float2x3 = .init(.zero, .zero)
            
            for i in 0..<2 {
                let delta = i == 0 ? xAxis : -xAxis
                let objectStart = fma((panelWidth / 2 - 0.001) * PendulumInterface.sizeScale, delta, position)
                let objectEnd   = fma((panelWidth / 2 + 0.020) * PendulumInterface.sizeScale, delta, position)
                
                if animationProgress == -1 {
                    boundingObjectEnds[i] = objectEnd
                }
                
                sideObjects.append(CentralObject(roundShapeType: .cylinder,
                                                 modelSpaceBottom: objectStart,
                                                 modelSpaceTop: objectEnd,
                                                 diameter: diameter,
                                                 
                                                 color: [0.3, 0.3, 0.3])!)
            }
            
            if animationProgress == -1 {
                boundingObject = CentralObject(roundShapeType: .cylinder,
                                               modelSpaceBottom: boundingObjectEnds[0],
                                               modelSpaceTop: boundingObjectEnds[1],
                                               diameter: diameter)
            } else {
                boundingObject = nil
            }
            
            
            
            var panelPositions: [(simd_float2, simd_float2)] = .init(repeating: (.zero, .zero), count: ListElement.allCases.count)
            let panelHeightHalf = (panelHeight / 2) * PendulumInterface.sizeScale
            
            let baseUpper = simd_float2(0,  panelHeightHalf)
            let baseLower = simd_float2(0, -panelHeightHalf)
            panelPositions[Int(selectedElement.rawValue)] = (baseLower, baseUpper)
            
            let angleDelta = simd_clamp(-animationProgress, 0, 1) * panelArcAngle
            var rotationDelta = simd_quatf(angle: angleDelta, axis: [0, 0, 1])
            let panelHeightFull = panelHeightHalf + panelHeightHalf
            
            do {
                var currentPanelDelta = simd_float2(0, panelHeightFull)
                var currentPanelLower = baseUpper
                var i = Int(selectedElement.rawValue) - 1
                
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
                var i = Int(selectedElement.rawValue) + 1
                
                while i < ListElement.allCases.count {
                    currentPanelDelta = simd_make_float2(rotationDelta.act(.init(currentPanelDelta, 0)))
                    
                    let currentPanelLower = currentPanelUpper + currentPanelDelta
                    panelPositions[i] = (currentPanelLower, currentPanelUpper)
                    
                    currentPanelUpper = currentPanelLower
                    i += 1
                }
            }
            
            var allSeparatorEnds: [(simd_float3, simd_float3)] = .init(capacity: ListElement.allCases.count + 1)
            
            let yAxis = orientation.act([0, 1, 0])
            let zAxis = orientation.act([0, 0, 1])
            let clampedProgress = simd_clamp(animationProgress, 0, 1)
            
            
            
            let maximumOffsetY = Float(ListElement.allCases.count - 1) * 0.5
            var offsetY = maximumOffsetY - Float(selectedElement.rawValue)
            offsetY *= clampedProgress * panelHeightFull
            
            let offsetZ = (clampedProgress * 0.05 + (panelHeight / 2 / tan(panelArcAngle / 2))) * PendulumInterface.sizeScale
            
            var origin = fma(yAxis, offsetY, position)
            origin     = fma(zAxis, offsetZ, origin)
            
            @inline(__always)
            func makeSeparatorEnds(modelSpaceCoords: simd_float2) -> (simd_float3, simd_float3) {
                var center = fma(modelSpaceCoords.x, zAxis, origin)
                center     = fma(modelSpaceCoords.y, yAxis, center)
                
                let left = fma((-panelWidth / 2 - 0.001) * PendulumInterface.sizeScale, xAxis, center)
                let right = fma((panelWidth / 2 + 0.001) * PendulumInterface.sizeScale, xAxis, center)
                
                return (left, right)
            }
            
            var cachedSeparatorEnds = makeSeparatorEnds(modelSpaceCoords: panelPositions[0].1)
            allSeparatorEnds.append(cachedSeparatorEnds)
            
            for i in 0..<ListElement.allCases.count {
                let currentSeparatorEnds = makeSeparatorEnds(modelSpaceCoords: panelPositions[i].0)
                allSeparatorEnds.append(currentSeparatorEnds)
                
                var elementPosition = currentSeparatorEnds.0 + currentSeparatorEnds.1
                elementPosition += cachedSeparatorEnds.0 + cachedSeparatorEnds.1
                elementPosition *= 0.25
                
                let elementYAxis = normalize(cachedSeparatorEnds.0 - currentSeparatorEnds.0)
                let elementZAxis = cross(xAxis, elementYAxis)
                let orientation = simd_quatf(simd_float3x3(xAxis, elementYAxis, elementZAxis))
                
                let element = CachedParagraph(rawValue: UInt8(i))!
                elements[element].setProperties(position: elementPosition, orientation: orientation)
                
                cachedSeparatorEnds = currentSeparatorEnds
            }
            
            for separatorEnds in allSeparatorEnds {
                separatorObjects.append(CentralObject(roundShapeType: .cylinder,
                                                      modelSpaceBottom: separatorEnds.0,
                                                      modelSpaceTop: separatorEnds.1,
                                                      diameter: 0.01 * PendulumInterface.sizeScale,
                                                      
                                                      color: [0.5, 0.5, 0.5])!)
            }
        }
        
        mutating func prepareToHighlight(element: CachedParagraph) {
            elementToHighlight = element
        }
        
        mutating func highlightSelectedElement() {
            guard let elementToHighlight = elementToHighlight else {
                fatalError("Must ensure an element is highlighted before calling this method")
            }
            
            highlightedElement = elementToHighlight
            self.elementToHighlight = nil
            
            elements[elementToHighlight].isHighlighted = true
        }
    }
    
}

extension PendulumInterface.Picker: RayTraceable {
    
    func rayTrace(ray worldSpaceRay: RayTracing.Ray) -> Float? {
        guard boundingObject.rayTrace(ray: worldSpaceRay) != nil else {
            return nil
        }
        
        var minProgress: Float
        
        if let progress = sideObjects.rayTrace(ray: worldSpaceRay) {
            minProgress = progress
        } else {
            minProgress = .greatestFiniteMagnitude
        }
        
        if let progress = separatorObjects.rayTrace(ray: worldSpaceRay), progress < minProgress {
            minProgress = progress
        }
        
        if let progress = elements.rayTrace(ray: worldSpaceRay)?.progress, progress < minProgress {
            minProgress = progress
        }
        
        return minProgress < .greatestFiniteMagnitude ? minProgress : nil
    }
    
}
