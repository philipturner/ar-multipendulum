//
//  Utilities.metal
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/13/21.
//

#include <metal_stdlib>
using namespace metal;

namespace CircleIntersectionUtilities {
    // Runs on 2 parallel threads
    void getIntersectionAngleRange(threadgroup void *tg_8bytes_angleRange,
                                   float2 origin1, float2 origin2,
                                   float radius,
                                   ushort quadgroup_id);
    
    // Runs on 8 parallel threads
    void combineAngleRanges(threadgroup void *tg_64bytes,
                            thread float2 *angleRanges,
                            thread float2 *arcSharedPoints,
                            thread ushort &numValidIntersections,
                            thread float2 &endPoint, thread half2 &endNormal,
                            bool onlyFindingEndPoint,
                            
                            float2 origin, float radius,
                            ushort id_in_quadgroup,
                            ushort quadgroup_id);
    
    // Alternative functions that don't use threadgroup memory (compatible with older devices)
    namespace Serial {
        void getIntersectionAngleRange(thread void *t_8bytes_angleRange,
                                       float2 origin1, float2 origin2,
                                       float radius);
        
        void combineAngleRanges(thread float2 *angleRanges,
                                thread float2 *arcSharedPoints,
                                thread ushort &numValidIntersections,
                                thread float2 *endPoints, thread half2 *endNormals,
                                bool onlyFindingEndPoint,
                                
                                float2 origin, float radius);
    }
}
