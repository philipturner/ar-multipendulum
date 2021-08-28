//
//  PendulumStandRendering.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/19/21.
//

import simd

extension PendulumRenderer {
    
    struct StandState: Equatable {
        var combinedPendulumLength: Double
        var jointRadius: Float
        var pendulumHalfWidth: Float
        var numPendulums: Int
        
        var pendulumColor: simd_float3
        var pendulumLocation: simd_float3
        var pendulumOrientation: simd_quatf
        var doingTwoSidedPendulums: Bool
        
        init(pendulumRenderer: PendulumRenderer) {
            combinedPendulumLength = pendulumRenderer.combinedPendulumLength
            jointRadius            = pendulumRenderer.jointRadius
            pendulumHalfWidth      = pendulumRenderer.pendulumHalfWidth
            numPendulums           = pendulumRenderer.numPendulums
            
            pendulumColor          = pendulumRenderer.pendulumColor
            pendulumLocation       = pendulumRenderer.pendulumLocation
            pendulumOrientation    = pendulumRenderer.pendulumOrientation
            doingTwoSidedPendulums = pendulumRenderer.doingTwoSidedPendulums
        }
    }
    
    @inline(__always)
    func createStandObjects() {
        let standState = StandState(pendulumRenderer: self)
        guard standState != lastStandState else {
            return
        }
        
        lastStandState = standState
        standObjects.removeAll(keepingCapacity: true)
        
        let yAxis = pendulumOrientation.act([0, 1, 0])
        let standHeight = Float(combinedPendulumLength) + jointRadius + 0.05
        var baseTop = pendulumLocation - standHeight * yAxis
        
        let standDiameter: Float = 0.05
        let standCenterToPendulumDistance = standDiameter / 2 + 0.02 + pendulumHalfWidth
        let pivotBackToPendulumDistance = standCenterToPendulumDistance + standDiameter / 2 + 0.001
        
        let zAxis = pendulumOrientation.act([0, 0, 1])
        
        
        
        if !doingTwoSidedPendulums {
            baseTop -= standCenterToPendulumDistance * zAxis
        }
        
        let baseBottom = baseTop - 0.01 * yAxis
            
        standObjects.append(CentralObject(roundShapeType: .cylinder,
                                          modelSpaceBottom: baseBottom,
                                          modelSpaceTop: baseTop,
                                          diameter: 0.30,
                                          
                                          color: standColor)!)
        
        if doingTwoSidedPendulums {
            baseTop -= standCenterToPendulumDistance * zAxis
        }
        
        var standTop = baseTop + standHeight * yAxis
        
        func appendStandObject() {
            standObjects.append(CentralObject(roundShapeType: .cylinder,
                                              modelSpaceBottom: baseTop,
                                              modelSpaceTop: standTop,
                                              diameter: standDiameter,
                                              
                                              color: standColor)!)
        }
        
        appendStandObject()
        
        if doingTwoSidedPendulums {
            baseTop  += (standCenterToPendulumDistance * 2) * zAxis
            standTop += (standCenterToPendulumDistance * 2) * zAxis
            
            appendStandObject()
        }
        
        
        
        let halfDepth = pendulumHalfWidth * Float(simd_fast_recip(Double(numPendulums << 1 - 1)))
        let depthOffset = simd_clamp(3e-4 - halfDepth, 0, 1e-4)
        
        let outsideDepth = pivotBackToPendulumDistance
        let insideDepth = fma(halfDepth, -2, pendulumHalfWidth) - depthOffset
        
        let jointDiameter = jointRadius + jointRadius
        
        func appendPivotObject(depths: simd_float2) {
            let pivotStart = depths[0] * zAxis + pendulumLocation
            let pivotEnd   = depths[1] * zAxis + pendulumLocation
            
            standObjects.append(CentralObject(roundShapeType: .cylinder,
                                              modelSpaceBottom: pivotStart,
                                              modelSpaceTop: pivotEnd,
                                              diameter: jointDiameter,
                                              
                                              color: pivotColor)!)
        }
        
        var depths: simd_float2
        
        if doingTwoSidedPendulums {
            if insideDepth < 0 {
                depths = .init(-outsideDepth, outsideDepth)
            } else {
                depths = .init(-outsideDepth, -insideDepth)
                
                appendPivotObject(depths: .init(insideDepth, outsideDepth))
            }
        } else {
            depths = .init(-outsideDepth, -insideDepth)
        }
        
        appendPivotObject(depths: depths)
    }
    
}
