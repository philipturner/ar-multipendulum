//
//  Shaders.metal
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/8/21.
//

#include <metal_stdlib>
#include "../../Other/Utilities/Metal/ColorUtilities.metal"
using namespace metal;

typedef struct {
    half3x3  normalTransform;
    half3    negativeZAxis;
    
    float4x4 modelToWorldTransform;
    float4x4 worldToModelTransform;
    
    float4x4 projectionTransforms[1];
    float4x3 eyeDirectionTransforms[1];
} VertexUniforms;

typedef struct {
    half3x3  normalTransform;
    half3    negativeZAxis;
    
    float4x4 modelToWorldTransform;
    float4x4 worldToModelTransform;
    float4x4 cullTransform;
    
    float4x4 projectionTransforms[2];
    float4x3 eyeDirectionTransforms[2];
} MRVertexUniforms;

typedef struct {
    half3 ambientLightColor;
    half3 ambientInsideLightColor;
    
    half3 directionalLightColor;
    half3 lightDirection;
} GlobalFragmentUniforms;

typedef struct {
    packed_half3 modelColor;
    half         shininess;
} FragmentUniforms;



#define VertexInOut_Common          \
float4 position [[position]];       \
half3  eyeDirection_notNormalized;  \
half3  normal_notNormalized;        \

typedef struct {
    VertexInOut_Common;
} VertexInOut;

typedef struct {
    VertexInOut_Common;
    ushort layer [[render_target_array_index]];
} MRVertexInOut;

#define PENDULUM_RECTANGLE_TRANSFORM_PARAMS(VertexUniforms)     \
constant     bool           &isPerimeter     [[ buffer(0) ]],   \
constant     VertexUniforms &vertexUniforms  [[ buffer(1) ]],   \
constant     half           *depths          [[ buffer(2) ]],   \
                                                                \
const device float2         *vertices        [[ buffer(3) ]],   \
const device ushort4        *triangleIndices [[ buffer(4) ]],   \
const device ushort3        *lineIndices     [[ buffer(5) ]],   \
                                                                \
ushort iid [[ instance_id ]],                                   \
ushort vid [[ vertex_id ]]                                      \

#define PENDULUM_JOINT_TRANSFORM_PARAMS(VertexUniforms)         \
constant     VertexUniforms  &vertexUniforms [[ buffer(1) ]],   \
const device JointBaseVertex *baseVertices   [[ buffer(2) ]],   \
                                                                \
const device JointVertex     *jointVertices  [[ buffer(3) ]],   \
const device float2          *edgeVertices   [[ buffer(4) ]],   \
const device half3           *edgeNormals    [[ buffer(5) ]],   \
                                                                \
ushort iid [[ instance_id ]],                                   \
ushort vid [[ vertex_id ]]                                      \



