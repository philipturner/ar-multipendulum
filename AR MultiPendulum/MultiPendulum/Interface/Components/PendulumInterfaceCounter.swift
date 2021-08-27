//
//  PendulumInterfaceCounter.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/18/21.
//

import simd

extension PendulumInterface {
    
    struct Counter: PendulumIndexContainer, InterfaceParagraphContainer {
        enum CachedParagraph: UInt8, PendulumParagraphList {
            case minus10
            case minus5
            case minus1
            case minusHalf
            case minusTenth
            case minusHundredth
            
            case plusHundredth
            case plusTenth
            case plusHalf
            case plus1
            case plus5
            case plus10
            
            fileprivate var hundredthsChange: Int {
                switch self {
                case .minus10:        return -10_00
                case .minus5:         return -5_00
                case .minus1:         return -1_00
                case .minusHalf:      return -0_50
                case .minusTenth:     return -0_10
                case .minusHundredth: return -0_01
                
                case .plusHundredth:  return 0_01
                case .plusTenth:      return 0_10
                case .plusHalf:       return 0_50
                case .plus1:          return 1_00
                case .plus5:          return 5_00
                case .plus10:         return 10_00
                }
            }
            
            var parameters: Parameters {
                switch self {
                case .minus10:        return Minus10.parameters
                case .minus5:         return Minus5.parameters
                case .minus1:         return Minus1.parameters
                case .minusHalf:      return MinusHalf.parameters
                case .minusTenth:     return MinusTenth.parameters
                case .minusHundredth: return MinusHundredth.parameters
                
                case .plusHundredth:  return PlusHundredth.parameters
                case .plusTenth:      return PlusTenth.parameters
                case .plusHalf:       return PlusHalf.parameters
                case .plus1:          return Plus1.parameters
                case .plus5:          return Plus5.parameters
                case .plus10:         return Plus10.parameters
                }
            }
            
            var interfaceElement: InterfaceRenderer.InterfaceElement {
                switch self {
                case .minus10:        return Minus10       .generateInterfaceElement(type: self)
                case .minus5:         return Minus5        .generateInterfaceElement(type: self)
                case .minus1:         return Minus1        .generateInterfaceElement(type: self)
                case .minusHalf:      return MinusHalf     .generateInterfaceElement(type: self)
                case .minusTenth:     return MinusTenth    .generateInterfaceElement(type: self)
                case .minusHundredth: return MinusHundredth.generateInterfaceElement(type: self)
                    
                case .plusHundredth:  return PlusHundredth .generateInterfaceElement(type: self)
                case .plusTenth:      return PlusTenth     .generateInterfaceElement(type: self)
                case .plusHalf:       return PlusHalf      .generateInterfaceElement(type: self)
                case .plus1:          return Plus1         .generateInterfaceElement(type: self)
                case .plus5:          return Plus5         .generateInterfaceElement(type: self)
                case .plus10:         return Plus10        .generateInterfaceElement(type: self)
                }
            }
        }
        
        enum Mode {
            case numberOfPendulums
            case length
            case gravity
            case angle
            case angularVelocity
            
            typealias ButtonConfiguration = ([CachedParagraph], [CachedParagraph])
            
            var buttonConfiguration: ButtonConfiguration {
                switch self {
                case .numberOfPendulums: return ([          .minus5,     .minus1        ], [.plus1,         .plus5             ])
                case .length:            return ([.minus1,  .minusTenth, .minusHundredth], [.plusHundredth, .plusTenth, .plus1 ])
                case .gravity:           return ([.minus10, .minus1,     .minusTenth    ], [.plusTenth,     .plus1,     .plus10])
                case .angle:             return ([          .minus5,     .minus1        ], [.plus1,         .plus5             ])
                case .angularVelocity:   return ([          .minusHalf,  .minusTenth    ], [.plusTenth,     .plusHalf          ])
                }
            }
        }
        
