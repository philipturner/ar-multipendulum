//
//  PendulumJointConstruction.metal
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/11/21.
//

#include <metal_stdlib>
#include <ARHeadsetKit/ARObjectUtilities.h>
#include "PendulumJointUtilities.h"
using namespace metal;

typedef struct {
    float rectangleHalfWidth;
    float jointRadius;
    float halfDepth;
    
    float minDistance;
    float minDistanceSquared;
    
    bool  doingAmplification;
    bool  usingHeadsetMode;
} ComputeUniforms;

typedef struct {
    half3x3  normalTransform;
    half3    negativeZAxis;
    
    float4x4 modelToWorldTransform;
    float4x4 worldToModelTransform;
    float4x4 cullTransform;
} VertexUniforms;

typedef struct {
    float angleStart;
    float angleStepSize;
    uint  startVertexID;
} AngleRange;

typedef struct {
    uint   edgeVertexIndex;
    ushort baseVertexIndex;
} JointVertex;

typedef struct {
    half2  depthRanges[2];
    float2 position;
} JointBaseVertex;

constant ushort2 axisMaxScaleIndices[3] = {
    { 1, 1 },
    { 0, 0 },
    { 0, 1 }
};

kernel void makePendulumJointMesh(constant float2          *jointOrigins            [[ buffer(0) ]],
                                  constant ComputeUniforms &computeUniforms         [[ buffer(1) ]],
                                  constant VertexUniforms  &vertexUniforms          [[ buffer(2) ]],
                                  
                                  device   AngleRange      *jointAngleRanges        [[ buffer(3) ]],
                                  device   JointBaseVertex *baseVertices            [[ buffer(4) ]],
                                  device   JointVertex     *jointVertices           [[ buffer(5) ]],
                                  
                                  constant float4x4        *worldToCameraTransforms [[ buffer(6) ]],
                                  constant float3          *cameraPositions         [[ buffer(7) ]],
                                  device   atomic_uint     *totalJointTriangleCount [[ buffer(8) ]],
                                  device   atomic_uint     *totalJointVertexCount   [[ buffer(9) ]],
                                  
                                  device   float2          *edgeVertices            [[ buffer(10) ]],
                                  device   half3           *edgeNormals             [[ buffer(11) ]],
                                  
                                  // threadgroup size must be 8
                                  ushort2 id        [[ threadgroup_position_in_grid ]],
                                  ushort2 grid_size [[ threadgroups_per_grid ]],
                                  ushort  thread_id [[ thread_index_in_threadgroup ]])
{
    uint jointID = mad24(id.x, grid_size.y, id.y);
    float depthMultiplier = ((grid_size.x - id.x) << 1) - 1;
    
    float2 origin = jointOrigins[jointID];
    float3 translation(float2(computeUniforms.jointRadius), computeUniforms.halfDepth);
    translation.z = fma(translation.z, depthMultiplier, 1e-4);
    
    ushort quadgroup_id    = thread_id >> 2;
    ushort id_in_quadgroup = thread_id & 3;
    
    if ((thread_id & 1) == 0) { translation.x = -translation.x; }
    if  (id_in_quadgroup < 2) { translation.y = -translation.y; }
    if  (quadgroup_id   == 1) { translation.z = -translation.z; }
    
    float4 cullVertex(origin + translation.xy, float2(translation.z, 1));
    cullVertex = vertexUniforms.cullTransform * cullVertex;

    threadgroup ulong tg_cullMasks[1];

    if (ARObjectUtilities::shouldCull(tg_cullMasks,
                                      cullVertex,
                                      
                                      id_in_quadgroup,
                                      quadgroup_id,
                                      thread_id))
    {
        return;
    }
    
    
    
    using namespace CircleIntersectionUtilities;
    
    threadgroup ulong4 tg_64bytes[2];
    bool2 doingIntersections(id.y > 0, id.y + 1 < grid_size.y);
    
    float3 halfScale = abs(translation);
    float2 otherOrigin;
    
    if (id_in_quadgroup < 2 && doingIntersections[id_in_quadgroup])
    {
        otherOrigin = jointOrigins[jointID + select(-1, 1, id_in_quadgroup != 0)];
        
        auto tg_8bytes = reinterpret_cast<threadgroup float2*>(tg_64bytes) + id_in_quadgroup;
        
        getIntersectionAngleRange(tg_8bytes,
                                  origin, otherOrigin,
                                  halfScale.x,
                                  quadgroup_id);
    }
    
    auto tg_angleRange = reinterpret_cast<threadgroup float*>(tg_64bytes);
    
    float2 angleRanges[2] = {
        { tg_angleRange[0], tg_angleRange[1] },
        { tg_angleRange[2], tg_angleRange[3] },
    };
    
    ushort numValidIntersections = select(0, 1, doingIntersections[0] && !isnan(angleRanges[0].x));
    ushort validIntersectionID = 0;
    
    if (doingIntersections[1] && !isnan(angleRanges[1].x))
    {
        angleRanges[numValidIntersections] = angleRanges[1];
        numValidIntersections += 1;
        validIntersectionID = 1;
    }
    
    
    
    float2 arcSharedPoints[2];
    
    if (numValidIntersections == 1)
    {
        threadgroup float2 tg_otherOrigin[1];
        if (id_in_quadgroup == validIntersectionID) { *tg_otherOrigin = otherOrigin; }
        otherOrigin = *tg_otherOrigin;
        
        arcSharedPoints[0] = (origin + otherOrigin) * 0.5;
    }
    
    if (numValidIntersections == 0)
    {
        angleRanges[0] = { -M_PI_F, M_PI_F };
        arcSharedPoints[0] = origin;
        
        numValidIntersections = 1;
    }
    
    float2 endPoint;
    half2 endNormal;
    
    combineAngleRanges(tg_64bytes,
                       angleRanges,
                       arcSharedPoints,
                       numValidIntersections,
                       endPoint, endNormal,
                       numValidIntersections < 2,
                       
                       origin, halfScale.x,
                       id_in_quadgroup,
                       quadgroup_id);
    
    if (numValidIntersections == 0) { return; }
    
    
    
    LOD lod = ARObjectUtilities::getLOD(tg_64bytes,
                                        vertexUniforms.modelToWorldTransform,
                                        vertexUniforms.worldToModelTransform,
                                        worldToCameraTransforms,
                                        cameraPositions,
                                        computeUniforms.usingHeadsetMode,
                                        
                                        axisMaxScaleIndices,
                                        halfScale, float3(origin, 0),
                                        
                                        id_in_quadgroup,
                                        quadgroup_id,
                                        thread_id);
    
    lod = clamp(lod, LOD(3), LOD(64));
    
    thread float2 &selectedAngleRange = angleRanges[quadgroup_id];
    float angleDifference = selectedAngleRange[1] - selectedAngleRange[0];
    float angleProportion = angleDifference * (1 / (2 * M_PI_F));
    
    float roundedNumSegments = rint(fma(angleProportion, float(lod), 0.5));
    ushort numSegments = max(ushort(roundedNumSegments), ushort(1));
    
    threadgroup ushort tg_numSegments[2];
    tg_numSegments[quadgroup_id] = numSegments;
    
    ushort numSegments1 = tg_numSegments[0];
    ushort totalNumSegments;
    ushort loopNumSegments;
    
    if (numValidIntersections == 2)
    {
        totalNumSegments = numSegments1 + tg_numSegments[1];
        loopNumSegments = numSegments;
    }
    else
    {
        totalNumSegments = numSegments1;
        loopNumSegments = numSegments1;
    }
    
    
    
    threadgroup uint tg_triangleOffset[1];
    threadgroup uint tg_vertexOffset[1];
    
    if (thread_id == 0)
    {
        *tg_triangleOffset = atomic_fetch_add_explicit(totalJointTriangleCount,
                                                       totalNumSegments,
                                                       memory_order_relaxed);
        
        *tg_vertexOffset   = atomic_fetch_add_explicit(totalJointVertexCount,
                                                       totalNumSegments + numValidIntersections,
                                                       memory_order_relaxed);
    }
    
    uint triangleOffset = *tg_triangleOffset;
    uint vertexOffset   = *tg_vertexOffset;
    
    ushort angleRangeID = jointID << 1;
    ushort loopStart = thread_id;
    
    bool amplifyingAnyPendulums = computeUniforms.doingAmplification;
    bool amplifyingSelectedPendulum = id.x + 2 < grid_size.x;
    
    if (numValidIntersections > quadgroup_id)
    {
        if (quadgroup_id == 1)
        {
            triangleOffset += numSegments1;
            vertexOffset   += numSegments1 + 1;
            
            angleRangeID += 1;
            loopStart    -= 4;
        }
        
        if (id_in_quadgroup == 0)
        {
            float angleStepSize = fast::divide(angleDifference, float(numSegments));
            
            jointAngleRanges[angleRangeID] = {
                selectedAngleRange.x, angleStepSize, vertexOffset
            };
            
            JointBaseVertex baseVertex;
            baseVertex.position = arcSharedPoints[quadgroup_id];
            
            halfScale.z -= 1e-4;
            float halfDepth   = computeUniforms.halfDepth;
            float insideDepth = fma(halfDepth, -4, halfScale.z);
            
            float depthOffset = clamp(3e-4 - halfDepth, float(0), 1e-4);
            halfScale.z += depthOffset;
            insideDepth -= depthOffset;
            
            if (amplifyingAnyPendulums)
            {
                if (amplifyingSelectedPendulum)
                {
                    baseVertex.depthRanges[0] = half2(-halfScale.z, -insideDepth);
                    baseVertex.depthRanges[1] = half2( insideDepth,  halfScale.z);
                }
                else
                {
                    baseVertex.depthRanges[0] = half2(-halfScale.z, halfScale.z);
                }
            }
            else
            {
                if (amplifyingSelectedPendulum)
                {
                    baseVertex.depthRanges[0] = half2(-halfScale.z, -insideDepth);
                }
                else
                {
                    baseVertex.depthRanges[0] = half2(-halfScale.z, halfDepth + depthOffset);
                }
            }
            
            baseVertices[angleRangeID] = baseVertex;
            
            uint lastEdgeVertexID = vertexOffset + numSegments;
            edgeVertices[lastEdgeVertexID] = endPoint;
            edgeNormals [lastEdgeVertexID] = vertexUniforms.normalTransform * half3(endNormal, 0);
        }
    }
    
    ushort loopStepSize = 16 >> numValidIntersections;
    auto selectedJointVertices = jointVertices + triangleOffset;
    
    JointVertex jointVertex;
    jointVertex.baseVertexIndex = (angleRangeID << 1) + select(1, 0, amplifyingAnyPendulums && amplifyingSelectedPendulum);
    
    for (ushort i = loopStart; i < loopNumSegments; i += loopStepSize)
    {
        jointVertex.edgeVertexIndex = i;
        selectedJointVertices[i] = jointVertex;
    }
}

