//
//  InterfaceElement.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/28/21.
//

import SwiftUI
import simd

extension InterfaceRenderer {
    
    struct InterfaceElement {
        private var centralObject: CentralObject
        private var inverseScale: simd_float4
        
        private(set) var radius: Float
        private(set) var controlPoints: simd_float4x2
        private(set) var normalTransform: simd_half3x3
        
        var surfaceColor: simd_packed_half3 {
            get { centralObject.color }
            set { centralObject.color = newValue }
        }
        
        var surfaceShininess: Float16 {
            get { centralObject.shininess }
            set { centralObject.shininess = newValue }
        }
        
        var baseSurfaceColor: simd_half3
        var highlightedSurfaceColor: simd_half3
        var surfaceOpacity: Float
        
        private var _isHighlighted = false
        var isHighlighted: Bool {
            get { _isHighlighted }
            set {
                surfaceColor = .init(newValue ? highlightedSurfaceColor : baseSurfaceColor)
                _isHighlighted = newValue
            }
        }
        
        var textColor: simd_half3
        var textShininess: Float16
        var textOpacity: Float16
        
        var hidden = false
        
        var characterGroups: [CharacterGroup?]
        
        static func createOrientation(forwardDirection: simd_float3, orthogonalUpDirection: simd_float3) -> simd_quatf {
            let xAxis = cross(orthogonalUpDirection, forwardDirection)
            return simd_quatf(simd_float3x3(xAxis, orthogonalUpDirection, forwardDirection))
        }
        
        init(position: simd_float3, forwardDirection: simd_float3, orthogonalUpDirection: simd_float3,
             width: Float, height: Float, depth: Float, radius: Float,
             
             highlightColor: simd_float3 = [0.2, 0.2, 0.9],
             surfaceColor:   simd_float3 = [0.1, 0.1, 0.8], surfaceShininess: Float = 32, surfaceOpacity: Float = 1.0,
             textColor:      simd_float3 = [0.9, 0.9, 0.9], textShininess:    Float = 32, textOpacity:    Float = 1.0,
             characterGroups: [CharacterGroup?])
        {
            let orientation = Self.createOrientation(forwardDirection: forwardDirection,
                                                     orthogonalUpDirection: orthogonalUpDirection)
            
            centralObject = CentralObject(shapeType: .cube,
                                          position: position,
                                          orientation: orientation,
                                          scale: simd_float3(width, height, depth),
                                          
                                          color: surfaceColor,
                                          shininess: surfaceShininess)
            centralObject.updateTransforms()
            
            self.radius = max(min(radius, min(width, height) * 0.5), 0)
            inverseScale = simd_precise_recip(simd_float4(width, height, depth, self.radius))
            
            controlPoints = Self.getControlPoints(width: width, height: height, radius: self.radius)
            normalTransform = simd_half3x3(simd_float3x3(orientation))
            
            baseSurfaceColor        = .init(surfaceColor)
            highlightedSurfaceColor = .init(highlightColor)
            self.surfaceOpacity     = surfaceOpacity
            
            self.textColor      = .init(textColor)
            self.textShininess  = .init(textShininess)
            self.textOpacity    = .init(textOpacity)
            
            self.characterGroups = characterGroups
        }
        
        private static func getControlPoints(width: Float, height: Float, radius: Float) -> simd_float4x2 {
            let outerX = width  * 0.5
            let outerY = height * 0.5
            
            let innerX = outerX - radius
            let innerY = outerY - radius
            
            return simd_float4x2(
                .init(innerX, outerX),
                .init(innerY, outerY),
                .init(innerX, outerX),
                .init(innerY, outerY)
            )
        }
        
        
        
        var position: simd_float3 { centralObject.position }
        var orientation: simd_quatf { centralObject.orientation }
        var scale: simd_float3 { centralObject.scale }
        
        mutating func setProperties(position: simd_float3? = nil,
                                    orientation: simd_quatf? = nil,
                                    scale: simd_float3? = nil,
                                    radius: Float? = nil) {
            if let position = position {
                centralObject.position = position
            }
            
            if let orientation = orientation {
                centralObject.orientation = orientation
                normalTransform = simd_half3x3(simd_float3x3(orientation))
            }
            
            if let scale = scale {
                centralObject.scale = scale
            }
            
            if let radius = radius {
                self.radius = max(radius, 0)
            }
            
            if scale != nil || radius != nil {
                inverseScale = simd_precise_recip(simd_float4(centralObject.scale, self.radius))
                
                controlPoints = Self.getControlPoints(width: centralObject.scale.x,
                                                      height: centralObject.scale.y,
                                                      radius: self.radius)
            }
            
            if position != nil || orientation != nil || scale != nil {
                centralObject.updateTransforms()
            }
        }
        
        
        
        var modelToWorldTransform: simd_float4x4 {
            centralObject.assertTransformsUpdated()
            
            var output = centralObject.modelToWorldTransform
            output[0] *= inverseScale.x
            output[1] *= inverseScale.y
            
            return output
        }
        
