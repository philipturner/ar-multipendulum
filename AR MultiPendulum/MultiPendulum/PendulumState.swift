//
//  PendulumState.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/2/21.
//

import simd

struct PendulumState: Equatable {
    // a timestamp for this state
    // a value of one means 1/60 of a second
    var frameProgress: Double
    
    var angles: [Double]
    var angularVelocities: [Double]!
    var momenta: [Double]!
    
    var coords: [simd_double2]!
    var energy: Double!
    
    static func firstState(_ initialAngles: [Double], _ initialAngularVelocities: [Double]) -> Self {
        Self(frameProgress: 0, angles: initialAngles, angularVelocities: initialAngularVelocities)
    }
    
    init(frameProgress: Double, angles: [Double], angularVelocities: [Double]? = nil, momenta: [Double]? = nil) {
        self.frameProgress = frameProgress
        self.angles = angles
        
        assert(angularVelocities != nil || momenta != nil, "Must provide either angular velocities or momenta!")
        
        self.angularVelocities = angularVelocities
        self.momenta = momenta
    }
    
    mutating func normalizeAngles() {
        for i in 0..<angles.count {
            angles[i] = positiveRemainder(angles[i], 2 * .pi)
        }
    }
    
    mutating func changeAngles(by angleChange: Double) {
        energy = nil
        momenta = nil
        
        let rotation = simd_quatd(angle: angleChange, axis: [0, 0, 1])
        
        for i in 0..<angles.count {
            angles[i] += angleChange
            coords[i] = simd_make_double2(rotation.act(.init(coords[i], 0)))
        }
        
        normalizeAngles()
    }
}

extension PendulumRenderer {
    
    typealias DepthRange = (simd_float2, simd_float2?)
    
    struct DepthRangePair {
        var rectangleRange: DepthRange
        var jointRange: DepthRange
        
        private static func getOuterBounds(_ range: DepthRange) -> simd_float2 {
            simd_float2(range.0[0], range.1?[1] ?? range.0[1])
        }
        
        var outerBounds: (rectangleBounds: simd_float2, jointBounds: simd_float2) {
            (Self.getOuterBounds(rectangleRange), Self.getOuterBounds(jointRange))
        }
    }
    
    var depthRangePairs: [DepthRangePair] {
        var output: [DepthRangePair] = .init(unsafeUninitializedCount: numPendulums)
        
        let halfDepth = pendulumHalfWidth * Float(simd_fast_recip(Double(numPendulums << 1 - 1)))
        let halfDepthVector = simd_float2(repeating: halfDepth)
        let depthOffsets = simd_clamp(simd_float2(2e-4, 3e-4) - halfDepthVector, [-1e-4, 0], [0, 1e-4])
        
        for i in 0..<numPendulums {
            var depths = halfDepthVector * Float((numPendulums - i) << 1 - 1)
            var insideDepths = fma(halfDepthVector, simd_float2(-2, -4), depths)
            
            depths       += depthOffsets
            insideDepths -= depthOffsets
            
            var rectangleRange: DepthRange
            var jointRange: DepthRange
            
            if doingTwoSidedPendulums {
                if i + 2 < numPendulums {
                    rectangleRange = (.init(-depths[0], -insideDepths[0]), .init(insideDepths[0], depths[0]))
                    jointRange     = (.init(-depths[1], -insideDepths[1]), .init(insideDepths[1], depths[1]))
                } else if i + 1 < numPendulums {
                    rectangleRange = (.init(-depths[0], -insideDepths[0]), .init(insideDepths[0], depths[0]))
                    jointRange     = (.init(-depths[1], depths[1]), nil)
                } else {
                    rectangleRange = (.init(insideDepths[0], depths[0]), nil)
                    jointRange     = (.init(-depths[1], depths[1]), nil)
                }
            } else {
                rectangleRange = (.init(-depths[0], -insideDepths[0]), nil)
                
                if i + 1 < numPendulums {
                    jointRange = (.init(-depths[1], -insideDepths[1]), nil)
                } else {
                    jointRange = (.init(-depths[1], halfDepthVector[0] + depthOffsets[1]), nil)
                }
            }
            
            output[i] = .init(rectangleRange: rectangleRange, jointRange: jointRange)
        }
        
        return output
    }
    
}

extension PendulumRenderer: RayTraceable {
    
