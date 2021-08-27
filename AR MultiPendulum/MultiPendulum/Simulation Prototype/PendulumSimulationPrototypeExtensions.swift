//
//  PendulumSimulationPrototypeExtensions.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/2/21.
//

import simd

extension PendulumSimulationPrototype {
    
    @inline(__always)
    private func getRandomProperty(min: Double, max: Double) -> [Double] {
        (0..<numPendulums).map{ _ in simd_mix(min, max, drand48()) }
    }
    
    @inline(__always)
    private func getInterpolatedProperty(start: Double, end: Double) -> [Double] {
        let multiplier = simd_fast_recip(Double(numPendulums - 1))
        return (0..<numPendulums).map{ simd_mix(start, end, Double($0) * multiplier) }
    }
    
    // Lengths
    
    var randomLengths: [Double] {
        let defaultLength = defaultProperties[.length]
        return getRandomProperty(min: 0.1 * defaultLength, max: defaultLength + defaultLength)
    }
    
    var endIsLongerLengths: [Double] {
        let defaultLength = defaultProperties[.length]
        guard numPendulums > 1 else { return [defaultLength] }
        
        return getInterpolatedProperty(start: 0.1 * defaultLength, end: defaultLength + defaultLength)
    }
    
    var endIsShorterLengths: [Double] {
        let defaultLength = defaultProperties[.length]
        guard numPendulums > 1 else { return [defaultLength] }
        
        return getInterpolatedProperty(start: defaultLength + defaultLength, end: 0.1 * defaultLength)
    }
    
    // Masses
    
    var randomMasses: [Double] {
        let defaultMass = defaultProperties[.mass]
        return getRandomProperty(min: 0.1 * defaultMass, max: defaultMass + defaultMass)
    }
    
    var endIsHeavierMasses: [Double] {
        let defaultMass = defaultProperties[.mass]
        guard numPendulums > 1 else { return [defaultMass] }
        
        return getInterpolatedProperty(start: 0.1 * defaultMass, end: defaultMass + defaultMass)
    }
    
    var endIsLighterMasses: [Double] {
        let defaultMass = defaultProperties[.mass]
        guard numPendulums > 1 else { return [defaultMass] }
        
        return getInterpolatedProperty(start: defaultMass + defaultMass, end: 0.1 * defaultMass)
    }
    
    // Angles
    
    var randomAnglePercents: [Double] { getRandomProperty(min: 0, max: 200) }
    
    var staircaseAnglePercents: [Double] { (0..<numPendulums).map{ $0 & 1 == 0 ? 50 : 100 } }
    
    var spiralAnglePercents: [Double] {
        guard numPendulums > 1 else {
            return [ 51 ]
        }
        
        let multipier = simd_fast_recip(Double(numPendulums - 1))
        return (0..<numPendulums).map{ simd_mix(51, 500, sqrt(Double($0) * multipier)) }
    }
    
    // Angular Velocities
    
    var randomAngularVelocities: [Double] { getRandomProperty(min: -5, max: 5) }
}
