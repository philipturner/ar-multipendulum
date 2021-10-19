//
//  PendulumSimulationPrototype.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/2/21.
//

import ARHeadsetKit

struct PendulumSimulationConfiguration {
    var numPendulums: Int
    var gravitationalAccelerationHalf: Double
    
    var masses: [Double]
    var lengths: [Double]
    var initialAngles: [Double]
    var initialAngularVelocities: [Double]
}

struct PendulumSimulationPrototype {
    private var _numPendulums = 2
    var numPendulums: Int {
        get { _numPendulums }
        set(rawNewValue) {
            let newValue = min(max(1, rawNewValue), 1024)
            let previousValue = _numPendulums
            
            if previousValue < newValue {
                for propertyType in PropertyType.allCases {
                    customProperties[propertyType] = .init(repeating: defaultProperties[propertyType],
                                                               count: newValue)
                }
            }
            
            _numPendulums = newValue
        }
    }
    
    var combinedPendulumLength: Double = 0.5
    var gravitationalAcceleration: Double = 9.8
    
    enum PropertyType: Int, CaseIterable {
        case length
        case mass
        case angle
        case angularVelocity
    }
    
    struct PropertyContainer<Element>: ExpressibleByArrayLiteral {
        private var array: [Element]
        
        init(repeating repeatedValue: Element) {
            array = Array(repeating: repeatedValue, count: PropertyType.allCases.count)
        }
        
        typealias ArrayLiteralElement = Element
        
        init(arrayLiteral elements: Element...) {
            array = elements
        }
        
        subscript(index: PropertyType) -> Element {
            get { array[index.rawValue] }
            set { array[index.rawValue] = newValue }
        }
    }
    
    var defaultProperties: PropertyContainer<Double> = [1, 1, 70, 0]
    var doingCustomProperties: PropertyContainer = .init(repeating: false)
    private var initializedCustomProperties: PropertyContainer = .init(repeating: false)
    
    private var customProperties: PropertyContainer<[Double]> = .init(repeating: [])
    private var storedRandomProperties: PropertyContainer<[Double]> = .init(repeating: [])
    private var storedCustomProperties: PropertyContainer<[Double]> = .init(repeating: [])
    
    enum LengthType {
        case random
        case endIsLonger
        case endIsShorter
        case custom
    }
    
    enum MassType {
        case random
        case endIsHeavier
        case endIsLighter
        case custom
    }
    
    enum AnglePercentType {
        case random
        case staircase
        case spiral
        case custom
    }
    
    enum AngularVelocityType {
        case random
        case custom
    }
    
    var customLengthType: LengthType = .random
    var customMassType: MassType = .random
    var customAngleType: AnglePercentType = .random
    var customAngularVelocityType: AngularVelocityType = .random
    var loadedProperty: PropertyType = .length
    
    var doingLengthNormalization = true
    var didUncheckLengthNormalization = false
    var shouldResetSimulation = false
    
    var configuration: PendulumSimulationConfiguration {
        mutating get {
            .init(numPendulums: numPendulums,
                  gravitationalAccelerationHalf: 0.5 * gravitationalAcceleration,
                  
                  masses: getMasses(usingStoredRandom: false),
                  lengths: getLengths(usingStoredRandom: false),
                  initialAngles: getInitialAnglesInRadians(usingStoredRandom: false),
                  initialAngularVelocities: getInitialAngularVelocities(usingStoredRandom: false))
        }
    }
    
    mutating func changeCombinedLength(newLength: Double) {
        if newLength != combinedPendulumLength {
            combinedPendulumLength = newLength
            shouldResetSimulation = true
        }
    }
    
    mutating func setAllToDefault() {
        let defaultProperty = defaultProperties[loadedProperty]
        let pendulumCapacity = customProperties[loadedProperty].count
        customProperties[loadedProperty] = .init(repeating: defaultProperty, count: pendulumCapacity)
    }
    
