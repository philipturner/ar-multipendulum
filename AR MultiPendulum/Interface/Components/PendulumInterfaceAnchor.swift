//
//  PendulumInterfaceAnchor.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/17/21.
//

import ARHeadsetKit

extension PendulumInterface {
    
    struct Anchor {
        var buttonObject: ARObject
        var symbolObjects: [ARObject] = []
        
        init(position: simd_float3, orientation: simd_quatf) {
            let xAxis = orientation.act([1, 0, 0])
            let yAxis = orientation.act([0, 1, 0])
            let zAxis = orientation.act([0, 0, 1])
            
            let fullScale = 0.8 * 0.05  * PendulumInterface.interfaceScale
            let halfScale = 0.8 * 0.025 * PendulumInterface.interfaceScale
            
            let buttonStart = fma(-halfScale, zAxis, position)
            let buttonEnd   = fma( halfScale, zAxis, position)
            
            buttonObject = ARObject(roundShapeType: .cylinder,
                                    bottomPosition: buttonStart,
                                    topPosition:    buttonEnd,
                                    diameter: 0.8 * 0.15 * PendulumInterface.interfaceScale,
                                    
                                    color: [0.3, 0.3, 0.3])!
            
            
            
            let symbolCenter = fma(halfScale, zAxis, buttonEnd)
            let directionCylinderDiameter = 0.8 * 0.02 * PendulumInterface.interfaceScale
            
            for i in 0..<2 {
                let delta = i == 0 ? xAxis : yAxis
                let objectStart = fma(-fullScale, delta, symbolCenter)
                let objectEnd   = fma( fullScale, delta, symbolCenter)
                
                symbolObjects.append(ARObject(roundShapeType: .cylinder,
                                              bottomPosition: objectStart,
                                              topPosition:    objectEnd,
                                              diameter: directionCylinderDiameter,
                                              
                                              color: [0.5, 0.5, 0.5])!)
            }
            
            for i in 0..<4 {
                var delta = (i & 1) == 0 ? xAxis : yAxis
                if i >= 2 { delta = -delta }
                
                let objectStart = fma(fullScale, delta, symbolCenter)
                let objectEnd   = fma(halfScale, delta, objectStart)
                
                symbolObjects.append(ARObject(roundShapeType: .cone,
                                              bottomPosition: objectStart,
                                              topPosition:    objectEnd,
                                              diameter: halfScale,
                                              
                                              color: [0.5, 0.5, 0.5])!)
            }
        }
        
        mutating func highlight() {
            buttonObject.color = simd_half3([0.6, 0.6, 0.6])
            
            for i in 0..<6 {
                symbolObjects[i].color = simd_half3([0.8, 0.8, 0.8])
            }
        }
    }
    
}

extension PendulumInterface.Anchor: RayTraceable {
    
    private var boundingBox: simd_float2x3 {
        let output = buttonObject.boundingBox
        
        return symbolObjects.reduce(into: output) {
            let currentBox = $1.boundingBox
            
            $0.columns.0 = min($0.columns.0, currentBox.columns.0)
            $0.columns.1 = max($0.columns.1, currentBox.columns.1)
        }
    }
    
    func trace(ray worldSpaceRay: RayTracing.Ray) -> Float? {
        let testRay = worldSpaceRay.transformedIntoBoundingBox(boundingBox)
        guard testRay.passesInitialBoundingBoxTest(), testRay.getCubeProgress() != nil else {
            return nil
        }
        
        var minProgress = buttonObject.trace(ray: worldSpaceRay) ?? .greatestFiniteMagnitude
        
        minProgress = symbolObjects.reduce(into: minProgress) {
            guard let progress = $1.trace(ray: worldSpaceRay) else {
                return
            }
            
            $0 = min($0, progress)
        }
        
        return minProgress < .greatestFiniteMagnitude ? minProgress : nil
    }
    
}
