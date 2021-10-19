//
//  Shaders.metal
//  AR MultiPendulum
//
//  Created by Philip Turner on 4/18/21.
//

#include <metal_stdlib>
#include "../Other/Utilities/Metal/ColorUtilities.metal"
using namespace metal;

typedef struct {
    float4x4 projectionTransforms[1];
    float4x3 eyeDirectionTransforms[1];
    half3x3  normalTransform;
    
    float    truncatedConeTopScale;
    half2    truncatedConeNormalMultipliers;
} VertexUniforms;

typedef struct {
    float4x4 projectionTransforms[2];
    float4x3 eyeDirectionTransforms[2];
    half3x3  normalTransform;
    
    float    truncatedConeTopScale;
    half2    truncatedConeNormalMultipliers;
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



typedef struct {
    float3 position [[attribute(0)]];
    half3  normal   [[attribute(1)]];
} Vertex;

typedef struct {
    float3 position                [[attribute(0)]];
    half3  normal                  [[attribute(1)]];
    ushort truncatedConeAttributes [[attribute(2)]];
} CylinderVertex;

#define VertexInOut_Common(attribute)       \
float4 position [[position]];               \
half3  eyeDirection_notNormalized;          \
half3  normal_notNormalized;                \
half3  normal2_notNormalized [[attribute]]; \
                                            \
ushort instance_id;                         \

typedef struct {
    VertexInOut_Common(flat);
} VertexInOut;

typedef struct {
    VertexInOut_Common(center_perspective);
} ConeVertexInOut;

typedef struct {
    VertexInOut_Common(flat);
    ushort layer [[render_target_array_index]];
} MRVertexInOut;

typedef struct {
    VertexInOut_Common(center_perspective);
    ushort layer [[render_target_array_index]];
} MRConeVertexInOut;

#define CENTRAL_VERTEX_TRANSFORM_PARAMS                         \
constant VertexUniforms *uniforms [[ buffer(2) ]],              \
                                                                \
ushort iid [[ instance_id ]]                                    \

#define CENTRAL_MR_VERTEX_TRANSFORM_PARAMS                      \
constant MRVertexUniforms *uniforms          [[ buffer(2) ]],   \
                                                                \
constant float3           &eyeDirectionDelta [[ buffer(28) ]],  \
constant float            &positionDelta     [[ buffer(29) ]],  \
                                                                \
ushort iid    [[ instance_id ]],                                \
ushort amp_id [[ amplification_id ]]                            \

#define CENTRAL_MR_VERTEX_TRANSFORM_PARAMS_2                    \
constant MRVertexUniforms *uniforms  [[ buffer(2) ]],           \
constant ushort           &amp_id    [[ buffer(30) ]],          \
                                                                \
ushort iid [[ instance_id ]]                                    \



template <typename VertexInOut, typename Vertex, typename VertexUniforms>
VertexInOut centralVertexTransformCommon(Vertex in, constant VertexUniforms *selectedUniforms,
                                         half3 normal2, ushort iid, ushort amp_id,
                                         bool usingAmplification, float3 eyeDirectionDelta, float positionDelta)
{
    float4 position;
    float3 eyeDirection;
    
    if (usingAmplification)
    {
        position = selectedUniforms->projectionTransforms[0] * float4(in.position, 1);
        eyeDirection = selectedUniforms->eyeDirectionTransforms[0] * float4(in.position, 1);
        
        if (amp_id == 1)
        {
            position.x   += positionDelta;
            eyeDirection += eyeDirectionDelta;
        }
    }
    else
    {
        position = selectedUniforms->projectionTransforms[amp_id] * float4(in.position, 1);
        eyeDirection = selectedUniforms->eyeDirectionTransforms[amp_id] * float4(in.position, 1);
    }
    
    return {
        position, half3(eyeDirection),
        in.normal, normal2, iid
    };
}

vertex VertexInOut centralVertexTransform(Vertex in [[ stage_in ]], CENTRAL_VERTEX_TRANSFORM_PARAMS)
{
    auto selectedUniforms = uniforms + iid;
    in.normal = normalize(selectedUniforms->normalTransform * in.normal);
    
    return centralVertexTransformCommon<VertexInOut>(in, selectedUniforms, half3{ }, iid, 0,
                                                     false, float3(NAN), NAN);
}

vertex MRVertexInOut centralMRVertexTransform(Vertex in [[ stage_in ]], CENTRAL_MR_VERTEX_TRANSFORM_PARAMS)
{
    auto selectedUniforms = uniforms + iid;
    in.normal = normalize(selectedUniforms->normalTransform * in.normal);

    auto out = centralVertexTransformCommon<MRVertexInOut>(in, selectedUniforms, half3{ }, iid, amp_id,
                                                           true, eyeDirectionDelta, positionDelta);
    out.layer = amp_id;

    return out;
}

vertex VertexInOut centralMRVertexTransform2(Vertex in [[ stage_in ]], CENTRAL_MR_VERTEX_TRANSFORM_PARAMS_2)
{
    auto selectedUniforms = uniforms + iid;
    in.normal = normalize(selectedUniforms->normalTransform * in.normal);
    
    return centralVertexTransformCommon<VertexInOut>(in, selectedUniforms, half3{ }, iid, amp_id,
                                                     false, float3(NAN), NAN);
}



template <typename VertexInOut, typename VertexUniforms>
VertexInOut centralConeVertexTransformCommon(thread Vertex &in, constant VertexUniforms *uniforms,
                                             ushort iid, ushort amp_id,
                                             bool usingAmplification, float3 eyeDirectionDelta, float positionDelta)
{
    constant VertexUniforms *selectedUniforms = uniforms + iid;
    
    half3 normal2 = selectedUniforms->normalTransform * in.normal;
    normal2 *= sqrt(HALF_MAX) * rsqrt(length_squared(normal2));
    
    in.normal = (in.position.y == 0.5) ? half3(0) : normal2;
    
    return centralVertexTransformCommon<VertexInOut>(in, selectedUniforms, normal2, iid, amp_id,
                                                     usingAmplification, eyeDirectionDelta, positionDelta);
}

vertex ConeVertexInOut centralConeVertexTransform(Vertex in [[ stage_in ]], CENTRAL_VERTEX_TRANSFORM_PARAMS)
{
    return centralConeVertexTransformCommon<ConeVertexInOut>(in, uniforms, iid, 0,
                                                             false, float3(NAN), NAN);
}

vertex MRConeVertexInOut centralMRConeVertexTransform(Vertex in [[ stage_in ]], CENTRAL_MR_VERTEX_TRANSFORM_PARAMS)
{
    auto out = centralConeVertexTransformCommon<MRConeVertexInOut>(in, uniforms, iid, amp_id,
                                                                   true, eyeDirectionDelta, positionDelta);
    out.layer = amp_id;
    
    return out;
}

vertex ConeVertexInOut centralMRConeVertexTransform2(Vertex in [[ stage_in ]], CENTRAL_MR_VERTEX_TRANSFORM_PARAMS_2)
{
    return centralConeVertexTransformCommon<ConeVertexInOut>(in, uniforms, iid, amp_id,
                                                             false, float3(NAN), NAN);
}



template <typename VertexInOut, typename VertexUniforms>
VertexInOut centralCylinderVertexTransformCommon(thread CylinderVertex &in, constant VertexUniforms *uniforms,
                                                 ushort iid, ushort amp_id,
                                                 bool usingAmplification, float3 eyeDirectionDelta, float positionDelta)
{
    constant VertexUniforms *selectedUniforms = uniforms + iid;
    
    float topScale = selectedUniforms->truncatedConeTopScale;
    if (!isnan(topScale))
    {
        if ((in.truncatedConeAttributes & 1) != 0)
        {
            in.position.xz *= topScale;
        }

        if ((in.truncatedConeAttributes & 2) != 0)
        {
            half2 normalMultipliers = uniforms->truncatedConeNormalMultipliers;

            in.normal.xz *= normalMultipliers.x;
            in.normal.y   = normalMultipliers.y;
        }
    }
    
    in.normal = normalize(selectedUniforms->normalTransform * in.normal);
    
    return centralVertexTransformCommon<VertexInOut>(in, selectedUniforms, half3{ }, iid, amp_id,
                                                     usingAmplification, eyeDirectionDelta, positionDelta);
}

vertex VertexInOut centralCylinderVertexTransform(CylinderVertex in [[ stage_in ]], CENTRAL_VERTEX_TRANSFORM_PARAMS)
{
    return centralCylinderVertexTransformCommon<VertexInOut>(in, uniforms, iid, 0,
                                                             false, float3(NAN), NAN);
}

vertex MRVertexInOut centralMRCylinderVertexTransform(CylinderVertex in [[ stage_in ]], CENTRAL_MR_VERTEX_TRANSFORM_PARAMS)
{
    auto out = centralCylinderVertexTransformCommon<MRVertexInOut>(in, uniforms, iid, amp_id,
                                                                   true, eyeDirectionDelta, positionDelta);
    out.layer = amp_id;

    return out;
}

vertex VertexInOut centralMRCylinderVertexTransform2(CylinderVertex in [[ stage_in ]], CENTRAL_MR_VERTEX_TRANSFORM_PARAMS_2)
{
    return centralCylinderVertexTransformCommon<VertexInOut>(in, uniforms, iid, amp_id,
                                                             false, float3(NAN), NAN);
}



[[early_fragment_tests]]
fragment half3 centralFragmentShader(VertexInOut in [[ stage_in ]],
                                     
                                     constant GlobalFragmentUniforms &globalUniforms [[ buffer(0) ]],
                                     constant FragmentUniforms       *uniforms       [[ buffer(1) ]],
                                     
                                     bool frontFacing [[ front_facing ]])
{
    auto selectedUniforms = uniforms[in.instance_id];
    half3 lightContribution;

    if (frontFacing)
    {
        float normal_lengthSquared       = length_squared(float3(in.normal_notNormalized));
        half  eyeDirection_lengthSquared = length_squared(in.eyeDirection_notNormalized);

        if (normal_lengthSquared <= HALF_MIN)
        {
            in.normal_notNormalized = in.normal2_notNormalized;
            normal_lengthSquared = length_squared(in.normal2_notNormalized);
        }

        lightContribution = ColorUtilities::getLightContribution(globalUniforms.lightDirection,
                                                                 globalUniforms.directionalLightColor,
                                                                 globalUniforms.ambientLightColor,
                                                                 selectedUniforms.shininess,

                                                                 normal_lengthSquared,
                                                                 in.normal_notNormalized,
                                                                 eyeDirection_lengthSquared,
                                                                 in.eyeDirection_notNormalized);
    }
    else
    {
        lightContribution = globalUniforms.ambientInsideLightColor;
    }

    return selectedUniforms.modelColor * lightContribution;
}