    mutating func setPropertyElement(_ index: Int, rawNewValue: Double?) {
        var newValue = rawNewValue ?? 1
        
        if loadedProperty == .angle {
            newValue *= 1 / 1.8
        } else if loadedProperty == .angularVelocity {
            newValue *= 2 * .pi
        }
        
        customProperties[loadedProperty][index] = newValue
        shouldResetSimulation = true
    }
    
    mutating func ensurePropertyInitialized(_ propertyType: PropertyType) {
        guard !initializedCustomProperties[propertyType] else {
            return
        }
        
        initializedCustomProperties[propertyType] = true
        
        var defaultProperty: Double
        
        if propertyType == .length, !didUncheckLengthNormalization {
            defaultProperty = combinedPendulumLength / Double(numPendulums)
            defaultProperty = Double(String(format: "%.4f", defaultProperty))!
            
            defaultProperties[.length] = defaultProperty
        } else {
            defaultProperty = defaultProperties[propertyType]
        }
        
        for i in 0..<customProperties[propertyType].count {
            customProperties[propertyType][i] = defaultProperty
        }
    }
    
    mutating func getLengths(usingStoredRandom: Bool = false) -> [Double] {
        guard doingCustomProperties[.length] else {
            var length: Double
            
            if doingLengthNormalization {
                length = combinedPendulumLength / Double(numPendulums)
            } else {
                length = defaultProperties[.length]
                changeCombinedLength(newLength: length * Double(numPendulums))
            }
            
            return Array(repeating: length, count: numPendulums)
        }
        
        var output: [Double]
        
        switch customLengthType {
        case .random:
            if usingStoredRandom {
                output = storedRandomProperties[.length]
            } else {
                output = randomLengths
                storedRandomProperties[.length] = output
            }
        case .endIsLonger:
            output = endIsLongerLengths
        case .endIsShorter:
            output = endIsShorterLengths
        case .custom:
            output = customProperties[.length]
        }
        
        let combinedPendulumLength = output.reduce(0, +)
        
        if doingLengthNormalization {
            let multiplier = self.combinedPendulumLength / combinedPendulumLength
            output = output.map{ $0 * multiplier }
        } else {
            changeCombinedLength(newLength: combinedPendulumLength)
        }
        
        return output
    }
    
    mutating func getMasses(usingStoredRandom: Bool = false) -> [Double] {
        guard doingCustomProperties[.mass] else {
            return Array(repeating: defaultProperties[.mass], count: numPendulums)
        }
        
        switch customMassType {
        case .random:
            if usingStoredRandom {
                return storedRandomProperties[.mass]
            } else {
                let output = randomMasses
                storedRandomProperties[.mass] = output
                return output
            }
        case .endIsHeavier:
            return endIsHeavierMasses
        case .endIsLighter:
            return endIsLighterMasses
        case .custom:
            return customProperties[.mass]
        }
    }
    
    mutating func getInitialAnglesInRadians(usingStoredRandom: Bool = false) -> [Double] {
        var outputPercents: [Double]
        
        if !doingCustomProperties[.angle] {
            outputPercents = Array(repeating: defaultProperties[.angle], count: numPendulums)
        } else {
            switch customAngleType {
            case .random:
                if usingStoredRandom {
                    outputPercents = storedRandomProperties[.angle]
                } else {
                    outputPercents = randomAnglePercents
                    storedRandomProperties[.angle] = outputPercents
                }
            case .staircase:
                outputPercents = staircaseAnglePercents
            case .spiral:
                outputPercents = spiralAnglePercents
            case .custom:
                outputPercents = customProperties[.angle]
            }
        }
        
        return outputPercents.map{ $0 * (0.01 * .pi) }
    }
    
    mutating func getInitialAngularVelocities(usingStoredRandom: Bool = false) -> [Double] {
        guard doingCustomProperties[.angularVelocity] else {
            return Array(repeating: defaultProperties[.angularVelocity], count: numPendulums)
        }
        
        switch customAngularVelocityType {
        case .random:
            if usingStoredRandom {
                return storedRandomProperties[.angularVelocity]
            } else {
                let output = randomAngularVelocities
                storedRandomProperties[.angularVelocity] = output
                return output
            }
        case .custom:
            return customProperties[.angularVelocity]
        }
    }
    
}