    func rayTrace(ray worldSpaceRay: RayTracing.Ray) -> (stateID: Int, pendulumID: Int, isJoint: Bool, progress: Float)? {
        guard let states = meshConstructor.statesToRender, states.count > 0 else {
            return nil
        }
        
        let rotationInverse = pendulumOrientation.conjugate
        let modelSpaceOrigin = rotationInverse.act(worldSpaceRay.origin - pendulumLocation)
        let modelSpaceDirection = rotationInverse.act(worldSpaceRay.direction)
        
        var pendulumWidthReciprocal: Float
        
        do {
            let pendulumHalfWidth = Double(self.pendulumHalfWidth)
            let pendulumWidth = pendulumHalfWidth + pendulumHalfWidth
            let simulationDiameter = combinedPendulumLength + combinedPendulumLength
            
            let reciprocalValues = simd_float2(simd_fast_recip(.init(simulationDiameter, pendulumWidth)))
            let diameterReciprocal  = reciprocalValues[0]
            pendulumWidthReciprocal = reciprocalValues[1]
            
            let inverseScale = simd_float3(diameterReciprocal, diameterReciprocal, pendulumWidthReciprocal)
            let testRay = RayTracing.Ray(origin: modelSpaceOrigin * inverseScale, direction: modelSpaceDirection * inverseScale)
            
            guard testRay.passesInitialBoundingBoxTest(), testRay.getCentralCylinderProgress() != nil else {
                return nil
            }
        }
        
        let depthRangePairs = self.depthRangePairs
        var rectangleDepthReciprocal: Float
        var jointDiameterReciprocal: Float
        
        do {
            let range = depthRangePairs[0].rectangleRange
            let depth = range.0[1] - range.0[0]
            let diameter = jointRadius + jointRadius
            
            let reciprocalValues = simd_float2(simd_fast_recip(.init(Double(depth), Double(diameter))))
            rectangleDepthReciprocal = reciprocalValues[0]
            jointDiameterReciprocal  = reciprocalValues[1]
        }
        
        var currentCoordinates = UnsafeMutablePointer<simd_float2>.allocate(capacity: states.count)
        var cachedCoordinates  = UnsafeMutablePointer<simd_float2>.allocate(capacity: states.count)
        cachedCoordinates.assign(repeating: .zero, count: states.count)
        
        let modelSpaceRay = RayTracing.Ray(origin: modelSpaceOrigin, direction: modelSpaceDirection)
        
        
        
        var maxStateID = states.count - 1
        var minProgress: Float = .greatestFiniteMagnitude
        
        var intersectionPendulumID: Int?
        var intersectionIsJoint = false
        
        @inline(__always)
        func updateRayTracingResult(stateID: Int, pendulumID: Int, isJoint: Bool, progress: Float) {
            if stateID < maxStateID || progress < minProgress {
                maxStateID  = stateID
                minProgress = progress
                
                intersectionPendulumID = pendulumID
                intersectionIsJoint    = isJoint
            }
        }
        
        for i in 0..<numPendulums {
            defer { swap(&cachedCoordinates, &currentCoordinates) }
            
            var rectangleBounds2D = simd_float2x2(.init(repeating:  .greatestFiniteMagnitude),
                                                  .init(repeating: -.greatestFiniteMagnitude))
            
            var jointBounds2D = simd_float2x2(.init(repeating:  .greatestFiniteMagnitude),
                                              .init(repeating: -.greatestFiniteMagnitude))
            
            for j in 0...maxStateID {
                let selectedCurrentCoordinates = simd_float2(states[j].coords[i])
                jointBounds2D[0] = min(jointBounds2D[0], selectedCurrentCoordinates)
                jointBounds2D[1] = max(jointBounds2D[1], selectedCurrentCoordinates)
                
                let selectedCachedCoordinates = cachedCoordinates[j]
                rectangleBounds2D[0] = min(rectangleBounds2D[0], min(selectedCurrentCoordinates, selectedCachedCoordinates))
                rectangleBounds2D[1] = max(rectangleBounds2D[1], max(selectedCurrentCoordinates, selectedCachedCoordinates))
                
                currentCoordinates[j] = selectedCurrentCoordinates
            }
            
            jointBounds2D[0] -= jointRadius
            jointBounds2D[1] += jointRadius
            
            
            
            let depthRangePair = depthRangePairs[i]
            let outerBounds = depthRangePair.outerBounds
            
            @inline(__always)
            func testBox(_ boundingBox: simd_float2x3) -> Bool {
                let transformedRay = modelSpaceRay.transformedIntoBoundingBox(boundingBox)
                
                if transformedRay.passesInitialBoundingBoxTest(), transformedRay.getCentralCubeProgress() != nil {
                    return true
                } else {
                    return false
                }
            }
            
            let rectangleBoundingBox = simd_float2x3(.init(rectangleBounds2D[0], outerBounds.rectangleBounds[0]),
                                                     .init(rectangleBounds2D[1], outerBounds.rectangleBounds[1]))
            
            let jointBoundingBox = simd_float2x3(.init(jointBounds2D[0], outerBounds.jointBounds[0]),
                                                 .init(jointBounds2D[1], outerBounds.jointBounds[1]))
            
            let combinedBoundingBox = simd_float2x3(min(rectangleBoundingBox[0], jointBoundingBox[0]),
                                                    max(rectangleBoundingBox[1], jointBoundingBox[1]))
            
            guard testBox(combinedBoundingBox) else {
                continue
            }
            
            @inline(__always)
            func testComponent(isJoint: Bool) -> (Bool, Bool) {
                var selectedBoundingBox = isJoint ? jointBoundingBox : rectangleBoundingBox
                
                var insideBounds1 = testBox(selectedBoundingBox)
                var insideBounds2 = false
                
                let selectedDepthRange = isJoint ? depthRangePair.jointRange : depthRangePair.rectangleRange
                
                if insideBounds1, let secondRange = selectedDepthRange.1 {
                    selectedBoundingBox[1].z = selectedDepthRange.0[1]
                    insideBounds1 = testBox(selectedBoundingBox)
                    
                    selectedBoundingBox[0].z = secondRange[0]
                    selectedBoundingBox[1].z = secondRange[1]
                    insideBounds2 = testBox(selectedBoundingBox)
                }
                
                return (insideBounds1, insideBounds2)
            }
            
            let (insideRectangleBounds1, insideRectangleBounds2) = testComponent(isJoint: false)
            let (insideJointBounds1,     insideJointBounds2)     = testComponent(isJoint: true)
            
            guard insideRectangleBounds1 || insideJointBounds1 ||
                  insideRectangleBounds2 || insideJointBounds2 else {
                continue
            }
            
            
            
            let pendulumLengthReciprocal = Float(simd_fast_recip(lengths[i]))
            let rectangleInverseScale = simd_float3(pendulumWidthReciprocal, pendulumLengthReciprocal, rectangleDepthReciprocal)
            
            var j = 0
            
            repeat {
                let jointCenter = currentCoordinates[j]
                var jointProgress: Float
                
                func testJoint(depthRange: simd_float2) -> Float? {
                    func flip(_ ray: RayTracing.Ray) -> RayTracing.Ray {
                        .init(origin:    .init(ray.origin.x,    ray.origin.z,    ray.origin.y),
                              direction: .init(ray.direction.x, ray.direction.z, ray.direction.y))
                    }
                    
                    let centerZ = (depthRange[0] + depthRange[1]) * 0.5
                    let testOrigin = modelSpaceRay.origin - simd_float3(jointCenter, centerZ)
                    let testDirection = modelSpaceRay.direction
                    
                    let inverseScaleZ = Float(simd_fast_recip(Double(depthRange[1] - depthRange[0])))
                    let inverseScale = simd_float3(.init(repeating: jointDiameterReciprocal), inverseScaleZ)
                    let testRay = flip(RayTracing.Ray(origin: testOrigin * inverseScale, direction: testDirection * inverseScale))
                    
                    if testRay.passesInitialBoundingBoxTest(), let progress = testRay.getCentralCylinderProgress() {
                        return progress
                    } else {
                        return nil
                    }
                }
                
                if insideJointBounds1, let progress = testJoint(depthRange: depthRangePair.jointRange.0) {
                    jointProgress = progress
                } else {
                    jointProgress = .greatestFiniteMagnitude
                }
                
                if insideJointBounds2, let progress = testJoint(depthRange: depthRangePair.jointRange.1!) {
                    jointProgress = min(jointProgress, progress)
                }
                
                if jointProgress < .greatestFiniteMagnitude {
                    updateRayTracingResult(stateID: j, pendulumID: i, isJoint: true, progress: jointProgress)
                }
                
                
                
                let end   = jointCenter
                let start = cachedCoordinates[j]
                var rectangleProgress: Float
                
                func testRectangle(depthRange: simd_float2) -> Float? {
                    let directionVector = simd_float3(normalize(end - start), 0)
                    let rotation = simd_quatf(from: directionVector, to: [0, 1, 0])
                    
                    let center = simd_float3(start + end, depthRange[0] + depthRange[1]) * 0.5
                    var testOrigin = modelSpaceRay.origin - center
                    var testDirection = modelSpaceRay.direction
                    
                    testOrigin    = rotation.act(testOrigin)
                    testDirection = rotation.act(testDirection)
                    
                    let inverseScale = rectangleInverseScale
                    let testRay = RayTracing.Ray(origin: testOrigin * inverseScale, direction: testDirection * inverseScale)
                    
                    if testRay.passesInitialBoundingBoxTest(), let progress = testRay.getCentralCubeProgress() {
                        return progress
                    } else {
                        return nil
                    }
                }
                
                if insideRectangleBounds1, let progress = testRectangle(depthRange: depthRangePair.rectangleRange.0) {
                    rectangleProgress = progress
                } else {
                    rectangleProgress = .greatestFiniteMagnitude
                }
                
                if insideRectangleBounds2, let progress = testRectangle(depthRange: depthRangePair.rectangleRange.1!) {
                    rectangleProgress = min(jointProgress, progress)
                }
                
                if rectangleProgress < .greatestFiniteMagnitude {
                    updateRayTracingResult(stateID: j, pendulumID: i, isJoint: true, progress: rectangleProgress)
                }
                
                j += 1
            }
            while j <= maxStateID
        }
        
        free(cachedCoordinates)
        free(currentCoordinates)
        
        if let intersectionPendulumID = intersectionPendulumID {
            return (maxStateID, intersectionPendulumID, intersectionIsJoint, minProgress)
        } else {
            return nil
        }
    }
    
}