kernel void createPendulumJointMeshVertices(constant float2          *jointOrigins     [[ buffer(0) ]],
                                            constant ComputeUniforms &computeUniforms  [[ buffer(1) ]],
                                            constant VertexUniforms  &vertexUniforms   [[ buffer(2) ]],
                                            
                                            constant AngleRange      *jointAngleRanges [[ buffer(3) ]],
                                            device   JointVertex     *jointVertices    [[ buffer(5) ]],
                                            
                                            constant uint            &computeArguments [[ buffer(8) ]],
                                            device   uint            &renderArguments  [[ buffer(9) ]],
                                            
                                            device   float2          *edgeVertices     [[ buffer(10) ]],
                                            device   half3           *edgeNormals      [[ buffer(11) ]],
                                            
                                            uint id [[ thread_position_in_grid ]])
{
    if (id == 0) { renderArguments = computeArguments; }
    
    auto jointVertexPointer = jointVertices + id;
    auto jointVertex = *jointVertexPointer;
    
    auto angleRange = jointAngleRanges[jointVertex.baseVertexIndex >> 1];
    float angle = fma(angleRange.angleStepSize, float(jointVertex.edgeVertexIndex), angleRange.angleStart);
    
    float radius  = computeUniforms.jointRadius;
    float2 origin = jointOrigins[jointVertex.baseVertexIndex >> 2];
    
    float cosval;
    float sinval = fast::sincos(angle, cosval);
    
    uint edgeVertexID = angleRange.startVertexID + jointVertex.edgeVertexIndex;
    edgeVertices[edgeVertexID] = fma(radius, float2(cosval, sinval), origin);
    edgeNormals [edgeVertexID] = vertexUniforms.normalTransform * half3(cosval, sinval, 0);
    
    *reinterpret_cast<device uint*>(jointVertexPointer) = edgeVertexID;
}



