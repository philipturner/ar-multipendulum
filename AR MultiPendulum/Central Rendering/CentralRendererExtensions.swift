//
//  CentralRendererExtensions.swift
//  AR MultiPendulum
//
//  Created by Philip Turner on 4/19/21.
//

import Metal
import simd

extension CentralRenderer {
    
    func initializeFrameData() {
        didSetRenderPipeline = .zero
        didSetGlobalFragmentUniforms = .zero
        currentlyCulling = .zero
        
        for i in 0..<shapeContainers.count { shapeContainers[i].clearAliases() }
        
        if doingMixedRealityRendering {
            cullTransform = worldToMixedRealityCullTransform
            
            if usingModifiedPerspective {
                lodTransform  = worldToModifiedPerspectiveTransform.appendingTranslation(-cameraSpaceLeftEyePosition)
                lodTransform2 = worldToModifiedPerspectiveTransform.appendingTranslation(-cameraSpaceRightEyePosition)
                
                lodTransformInverse  = modifiedPerspectiveToWorldTransform.prependingTranslation(cameraSpaceLeftEyePosition)
                lodTransformInverse2 = modifiedPerspectiveToWorldTransform.prependingTranslation(cameraSpaceRightEyePosition)
            } else {
                lodTransform  = worldToCameraTransform.appendingTranslation(-cameraSpaceLeftEyePosition)
                lodTransform2 = worldToCameraTransform.appendingTranslation(-cameraSpaceRightEyePosition)
                
                lodTransformInverse  = cameraToWorldTransform.prependingTranslation(cameraSpaceLeftEyePosition)
                lodTransformInverse2 = cameraToWorldTransform.prependingTranslation(cameraSpaceRightEyePosition)
            }
        } else {
            cullTransform = worldToScreenClipTransform
            
            if usingModifiedPerspective {
                lodTransform = worldToModifiedPerspectiveTransform
                lodTransformInverse = modifiedPerspectiveToWorldTransform
            } else {
                lodTransform = worldToCameraTransform
                lodTransformInverse = cameraToWorldTransform
            }
        }
    }
    
    
    
    private func shouldAppend(object: inout CentralObject) -> Bool {
        object.updateTransforms()
        return object.shouldPresent(cullTransform: cullTransform)
    }
    
    func append(object: inout CentralObject) {
        if shouldAppend(object: &object) {
            shapeContainers[object.shapeType.rawValue].appendAlias(of: object)
        }
    }
    
    func append(object: inout CentralObject, desiredLOD: Int) {
        if shouldAppend(object: &object) {
            shapeContainers[object.shapeType.rawValue].appendAlias(of: object, desiredLOD: desiredLOD)
        }
    }
    
    func append(object: inout CentralObject, desiredLOD: Int, userDistanceEstimate: Float) {
        if shouldAppend(object: &object) {
            shapeContainers[object.shapeType.rawValue].appendAlias(of: object, desiredLOD: desiredLOD,
                                                                   userDistanceEstimate: userDistanceEstimate)
        }
    }
    
    
    
    func append(objects: inout [CentralObject]) {
        for i in 0..<objects.count {
            append(object: &objects[i])
        }
    }
    
    func append(objects: inout [CentralObject], desiredLOD: Int) {
        for i in 0..<objects.count {
            append(object: &objects[i], desiredLOD: desiredLOD)
        }
    }
    
    func append(objectGroup: inout CentralObjectGroup, desiredLOD inputLOD: Int? = nil) {
        for i in 0..<objectGroup.objects.count {
            objectGroup.objects[i].updateTransforms()
        }
        
        let objectGroupAlias = CentralObject(aliasing: objectGroup)
        if !objectGroupAlias.shouldPresent(cullTransform: cullTransform) {
            return
        }
        
        let (desiredLOD, userDistanceEstimate) = inputLOD == nil
                                               ? getDistanceAndLOD(of: objectGroupAlias)
                                               : (inputLOD!, getDistance(of: objectGroupAlias))
        
        for object in objectGroup.objects {
            shapeContainers[object.shapeType.rawValue].appendAlias(of: object,
                                                                   desiredLOD: desiredLOD,
                                                                   userDistanceEstimate: userDistanceEstimate)
        }
    }
    
}

extension CentralRenderer {
    
    func getDistance(of object: CentralObject) -> Float {
        if doingMixedRealityRendering {
            return object.userDistance(lodTransform1: lodTransform,
                                       lodTransform2: lodTransform2,
                                       
                                       lodTransformInverse1: lodTransformInverse,
                                       lodTransformInverse2: lodTransformInverse2)
        } else {
            return object.userDistance(lodTransform:        lodTransform,
                                       lodTransformInverse: lodTransformInverse)
        }
    }
    
    func getDistanceAndLOD(of object: CentralObject) -> CentralObject.LODReturn {
        if doingMixedRealityRendering {
            return object.lod(lodTransform1: lodTransform,
                              lodTransform2: lodTransform2,
                              
                              lodTransformInverse1: lodTransformInverse,
                              lodTransformInverse2: lodTransformInverse2)
        } else {
            return object.lod(lodTransform:        lodTransform,
                              lodTransformInverse: lodTransformInverse)
        }
    }
    
}

extension CentralRenderer: GeometryRenderer {
    
    func updateResources() {
        assert(shouldRenderToDisplay)
        
        let globalFragmentUniformPointer = globalFragmentUniformBuffer.contents().assumingMemoryBound(to: GlobalFragmentUniforms.self)
        globalFragmentUniformPointer[renderIndex] = GlobalFragmentUniforms(centralRenderer: self)
        
        for i in 0..<shapeContainers.count { shapeContainers[i].updateResources() }
    }
    
    func drawGeometry(renderEncoder: MTLRenderCommandEncoder, threadID: Int) {
        assert(shouldRenderToDisplay)
        
        guard shapeContainers.contains(where: { $0.numAliases > 0 }) else {
            return
        }
        
        renderEncoder.pushOptDebugGroup("Render Virtual Objects")
        
        shapeContainers.forEach {
            $0.drawGeometry(renderEncoder: renderEncoder, threadID: threadID)
        }
        
        renderEncoder.popOptDebugGroup()
    }
    
}