template <typename VertexInOut, typename VertexUniforms>
VertexInOut pendulumRectangleTransformCommon(PENDULUM_RECTANGLE_TRANSFORM_PARAMS(VertexUniforms), ushort amp_id,
                                             bool usingAmplification, float3 eyeDirectionDelta, float positionDelta)
{
    bool   isAmplified;
    bool   depthRangeMask;
    ushort depthRangeIndex;
    
    float3 position;
    half3  normal;
    
    ushort2 selectedIndices;
    
    if (!isPerimeter)
    {
        isAmplified = vid >= 6;
        if (isAmplified) { vid -= 6; }
        
        depthRangeIndex = isAmplified;
        
        constexpr ushort2 indices[6] = {
            { 0, 1 },
            { 1, 1 },
            { 2, 1 },
            
            { 2, 0 },
            { 1, 0 },
            { 0, 0 },
        };
        
        selectedIndices = indices[vid];
        
        
        
        ushort4 selectedTriangleIndices = triangleIndices[iid];
        depthRangeMask   = selectedTriangleIndices.w & 1;
        depthRangeIndex += selectedTriangleIndices.w & (__UINT16_MAX__ - 1);
        
        ushort vertexIndex = selectedTriangleIndices[selectedIndices[0]];
        position.xy = vertices[vertexIndex];
        
        auto normalPointer = reinterpret_cast<constant half4x3&>(vertexUniforms);
        normal = normalPointer.columns[select(ushort(2), ushort(3), vid >= 3)];
    } else {
        isAmplified = vid >= 4;
        if (isAmplified) { vid -= 4; }
        
        depthRangeIndex = isAmplified;
        
        constexpr ushort2 indices[4] = {
            { 1, 1 },
            { 0, 1 },
            { 1, 0 },
            { 0, 0 }
        };
        
        selectedIndices = indices[vid];
        
        
        
        ushort3 selectedLineIndices = lineIndices[iid];
        depthRangeMask   = selectedLineIndices.z & 1;
        depthRangeIndex += selectedLineIndices.z & (__UINT16_MAX__ - 1);
        
        float2 selectedVertices[2] = {
            vertices[selectedLineIndices[0]],
            vertices[selectedLineIndices[1]]
        };
        
        position.xy = selectedVertices[selectedIndices[0]];
        
        half2 delta = half2(selectedVertices[1]) - half2(selectedVertices[0]);
        normal.xy = half2(delta.y, -delta.x) * rsqrt(length_squared(delta));
        
        normal = vertexUniforms.normalTransform * half3(normal.xy, 0);
    }
    
    ushort depthIndex = (depthRangeIndex << 1) + selectedIndices[1];
    position.z = depths[depthIndex];
    
    if (isAmplified && depthRangeMask)
    {
        VertexInOut out;
        out.position.w = -1;
        
        return out;
    }
    
    
    
    float4 clipPosition;
    float3 eyeDirection;
    
    if (usingAmplification)
    {
        clipPosition = vertexUniforms.projectionTransforms[0] * float4(position, 1);
        eyeDirection = vertexUniforms.eyeDirectionTransforms[0] * float4(position, 1);
        
        if (amp_id == 1)
        {
            clipPosition.x += positionDelta;
            eyeDirection   += eyeDirectionDelta;
        }
    }
    else
    {
        clipPosition = vertexUniforms.projectionTransforms[amp_id] * float4(position, 1);
        eyeDirection = vertexUniforms.eyeDirectionTransforms[amp_id] * float4(position, 1);
    }
    
    return {
        clipPosition, half3(eyeDirection), normal
    };
}



vertex VertexInOut pendulumRectangleTransform(PENDULUM_RECTANGLE_TRANSFORM_PARAMS(VertexUniforms))
{
    return pendulumRectangleTransformCommon<VertexInOut>(isPerimeter, vertexUniforms, depths,
                                                         vertices, triangleIndices, lineIndices,
                                                         iid, vid, 0,
                                                         false, float3(NAN), NAN);
}

vertex MRVertexInOut pendulumMRRectangleTransform(PENDULUM_RECTANGLE_TRANSFORM_PARAMS(MRVertexUniforms),
                                                  constant float3 &eyeDirectionDelta [[ buffer(28) ]],
                                                  constant float  &positionDelta     [[ buffer(29) ]],
                                                  
                                                  ushort amp_id [[ amplification_id ]])
{
    auto out = pendulumRectangleTransformCommon<MRVertexInOut>(isPerimeter, vertexUniforms, depths,
                                                               vertices, triangleIndices, lineIndices,
                                                               iid, vid, amp_id,
                                                               true, eyeDirectionDelta, positionDelta);
    out.layer = amp_id;
    
    return out;
}

vertex VertexInOut pendulumMRRectangleTransform2(PENDULUM_RECTANGLE_TRANSFORM_PARAMS(MRVertexUniforms),
                                                 constant ushort &amp_id [[ buffer(30) ]])
{
    return pendulumRectangleTransformCommon<VertexInOut>(isPerimeter, vertexUniforms, depths,
                                                         vertices, triangleIndices, lineIndices,
                                                         iid, vid, amp_id,
                                                         false, float3(NAN), NAN);
}



typedef struct {
    uint   edgeVertexIndex;
    ushort baseVertexIndex;
} JointVertex;

typedef struct {
    half2  depthRanges[2];
    float2 position;
} JointBaseVertex;