        private struct Counts {
            private var _numPendulums: Int = 2_00
            private var _combinedLength: Int = 0_50
            private var _gravity: Int = 9_80
            private var _angleDegrees: Int = 126_00
            private var _angularVelocityHz: Int = 0_00
            
            subscript(index: Mode) -> Int {
                get {
                    switch index {
                    case .numberOfPendulums: return _numPendulums
                    case .length:            return _combinedLength
                    case .gravity:           return _gravity
                    case .angle:             return _angleDegrees
                    case .angularVelocity:   return _angularVelocityHz
                    }
                }
                set {
                    switch index {
                    case .numberOfPendulums: _numPendulums      = max(min(newValue, 102400), 100)
                    case .length:            _combinedLength    = max(newValue, 1)
                    case .gravity:           _gravity           = max(newValue, 0)
                    case .angularVelocity:   _angularVelocityHz = newValue
                    case .angle:
                        _angleDegrees = newValue % 36000
                        if _angleDegrees < 0 { _angleDegrees += 36000 }
                    }
                }
            }
            
            var numPendulums: Int         { _numPendulums / 100 }
            var combinedLength: Double    { Double(_combinedLength) * 0.01 }
            var gravity: Double           { Double(_gravity) * 0.01 }
            var angleDegrees: Double      { Double(_angleDegrees) * 0.01 }
            var angularVelocityHz: Double { Double(_angularVelocityHz) * 0.01 }
            
            var clampedAngleDegrees: Double {
                let output = _angleDegrees > 180_00 ? _angleDegrees - 360_00 : _angleDegrees
                return Double(output) * 0.01
            }
        }
        
        private var pendulumInterface: PendulumInterface
        var elements: ParagraphIndexContainer<CachedParagraph>
        
        private var highlightedButton: CachedParagraph?
        
        private var counts: Counts = .init()
        var mode: Mode {
            switch pendulumInterface.baseInterface {
            case .settings:        return .numberOfPendulums
                
            case .length:          return .length
            case .mass:            return .gravity
            case .angle:           return .angle
            case .angularVelocity: return .angularVelocity
                
            case .mainInterface:   fatalError("""
                The `mode` property of PendulumInterface.Counter should never be accessed when using the main interface!
            """)
            }
        }
        
        mutating func hideAllButtons() {
            for button in CachedParagraph.allCases {
                elements[button].hidden = true
            }
        }
        
        init(pendulumInterface: PendulumInterface) {
            self.pendulumInterface = pendulumInterface
            elements = .init(interfaceRenderer: pendulumInterface.interfaceRenderer)
        }
        
        
        
        mutating func resetHighlighting() {
            if let highlightedButton = highlightedButton {
                elements[highlightedButton].isHighlighted = false
                self.highlightedButton = nil
            }
        }
        
        mutating func highlight(button: CachedParagraph) {
            assert(highlightedButton == nil)
            
            highlightedButton = button
            
            elements[button].isHighlighted = true
        }
        
        var measurement: String {
            @inline(__always)
            func convert(_ doubleValue: Double) -> String { .init(format: "%.1f", doubleValue) }
            
            func interpolate(_ doubleValue: Double, _ singularString: String) -> String {
                if abs(abs(doubleValue) - 1) < 1e-3 {
                    return "\(convert(copysign(1, doubleValue)))" + singularString
                } else {
                    return "\(convert(doubleValue))" + singularString + "s"
                }
            }
            
            @inline(__always)
            func addRotationDirection(_ value: Double, _ string: inout String) {
                if abs(value) > 0 {
                    string += " (\(value > 0 ? "\u{21BA}" : "\u{21BB}"))"
                }
            }
            
            switch mode {
            case .numberOfPendulums: return "\(counts.numPendulums)"
            case .length:            return interpolate(counts.combinedLength, " meter")
            case .gravity:           return "\(convert(counts.gravity)) m/s/s"
            case .angle:
                let angleDegrees = counts.clampedAngleDegrees
                var output = interpolate(angleDegrees, " degree")
                
                addRotationDirection(angleDegrees, &output)
                return output
            case .angularVelocity:
                let angularVelocityHz = counts.angularVelocityHz
                var output = "\(interpolate(angularVelocityHz, " rotation"))/s"
                
                addRotationDirection(angularVelocityHz, &output)
                return output
            }
        }
        
