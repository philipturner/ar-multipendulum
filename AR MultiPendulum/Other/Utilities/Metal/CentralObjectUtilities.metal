//
//  CentralObjectUtilities.metal
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/11/21.
//

#include <metal_stdlib>
using namespace metal;

typedef ushort LOD;

namespace CentralObjectUtilities {
    // Runs on 8 parallel threads
    bool shouldCull(threadgroup void *tg_8bytes,
                    float4 projectedVertex,
                    
                    ushort id_in_quadgroup,
                    ushort quadgroup_id,
                    ushort thread_id);
    
    // Runs on 8 parallel threads
    ushort getLOD(threadgroup void *tg_64bytes,
                  float4x4 modelToWorldTransform,
                  float4x4 worldToModelTransform,
                  constant float4x4 *worldToCameraTransforms,
                  constant float3   *cameraPositions,
                  bool isMR,
                  
                  constant ushort2 *axisMaxScaleIndices,
                  float3 objectScaleHalf, float3 objectPosition,
                  
                  ushort id_in_quadgroup,
                  ushort quadgroup_id,
                  ushort thread_id);
    
    // Alternative functions that don't use threadgroup memory (compatible with older devices)
    namespace Serial {
        bool shouldCull(thread float4 *projectedVertices);
        
        ushort getLOD(float4x4 modelToWorldTransform,
                      float4x4 worldToModelTransform,
                      constant float4x4 *worldToCameraTransforms,
                      constant float3   *cameraPositions,
                      bool isMR,
                      
                      constant ushort2 *axisMaxScaleIndices,
                      float3 objectScaleHalf, float3 objectPosition);
    };
}