template <typename VertexInOut, typename VertexUniforms>
VertexInOut pendulumJointTransformCommon(PENDULUM_JOINT_TRANSFORM_PARAMS(VertexUniforms), ushort amp_id,
                                         bool usingAmplification, float3 eyeDirectionDelta, float positionDelta)
{
    auto jointVertex = jointVertices[iid];
    ushort depthRangeMask = jointVertex.baseVertexIndex & 1;
    ushort depthRangeIndex = vid >= 10;
    
    if (vid >= 10)
    {
        if (depthRangeMask != 0)
        {
            VertexInOut out;
            out.position.w = -1;
            
            return out;
        }
        
        vid -= 10;
    }
    
    constexpr ushort2 indices[10] = {
        { 2, 1 },
        { 0, 1 },
        { 1, 1 },
        
        { 2, 0 },
        { 1, 0 },
        { 0, 0 },
        
        { 1, 1 },
        { 0, 1 },
        { 1, 0 },
        { 0, 0 }
    };
    
    ushort2 selectedIndices = indices[vid];
    
    
    
    uint vertexIndex = jointVertex.edgeVertexIndex + selectedIndices[0];
    half3 normal;
    
    if (vid < 6)
    {
        auto normalPointer = reinterpret_cast<constant half4x3&>(vertexUniforms);
        normal = normalPointer.columns[select(ushort(2), ushort(3), vid >= 3)];
    }
    else
    {
        normal = edgeNormals[vertexIndex];
    }
    
    ushort baseVertexIndex = jointVertex.baseVertexIndex >> 1;
    float3 position;
    
    if (selectedIndices[0] == 2)
    {
        position.xy = reinterpret_cast<const device float4*>(baseVertices)[baseVertexIndex].zw;
    }
    else
    {
        position.xy = edgeVertices[vertexIndex];
    }
    
    ushort depthIndex = (baseVertexIndex << 3) + (depthRangeIndex << 1) + selectedIndices[1];
    position.z = reinterpret_cast<const device half*>(baseVertices)[depthIndex];
    
    
    
    float4 clipPosition;
    float3 eyeDirection;
    
    if (usingAmplification)
    {
        clipPosition = vertexUniforms.projectionTransforms[0] * float4(position, 1);
        eyeDirection = vertexUniforms.eyeDirectionTransforms[0] * float4(position, 1);
        
        if (amp_id == 1)
        {
            clipPosition.x += positionDelta;
            eyeDirection   += eyeDirectionDelta;
        }
    }
    else
    {
        clipPosition = vertexUniforms.projectionTransforms[amp_id] * float4(position, 1);
        eyeDirection = vertexUniforms.eyeDirectionTransforms[amp_id] * float4(position, 1);
    }
    
    return {
        clipPosition, half3(eyeDirection), normal
    };
}



vertex VertexInOut pendulumJointTransform(PENDULUM_JOINT_TRANSFORM_PARAMS(VertexUniforms))
{
    return pendulumJointTransformCommon<VertexInOut>(vertexUniforms, baseVertices,
                                                     jointVertices, edgeVertices, edgeNormals,
                                                     iid, vid, 0,
                                                     false, float3(NAN), NAN);
}

vertex MRVertexInOut pendulumMRJointTransform(PENDULUM_JOINT_TRANSFORM_PARAMS(MRVertexUniforms),
                                              constant float3 &eyeDirectionDelta [[ buffer(28) ]],
                                              constant float  &positionDelta     [[ buffer(29) ]],
                                              
                                              ushort amp_id [[ amplification_id ]])
{
    auto out = pendulumJointTransformCommon<MRVertexInOut>(vertexUniforms, baseVertices,
                                                           jointVertices, edgeVertices, edgeNormals,
                                                           iid, vid, amp_id,
                                                           true, eyeDirectionDelta, positionDelta);
    out.layer = amp_id;
    
    return out;
}

vertex VertexInOut pendulumMRJointTransform2(PENDULUM_JOINT_TRANSFORM_PARAMS(MRVertexUniforms),
                                             constant ushort &amp_id [[ buffer(30) ]])
{
    return pendulumJointTransformCommon<VertexInOut>(vertexUniforms, baseVertices,
                                                     jointVertices, edgeVertices, edgeNormals,
                                                     iid, vid, amp_id,
                                                     false, float3(NAN), NAN);
}



[[early_fragment_tests]]
fragment half3 pendulumFragmentShader(VertexInOut in [[ stage_in ]],
                                      
                                      constant GlobalFragmentUniforms &globalUniforms [[ buffer(0) ]],
                                      constant FragmentUniforms       &uniforms       [[ buffer(1) ]])
{
    half normal_lengthSquared       = length_squared(in.normal_notNormalized);
    half eyeDirection_lengthSquared = length_squared(in.eyeDirection_notNormalized);

    half3 lightContribution = ColorUtilities::getLightContribution(globalUniforms.lightDirection,
                                                                   globalUniforms.directionalLightColor,
                                                                   globalUniforms.ambientLightColor,
                                                                   uniforms.shininess,

                                                                   normal_lengthSquared,
                                                                   in.normal_notNormalized,
                                                                   eyeDirection_lengthSquared,
                                                                   in.eyeDirection_notNormalized);

    return uniforms.modelColor * lightContribution;
}