kernel void makePendulumJointMesh2(constant float2          *jointOrigins            [[ buffer(0) ]],
                                   constant ComputeUniforms &computeUniforms         [[ buffer(1) ]],
                                   constant VertexUniforms  &vertexUniforms          [[ buffer(2) ]],
                                   
                                   device   AngleRange      *jointAngleRanges        [[ buffer(3) ]],
                                   device   JointBaseVertex *baseVertices            [[ buffer(4) ]],
                                   device   JointVertex     *jointVertices           [[ buffer(5) ]],
                                   
                                   constant float4x4        *worldToCameraTransforms [[ buffer(6) ]],
                                   constant float3          *cameraPositions         [[ buffer(7) ]],
                                   device   atomic_uint     *totalJointTriangleCount [[ buffer(8) ]],
                                   device   atomic_uint     *totalJointVertexCount   [[ buffer(9) ]],
                                   
                                   device   float2          *edgeVertices            [[ buffer(10) ]],
                                   device   half3           *edgeNormals             [[ buffer(11) ]],
                                   
                                  ushort2 id        [[ thread_position_in_grid ]],
                                  ushort2 grid_size [[ threads_per_grid ]])
{
    uint jointID = mad24(id.x, grid_size.y, id.y);
    float depthMultiplier = ((grid_size.x - id.x) << 1) - 1;
    
    float2 origin = jointOrigins[as_type<int>(jointID)];
    float3 translation(float2(computeUniforms.jointRadius), computeUniforms.halfDepth);
    translation.z = fma(translation.z, depthMultiplier, 1e-4);
    
    float4 cullVertices[8];
    
    for (ushort thread_id = 0; thread_id < 8; ++thread_id)
    {
        ushort quadgroup_id    = thread_id >> 2;
        ushort id_in_quadgroup = thread_id & 3;
        
        bool3 comparisons((thread_id & 1) == 0, id_in_quadgroup < 2, quadgroup_id == 1);
        translation = copysign(translation, select(float3(1), float3(-1), comparisons));
        
        float4 cullVertex(origin + translation.xy, float2(translation.z, 1));
        cullVertices[thread_id] = vertexUniforms.cullTransform * cullVertex;
    }
    
    if (ARObjectUtilities::Serial::shouldCull(cullVertices))
    {
        return;
    }
    
    
    
    using namespace CircleIntersectionUtilities::Serial;
    
    bool2 doingIntersections(id.y > 0, id.y + 1 < grid_size.y);
    
    float3 halfScale = abs(translation);
    float2 otherOrigins[2];
    
    float2 angleRanges[2];
    
    for (ushort i = 0; i < 2; ++i)
    {
        if (!doingIntersections[i]) { continue; }
        
        otherOrigins[i] = jointOrigins[as_type<int>(jointID + select(-1, 1, i))];
        
        getIntersectionAngleRange(angleRanges + i, origin, otherOrigins[i], halfScale.x);
    }
    
    ushort numValidIntersections = select(0, 1, doingIntersections[0] && !isnan(angleRanges[0].x));
    ushort validIntersectionID = 0;
    
    if (doingIntersections[1] && !isnan(angleRanges[1].x))
    {
        angleRanges[numValidIntersections] = angleRanges[1];
        numValidIntersections += 1;
        validIntersectionID = 1;
    }
    
    
    
    float2 arcSharedPoints[2];
    
    if (numValidIntersections == 1)
    {
        float2 otherOrigin = otherOrigins[validIntersectionID];
        arcSharedPoints[0] = (origin + otherOrigin) * 0.5;
    }
    
    if (numValidIntersections == 0)
    {
        angleRanges[0] = { -M_PI_F, M_PI_F };
        arcSharedPoints[0] = origin;
        
        numValidIntersections = 1;
    }
    
    float2 endPoints[2];
    half2 endNormals[2];
    
    combineAngleRanges(angleRanges,
                       arcSharedPoints,
                       numValidIntersections,
                       endPoints, endNormals,
                       numValidIntersections < 2,
                       
                       origin, halfScale.x);
    
    if (numValidIntersections == 0) { return; }
    
    
    
    LOD lod = ARObjectUtilities::Serial::getLOD(vertexUniforms.modelToWorldTransform,
                                                vertexUniforms.worldToModelTransform,
                                                worldToCameraTransforms,
                                                cameraPositions,
                                                computeUniforms.usingHeadsetMode,
                                                
                                                axisMaxScaleIndices,
                                                halfScale, float3(origin, 0));
    
    lod = clamp(lod, LOD(3), LOD(64));
    
    ushort2 numSegments;
    float2 angleDifferences;
    
    for (ushort quadgroup_id = 0; quadgroup_id < 2; ++quadgroup_id)
    {
        thread float2 &selectedAngleRange = angleRanges[quadgroup_id];
        float angleDifference = selectedAngleRange[1] - selectedAngleRange[0];
        angleDifferences[quadgroup_id] = angleDifference;
        
        float angleProportion = angleDifference * (1 / (2 * M_PI_F));
        float roundedNumSegments = rint(fma(angleProportion, float(lod), 0.5));
        numSegments[quadgroup_id] = ushort(roundedNumSegments);
    }
    
    ushort totalNumSegments;
    numSegments = max(numSegments, ushort2(1));
    
    if (numValidIntersections == 2) { totalNumSegments = numSegments[0] + numSegments[1]; }
    else                            { totalNumSegments = numSegments[0]; }
    
    
    
    ushort numVertices = totalNumSegments + numValidIntersections;
    ushort angleRangeID = jointID << 1;
    
    uint triangleOffset = atomic_fetch_add_explicit(totalJointTriangleCount, totalNumSegments, memory_order_relaxed);
    uint vertexOffset   = atomic_fetch_add_explicit(totalJointVertexCount,   numVertices,      memory_order_relaxed);
    
    bool amplifyingAnyPendulums = computeUniforms.doingAmplification;
    bool amplifyingSelectedPendulum = id.x + 2 < grid_size.x;
    
    for (ushort quadgroup_id = 0; quadgroup_id < numValidIntersections; ++quadgroup_id)
    {
        if (quadgroup_id == 1)
        {
            triangleOffset += numSegments[0];
            
            vertexOffset += 1;
            angleRangeID += 1;
        }
        
        float angleStepSize = fast::divide(angleDifferences[quadgroup_id], float(numSegments[quadgroup_id]));
        
        jointAngleRanges[angleRangeID] = {
            angleRanges[quadgroup_id].x, angleStepSize, vertexOffset
        };
        
        JointBaseVertex baseVertex;
        baseVertex.position = arcSharedPoints[quadgroup_id];
        
        float halfScaleZ  = halfScale.z - (1e-4);
        float halfDepth   = computeUniforms.halfDepth;
        float insideDepth = fma(halfDepth, -4, halfScaleZ);
        
        float depthOffset = clamp(3e-4 - halfDepth, float(0), 1e-4);
        halfScaleZ  += depthOffset;
        insideDepth -= depthOffset;
        
        if (amplifyingAnyPendulums)
        {
            if (amplifyingSelectedPendulum)
            {
                baseVertex.depthRanges[0] = half2(-halfScaleZ, -insideDepth);
                baseVertex.depthRanges[1] = half2( insideDepth,  halfScaleZ);
            }
            else
            {
                baseVertex.depthRanges[0] = half2(-halfScaleZ, halfScaleZ);
            }
        }
        else
        {
            if (amplifyingSelectedPendulum)
            {
                baseVertex.depthRanges[0] = half2(-halfScaleZ, -insideDepth);
            }
            else
            {
                baseVertex.depthRanges[0] = half2(-halfScaleZ, halfDepth + depthOffset);
            }
        }
        
        baseVertices[as_type<short>(angleRangeID)] = baseVertex;
        vertexOffset += numSegments[quadgroup_id];
        
        edgeVertices[as_type<int>(vertexOffset)] = endPoints[quadgroup_id];
        edgeNormals [as_type<int>(vertexOffset)] = vertexUniforms.normalTransform * half3(endNormals[quadgroup_id], 0);
        
        
        
        auto selectedJointVertices = jointVertices + triangleOffset;
        
        JointVertex jointVertex;
        jointVertex.baseVertexIndex = (angleRangeID << 1) + select(1, 0, amplifyingAnyPendulums && amplifyingSelectedPendulum);
        
        for (ushort i = 0; i < numSegments[quadgroup_id]; ++i)
        {
            jointVertex.edgeVertexIndex = i;
            selectedJointVertices[as_type<short>(i)] = jointVertex;
        }
    }
}