        func frontIsVisible(projectionTransform: simd_float4x4) -> Bool {
            let worldSpacePointA = simd_make_float3(centralObject.modelToWorldTransform * [-0.5, -0.5, 0.5, 1])
            let worldSpacePointB = simd_make_float3(centralObject.modelToWorldTransform * [ 0.5,  0.5, 0.5, 1])
            let worldSpacePointC = simd_make_float3(centralObject.modelToWorldTransform * [-0.5,  0.5, 0.5, 1])
            
            let pointA = projectionTransform * simd_float4(worldSpacePointA, 1)
            let pointB = projectionTransform * simd_float4(worldSpacePointB, 1)
            let pointC = projectionTransform * simd_float4(worldSpacePointC, 1)
            
            let reciprocalW = simd_precise_recip(simd_float3(pointA.w, pointB.w, pointC.w))
            let clipCoords = simd_float3x2(
                pointA.lowHalf * reciprocalW[0],
                pointB.lowHalf * reciprocalW[1],
                pointC.lowHalf * reciprocalW[2]
            )
            
            return simd_orient(clipCoords[1] - clipCoords[0], clipCoords[2] - clipCoords[0]) >= 0
        }
        
        func frontIsVisible(cameraMeasurements: CameraMeasurements) -> Bool {
            if cameraMeasurements.doingMixedRealityRendering {
                if frontIsVisible(projectionTransform: cameraMeasurements.worldToLeftClipTransform) {
                    return true
                }
                
                return frontIsVisible(projectionTransform: cameraMeasurements.worldToRightClipTransform)
            } else {
                return frontIsVisible(projectionTransform: cameraMeasurements.worldToScreenClipTransform)
            }
        }
        
        func shouldPresent(cullTransform worldToClipTransform: simd_float4x4) -> Bool {
            !hidden && centralObject.shouldPresent(cullTransform: worldToClipTransform)
        }
        
        func shouldPresent(cameraMeasurements: CameraMeasurements) -> Bool {
            guard !hidden else { return false }
            
            let cullTransform = cameraMeasurements.renderer.centralRenderer.cullTransform
            return centralObject.shouldPresent(cullTransform: cullTransform)
        }
    }
    
}

extension InterfaceRenderer.InterfaceElement: RayTraceable {
    
    func rayTrace(ray worldSpaceRay: RayTracing.Ray) -> Float? {
        guard !hidden, let initialProgress = centralObject.rayTrace(ray: worldSpaceRay) else {
            return nil
        }
        
        if radius == 0 { return initialProgress }
        
        var modelToWorldTransform = self.modelToWorldTransform
        modelToWorldTransform[2] *= inverseScale.z
        
        let worldToModelTransform = modelToWorldTransform.inverseRotationTranslation
        let worldSpaceIntersection = worldSpaceRay.project(progress: initialProgress)
        var modelSpaceIntersection = simd_make_float3(worldToModelTransform * simd_float4(worldSpaceIntersection, 1))
        
        let controlX = controlPoints[0][0]
        let controlY = controlPoints[1][0]
        
        if abs(modelSpaceIntersection.x) <= controlX ||
           abs(modelSpaceIntersection.y) <= controlY {
            return initialProgress
        }
        
        var modelSpaceOrigin = simd_make_float3(worldToModelTransform * simd_float4(worldSpaceRay.origin, 1))
        modelSpaceOrigin       = .init(modelSpaceOrigin.x,       modelSpaceOrigin.z,       modelSpaceOrigin.y)
        modelSpaceIntersection = .init(modelSpaceIntersection.x, modelSpaceIntersection.z, modelSpaceIntersection.y)
        
        let radiusMultiplier = inverseScale.w * 0.5
        let rayScaleMultiplier = simd_float3(radiusMultiplier, inverseScale.z, radiusMultiplier)
        let rayDirection = (modelSpaceIntersection - modelSpaceOrigin) * rayScaleMultiplier
        
        var finalProgress = Float.greatestFiniteMagnitude
        
        func testCorner(x: Float, z: Float) {
            let rayOrigin = (modelSpaceOrigin - simd_float3(x, 0, z)) * rayScaleMultiplier
            let testRay = RayTracing.Ray(origin: rayOrigin, direction: rayDirection)
            guard testRay.passesInitialBoundingBoxTest() else { return }
            
            if let testProgress = testRay.getCentralCylinderProgress(), testProgress < finalProgress {
                finalProgress = testProgress
            }
        }
        
        func testSide(x: Float) {
            if modelSpaceIntersection.z > controlY || controlY <= 1e-8 {
                testCorner(x: x, z: controlY)
            }
            
            if modelSpaceIntersection.z < -controlY, controlY > 1e-8 {
                testCorner(x: x, z: -controlY)
            }
        }
        
        if modelSpaceIntersection.x > controlX || controlX <= 1e-8 {
            testSide(x: controlX)
        }
        
        if modelSpaceIntersection.x < -controlX, controlX > 1e-8 {
            testSide(x: -controlX)
        }
        
        if finalProgress < .greatestFiniteMagnitude {
            return initialProgress * finalProgress
        } else {
            return nil
        }
    }
    
}

