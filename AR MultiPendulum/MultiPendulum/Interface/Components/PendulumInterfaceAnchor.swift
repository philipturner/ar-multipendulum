//
//  PendulumInterfaceAnchor.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/17/21.
//

import simd

extension PendulumInterface {
    
    struct Anchor {
        var buttonObject: CentralObject
        var symbolObjects: [CentralObject] = []
        
        init(position: simd_float3, orientation: simd_quatf) {
            let xAxis = orientation.act([1, 0, 0])
            let yAxis = orientation.act([0, 1, 0])
            let zAxis = orientation.act([0, 0, 1])
            
            let buttonStart = position - zAxis * 0.025
            let buttonEnd   = position + zAxis * 0.025
            
            buttonObject = CentralObject(roundShapeType: .cylinder,
                                         modelSpaceBottom: buttonStart,
                                         modelSpaceTop: buttonEnd,
                                         diameter: 0.15,
                                         
                                         color: [0.3, 0.3, 0.3])!
            buttonObject.updateTransforms()
            
            
            
            let symbolCenter = buttonEnd + zAxis * 0.025
            
            for i in 0..<2 {
                let delta = i == 0 ? xAxis : yAxis
                let objectStart = symbolCenter - 0.05 * delta
                let objectEnd   = symbolCenter + 0.05 * delta
                
                symbolObjects.append(CentralObject(roundShapeType: .cylinder,
                                                   modelSpaceBottom: objectStart,
                                                   modelSpaceTop: objectEnd,
                                                   diameter: 0.02,
                                                   
                                                   color: [0.5, 0.5, 0.5])!)
            }
            
            for i in 0..<4 {
                var delta = (i & 1) == 0 ? xAxis : yAxis
                if i >= 2 { delta = -delta }
                
                let objectStart = symbolCenter + 0.05 * delta
                let objectEnd   = objectStart  + 0.025 * delta
                
                symbolObjects.append(CentralObject(roundShapeType: .cone,
                                                   modelSpaceBottom: objectStart,
                                                   modelSpaceTop: objectEnd,
                                                   diameter: 0.025,
                                                   
                                                   color: [0.5, 0.5, 0.5])!)
            }
            
            for i in 0..<6 {
                symbolObjects[i].updateTransforms()
            }
        }
        
        mutating func highlight() {
            buttonObject.setColor([0.5, 0.5, 0.5])
            
            for i in 0..<6 {
                symbolObjects[i].setColor([0.7, 0.7, 0.7])
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
    
    func rayTrace(ray worldSpaceRay: RayTracing.Ray) -> Float? {
        let testRay = worldSpaceRay.transformedIntoBoundingBox(boundingBox)
        guard testRay.passesInitialBoundingBoxTest(), testRay.getCentralCubeProgress() != nil else {
            return nil
        }
        
        var minProgress = buttonObject.rayTrace(ray: worldSpaceRay) ?? .greatestFiniteMagnitude
        
        minProgress = symbolObjects.reduce(into: minProgress) {
            guard let progress = $1.rayTrace(ray: worldSpaceRay) else {
                return
            }
            
            $0 = min($0, progress)
        }
        
        return minProgress < .greatestFiniteMagnitude ? minProgress : nil
    }
    
}
