//
//  PendulumRectangleUtilities.h
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/9/21.
//

#ifndef PendulumRectangleUtilities_h
#define PendulumRectangleUtilities_h

#include <metal_stdlib>
using namespace metal;

enum TriangleIndexType: ushort;

#define INTERSECTION_PARAMS                     \
thread TriangleIndexType &triangleIndexType,    \
float4x2 corners1,                              \
float4x2 corners2,                              \
uchar corners1_insideMask,                      \
                                                \
thread float2 *intersectionProgresses,          \
thread uchar2 *intersectionIDs,                 \
uchar4 intersectionsPerSide,                    \
                                                \
thread uchar3 &geometryCounts,                  \
thread ushort &maxPerimeterIndex,               \
thread float2 *vertices                         \

#define CALL_INTERSECTION_PARAMS                \
triangleIndexType,                              \
corners1, corners2,                             \
corners1_insideMask,                            \
                                                \
intersectionProgresses,                         \
intersectionIDs,                                \
intersectionsPerSide,                           \
                                                \
geometryCounts,                                 \
maxPerimeterIndex,                              \
vertices                                        \



namespace RectangleIntersectionUtilities {
    float2x2 makeSide(float4x2 corners, uchar index);
    
    float getIntersectionProgress(float2x2 line1, float2x2 line2, threadgroup bool *shouldReturnEarly);
    
    
    
    TriangleIndexType getTriangleIndexType(uint numOnes, uint numTwos);
    
    constant uchar3* getTriangleIndices(TriangleIndexType triangleIndexType);
    
    // Runs on 8 parallel threads
    void intersectionFunction(threadgroup void *tg_64bytes,
                              INTERSECTION_PARAMS,
                              
                              ushort id_in_quadgroup,
                              ushort quadgroup_id,
                              ushort thread_id);
    
    // Alternative functions that don't use threadgroup memory (compatible with older devices)
    namespace Serial {
        float getIntersectionProgress(float2x2 line1, float2x2 line2, thread bool &shouldReturnEarly);
        
        void intersectionFunction(INTERSECTION_PARAMS);
    }
}

enum TriangleIndexType: ushort {
    allZeroes = 0,
    notInitialized = allZeroes,
    
    zeroTwos_TwoOnes_0 = 1,
    zeroTwos_TwoOnes_1 = 2,
    zeroTwos_TwoOnes_2 = 3,
    zeroTwos_TwoOnes_3 = 4,
    zeroTwos_TwoOnes_4 = 5,
    zeroTwos_TwoOnes_5 = 6,
    
    zeroTwos_FourOnes = 7,
    
    oneTwo_ZeroOnes_0 = 8,
    oneTwo_ZeroOnes_1 = 9,
    oneTwo_ZeroOnes_2 = 10,
    oneTwo_ZeroOnes_3 = 11,
    
    oneTwo_TwoOnes_0 = zeroTwos_FourOnes,
    oneTwo_TwoOnes_1 = 12,
    oneTwo_TwoOnes_2 = 13,
    oneTwo_TwoOnes_3 = 14,
    oneTwo_TwoOnes_4 = 15,
    
    twoTwos_ZeroOnes_0_0 = 16,
    twoTwos_ZeroOnes_0_1 = 17,
    twoTwos_ZeroOnes_0_2 = 18,
    twoTwos_ZeroOnes_0_3 = 19,
    twoTwos_ZeroOnes_1_0 = 20,
    twoTwos_ZeroOnes_1_1 = 21,
    twoTwos_ZeroOnes_1_2 = 22,
    twoTwos_ZeroOnes_1_3 = 23,
    twoTwos_TwoOnes = 24,
    
    threeTwos_ZeroOnes_0 = 25,
    threeTwos_ZeroOnes_1 = 26,
    threeTwos_ZeroOnes_2 = 27,
    
    fourTwos_ZeroOnes = 28
};

#endif /* PendulumRectangleUtilities_h */
