//
//  PendulumFailureTrajectory.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 8/19/21.
//

import simd

extension PendulumRenderer {
    
    struct FailureTrajectory {
        var rectangleObjects: [CentralObject]
        var jointObjects: [CentralObject]
        
        private var state: PendulumState
        private var lengths: [Double]
        private var gravityHalf: Double
        private var linearVelocities: [simd_double2]
        
        init(state: PendulumState, lengths: [Double], gravityHalf: Double) {
            self.state = state
            self.lengths = lengths
            self.gravityHalf = gravityHalf
            
            linearVelocities = .init(unsafeUninitializedCount: lengths.count)
            
            var linearVelocity: simd_double2 = .zero
            
            for i in 0..<lengths.count {
                let sincosValues = __sincos_stret(state.angles[i])
                let velocityScale = lengths[i] * state.angularVelocities[i]
                let velocityDirection = simd_double2(sincosValues.__cosval, sincosValues.__sinval)
                
                linearVelocity = fma(velocityDirection, velocityScale, linearVelocity)
                
                linearVelocities[i] = linearVelocity
            }
            
            rectangleObjects = .init(capacity: lengths.count << 1 - 1)
            jointObjects     = .init(capacity: lengths.count << 1 - 1)
        }
        
        mutating func updateObjects(pendulumRenderer: PendulumRenderer, frameID: Int) {
            rectangleObjects.removeAll(keepingCapacity: true)
            jointObjects.removeAll(keepingCapacity: true)
            
            let depthRangePairs = pendulumRenderer.depthRangePairs
            
            let baseOrientation = pendulumRenderer.pendulumOrientation
            let rotationTransform = simd_float3x3(baseOrientation)
            
            let modelToWorldTransform = simd_float4x4(rotation: rotationTransform,
                                                      translation: pendulumRenderer.pendulumLocation)
            
            let jointDiameter = pendulumRenderer.jointRadius + pendulumRenderer.jointRadius
            let pendulumWidth = pendulumRenderer.pendulumHalfWidth + pendulumRenderer.pendulumHalfWidth
            
            
            
            let time = (Double(frameID) - state.frameProgress) * (1.0 / 60)
            let offsetY = -pendulumRenderer.gravitationalAccelerationHalf * time
            
            for i in 0..<lengths.count {
                var jointPosition2D = fma(linearVelocities[i], time, state.coords[i])
                let angularVelocity = state.angularVelocities[i]
                let initialAngle = state.angles[i] + .pi
                
                let angle_posY = fma(.init(angularVelocity, offsetY), time, .init(initialAngle, jointPosition2D.y))
                let angle         = angle_posY[0]
                jointPosition2D.y = angle_posY[1]
                
                let sincosValues = __sincos_stret(angle)
                let rectangleDirection = simd_double2(sincosValues.__sinval, -sincosValues.__cosval)
                let length = lengths[i]
                let rectanglePosition2D = fma(rectangleDirection, length * 0.5, jointPosition2D)
                
                var jointPosition3D     = simd_float4(lowHalf: .init(jointPosition2D),     highHalf: [0, 1])
                var rectanglePosition3D = simd_float4(lowHalf: .init(rectanglePosition2D), highHalf: [0, 1])
                
                jointPosition3D     = modelToWorldTransform * jointPosition3D
                rectanglePosition3D = modelToWorldTransform * rectanglePosition3D
                
                
                
                let depthRangePair  = depthRangePairs[i]
                let jointScaleZ     = depthRangePair.jointRange.0[1]     - depthRangePair.jointRange.0[0]
                let rectangleScaleZ = depthRangePair.rectangleRange.0[1] - depthRangePair.rectangleRange.0[0]
                
                let jointScale = simd_float3(jointDiameter, jointScaleZ, jointDiameter)
                let rectangleScale = simd_float3(pendulumWidth, Float(length), rectangleScaleZ)
                
                let rectangleOrientation = baseOrientation * simd_quatf(angle: Float(angle), axis: [0, 0, 1])
                let jointOrientation     = baseOrientation * simd_quatf(from: [0, 1, 0], to: [0, 0, 1])
                
                func makeJointObject(depth: Float) {
                    let position = fma(depth, modelToWorldTransform[2], jointPosition3D)
                    
                    jointObjects.append(CentralObject(shapeType: .cylinder,
                                                      position: simd_make_float3(position),
                                                      orientation: jointOrientation,
                                                      scale: jointScale,
                                                      
                                                      color: pendulumRenderer.jointColor))
                }
                
                func makeRectangleObject(depth: Float) {
                    let position = fma(depth, modelToWorldTransform[2], rectanglePosition3D)
                    
                    rectangleObjects.append(CentralObject(shapeType: .cube,
                                                      position: simd_make_float3(position),
                                                      orientation: rectangleOrientation,
                                                      scale: rectangleScale,
                                                      
                                                      color: pendulumRenderer.pendulumColor))
                }
                
                let jointDepth1     = 0.5 * (depthRangePair.jointRange.0[0]     + depthRangePair.jointRange.0[1])
                let rectangleDepth1 = 0.5 * (depthRangePair.rectangleRange.0[0] + depthRangePair.rectangleRange.0[1])
                
                makeJointObject(depth: jointDepth1)
                makeRectangleObject(depth: rectangleDepth1)
                
                if let jointRange2 = depthRangePair.jointRange.1 {
                    makeJointObject(depth: (jointRange2[0] + jointRange2[1]) * 0.5)
                }
                
                if let rectangleRange2 = depthRangePair.rectangleRange.1 {
                    makeRectangleObject(depth: (rectangleRange2[0] + rectangleRange2[1]) * 0.5)
                }
            }
        }
    }
    
}
