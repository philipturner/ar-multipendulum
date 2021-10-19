//
//  RayTracing.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 6/28/21.
//

import simd

protocol RayTraceable {
    associatedtype RayTracingResult
    func rayTrace(ray worldSpaceRay: RayTracing.Ray) -> RayTracingResult
}

enum RayTracing {
    struct Ray: Equatable {
        var origin: simd_float3
        var direction: simd_float3
    }
    
    typealias Plane = (point: simd_float3, normal: simd_float3)
    
    static func getProgress(_ direction: simd_float3, onto plane: Plane) -> Float {
        let dotProducts = dotAdd(plane.normal, plane.point,
                                 plane.normal, direction)
        
        return dotProducts[0] / dotProducts[1]
    }
    
    static func getProgress(_ ray: Ray, onto plane: Plane) -> Float {
        let adjustedPlane = Plane(plane.point - ray.origin, plane.normal)
        
        return getProgress(ray.direction, onto: adjustedPlane)
    }
    
    static func project(_ direction: simd_float3, onto plane: Plane) -> simd_float3 {
        direction * getProgress(direction, onto: plane)
    }
    
    static func project(_ ray: Ray, onto plane: Plane) -> simd_float3 {
        ray.project(progress: getProgress(ray, onto: plane))
    }
}

extension RayTracing.Ray {
    
    func project(progress: Float) -> simd_float3 {
        fma(direction, progress, origin)
    }
    
    // Must guarantee this test returns true before calling
    // any other raytracing functions
    
    func passesInitialBoundingBoxTest() -> Bool {
        let origin_test = abs(origin) .>= 0.5
        
        let direction_sign = sign(direction)
        let point_away_test = direction_sign .== sign(origin)
        let direction_zero_test = direction_sign .== 0
        
        return !any(origin_test .& (point_away_test .| direction_zero_test))
    }
    
    // Must guarantee the indexed direction isn't zero before calling this function
    
    func getBoundingCoordinatePlaneProgress(index: Int) -> Float {
        assert(passesInitialBoundingBoxTest())
        assert(direction[index] != 0)
        
        var planeCoord: Float
        
        if abs(origin[index]) >= 0.5 {
            assert(sign(origin[index]) != sign(direction[index]))
            
            planeCoord = copysign(0.5, origin[index])
        } else {
            planeCoord = copysign(0.5, direction[index])
        }
        
        return (planeCoord - origin[index]) / direction[index]
    }
    
    func getBoundingCoordinatePlaneProgresses() -> simd_float3 {
        assert(passesInitialBoundingBoxTest())
        
        let signSources = direction.replacing(with: origin, where: abs(origin) .>= 0.5)
        let planeCoords = __tg_copysign(.init(repeating: 0.5), signSources)
        
        var output = (planeCoords - origin) / direction
        output.replace(with: .init(repeating: .nan), where: direction .== 0)
        return output
    }
    
    @inline(__always)
    func finishRoundShapeProgress(_ b_half: Float, _ ac: Float) -> Float? {
        assert(passesInitialBoundingBoxTest())
        
        let discriminant_4th = fma(b_half, b_half, -ac)
        guard discriminant_4th >= 0 else { return nil }
        
        let discriminant_sqrt_half = sqrt(discriminant_4th)
        
        let upper_solution = -b_half + discriminant_sqrt_half
        guard upper_solution >= 0 else { return nil }
        
        let lower_solution = -b_half - discriminant_sqrt_half
        return lower_solution >= 0 ? lower_solution : upper_solution
    }
    
    func getProgress(polyhedralShape shape: CentralShapeType) -> Float? {
        assert(passesInitialBoundingBoxTest())
        assert(shape.isPolyhedral)
        
        if shape == .cube {
            return getCentralCubeProgress()
        } else if shape == .squarePyramid {
            return getCentralSquarePyramidProgress()
        } else {
            assert(shape == .octahedron, "Did not update raytracing for new polyhedral shape \(shape.toString)")
            return getCentralOctahedronProgress()
        }
    }
    
    func getProgress(roundShape shape: CentralShapeType) -> Float? {
        assert(passesInitialBoundingBoxTest())
        assert(!shape.isPolyhedral)
        
        if shape == .cylinder {
            return getCentralCylinderProgress()
        } else if shape == .sphere {
            return getCentralSphereProgress()
        } else {
            assert(shape == .cone, "Did not update raytracing for new rounding shape \(shape.toString)")
            return getCentralConeProgress()
        }
    }
    
}