        mutating func registerValueChange(button: CachedParagraph) {
            counts[mode] += button.hundredthsChange
        }
        
        func update(simulationPrototype: inout PendulumSimulationPrototype) {
            var shouldReset = false
            
            let newNumPendulums    = counts.numPendulums
            let newCombinedLength  = counts.combinedLength
            let newGravity         = counts.gravity
            let newAnglePercent    = counts.angleDegrees * (200.0 / 360)
            let newAngularVelocity = counts.angularVelocityHz
            
            if newNumPendulums != simulationPrototype.numPendulums {
                simulationPrototype.numPendulums = newNumPendulums
                shouldReset = true
            }
            
            if abs(newCombinedLength - simulationPrototype.combinedPendulumLength) > 1e-3 {
                simulationPrototype.combinedPendulumLength = newCombinedLength
                shouldReset = true
            }
            
            if abs(newGravity - simulationPrototype.gravitationalAcceleration) > 1e-3 {
                simulationPrototype.gravitationalAcceleration = newGravity
                shouldReset = true
            }
            
            if abs(newAnglePercent - simulationPrototype.defaultProperties[.angle]) > 1e-3 {
                simulationPrototype.defaultProperties[.angle] = newAnglePercent
                shouldReset = true
            }
            
            if abs(newAngularVelocity - simulationPrototype.defaultProperties[.angularVelocity]) > 1e-3 {
                simulationPrototype.defaultProperties[.angularVelocity] = newAngularVelocity
                shouldReset = true
            }
            
            if shouldReset {
                simulationPrototype.shouldResetSimulation = true
            }
        }
    }
    
}

// Circular Buttons

fileprivate protocol PendulumInterfaceCircularButton: PendulumInterfaceElement { }

extension PendulumInterface.CircularButton {
    
    typealias Counter = PendulumInterface.Counter
    
    static var width: Float { 0.10 }
    static var height: Float { 0.10 }
    static var pixelSize: Float { 0.0002 }
    
    static var parameters: Parameters {
        let paragraphWidth = width - 0.002
        return (stringSegments: [ (label, 0) ], width: paragraphWidth, pixelSize: pixelSize)
    }
    
    static func generateInterfaceElement(type: Counter.CachedParagraph) -> InterfaceRenderer.InterfaceElement {
        let paragraph = Counter.createParagraph(type)
        
        return .init(position: .zero, forwardDirection: [0, 0, 1], orthogonalUpDirection: [0, 1, 0],
                     width: width, height: height, depth: 0.05, radius: .greatestFiniteMagnitude,
                     
                     highlightColor: [0.5, 0.7, 0.9],
                     surfaceColor:   [0.3, 0.5, 0.7], surfaceOpacity: 0.75,
                     characterGroups: paragraph.characterGroups)
    }
    
}

fileprivate extension PendulumInterface {
    
    typealias CircularButton = PendulumInterfaceCircularButton
    
    enum Minus10:        CircularButton { static let label = "-10" }
    enum Minus5:         CircularButton { static let label = "-5" }
    enum Minus1:         CircularButton { static let label = "-1" }
    enum MinusHalf:      CircularButton { static let label = "-.5" }
    enum MinusTenth:     CircularButton { static let label = "-.1" }
    enum MinusHundredth: CircularButton { static let label = "-.01" }
    
    enum PlusHundredth:  CircularButton { static let label = "+.01" }
    enum PlusTenth:      CircularButton { static let label = "+.1" }
    enum PlusHalf:       CircularButton { static let label = "+.5" }
    enum Plus1:          CircularButton { static let label = "+1" }
    enum Plus5:          CircularButton { static let label = "+5" }
    enum Plus10:         CircularButton { static let label = "+10" }
    
}
