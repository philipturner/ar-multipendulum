//
//  PendulumRectangleUtilities.metal
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/9/21.
//

#include <metal_stdlib>
#include "PendulumRectangleUtilities.h"
using namespace metal;

namespace InternalRectangleIntersectionUtilities {
    uchar increment(uchar index) { return (index + 1) & 3; }
    uchar decrement(uchar index) { return (index - 1) & 3; }
    uchar flip     (uchar index) { return (index + 2) & 3; }
    
    template <typename T> T increment(T indices) { return (indices + 1) & 3; }
    template <typename T> T decrement(T indices) { return (indices - 1) & 3; }
    template <typename T> T flip     (T indices) { return (indices + 2) & 3; }
}

namespace Utilities = RectangleIntersectionUtilities;
using namespace InternalRectangleIntersectionUtilities;

float2x2 Utilities::makeSide(float4x2 corners, uchar index)
{
    return { corners.columns[index], corners.columns[increment(index)] };
}

float Utilities::getIntersectionProgress(float2x2 line1, float2x2 line2, threadgroup bool *shouldReturnEarly)
{
    float2 delta1 = line1[1] - line1[0];
    float2 delta2 = line2[1] - line2[0];
    
    float denominator = fma(delta1.x, delta2.y, -delta1.y * delta2.x);
    if (abs(denominator) <= FLT_MIN) { return NAN; }
    
    float determinant1 = fma(line1[1].x, line1[0].y, -line1[1].y * line1[0].x);
    float determinant2 = fma(line2[1].x, line2[0].y, -line2[1].y * line2[0].x);
    
    float numeratorX = fma(determinant1, delta2.x, -delta1.x * determinant2);
    float numeratorY = fma(determinant1, delta2.y, -delta1.y * determinant2);
    
    float2 intersection;
    intersection.x = fast::divide(numeratorX, denominator);
    if (isinf(intersection.x)) { return NAN; }
    
    intersection.y = fast::divide(numeratorY, denominator);
    if (isinf(intersection.y)) { return NAN; }
    
    
    
    float progress0 = fast::divide(dot(intersection - line1[0], delta1), length_squared(delta1));
    if (progress0 < 1e-4 || progress0 > 1 - 1e-4)
    {
        if (abs(progress0)     < 1e-4 ||
            abs(progress0 - 1) < 1e-4)
        {
            *shouldReturnEarly = true;
        }
        
        return NAN;
    }
    
    float progress1 = fast::divide(dot(intersection - line2[0], delta2), length_squared(delta2));
    if (progress1 < 1e-4 || progress1 > 1 - 1e-4)
    {
        if (abs(progress1)     < 1e-4 ||
            abs(progress1 - 1) < 1e-4)
        {
            *shouldReturnEarly = true;
        }
        
        return NAN;
    }
    
    return progress0;
}

float Utilities::Serial::getIntersectionProgress(float2x2 line1, float2x2 line2, thread bool &shouldReturnEarly)
{
    float2 delta1 = line1[1] - line1[0];
    float2 delta2 = line2[1] - line2[0];
    
    float denominator = fma(delta1.x, delta2.y, -delta1.y * delta2.x);
    if (abs(denominator) <= FLT_MIN) { return NAN; }
    
    float determinant1 = fma(line1[1].x, line1[0].y, -line1[1].y * line1[0].x);
    float determinant2 = fma(line2[1].x, line2[0].y, -line2[1].y * line2[0].x);
    
    float numeratorX = fma(determinant1, delta2.x, -delta1.x * determinant2);
    float numeratorY = fma(determinant1, delta2.y, -delta1.y * determinant2);
    
    float2 intersection;
    intersection.x = fast::divide(numeratorX, denominator);
    if (isinf(intersection.x)) { return NAN; }
    
    intersection.y = fast::divide(numeratorY, denominator);
    if (isinf(intersection.y)) { return NAN; }
    
    
    
    float progress0 = fast::divide(dot(intersection - line1[0], delta1), length_squared(delta1));
    if (progress0 < 1e-5 || progress0 > 1 - 1e-5)
    {
        if (abs(progress0)     < 1e-5 ||
            abs(progress0 - 1) < 1e-5)
        {
            shouldReturnEarly = true;
        }
        
        return NAN;
    }
    
    float progress1 = fast::divide(dot(intersection - line2[0], delta2), length_squared(delta2));
    if (progress1 < 1e-5 || progress1 > 1 - 1e-5)
    {
        if (abs(progress1)     < 1e-5 ||
            abs(progress1 - 1) < 1e-5)
        {
            shouldReturnEarly = true;
        }
        
        return NAN;
    }
    
    return progress0;
}



TriangleIndexType Utilities::getTriangleIndexType(uint numOnes, uint numTwos)
{
    switch (numTwos)
    {
        case 0:
        {
            switch (numOnes)
            {
                case 0:  return allZeroes;
                case 2:  return zeroTwos_TwoOnes_0;
                default: return zeroTwos_FourOnes;
            }
        }
        case 1:
        {
            return numOnes == 0 ? oneTwo_ZeroOnes_0
                                : oneTwo_TwoOnes_4;
        }
        case 2:
        {
            return numOnes == 0 ? twoTwos_ZeroOnes_0_0
                                : twoTwos_TwoOnes;
        }
        case 3:
        {
            return threeTwos_ZeroOnes_0;
        }
        default:
        {
            return fourTwos_ZeroOnes;
        }
    }
}

constexpr constant uchar NUM_TRIANGLE_INDEX_TYPES = 29;
constexpr constant uchar MAX_NUM_INDICES = 7;
constexpr constant uchar ROUNDED_MAX_NUM_INDICES = MAX_NUM_INDICES + 1;

constant uchar3 allIndices[NUM_TRIANGLE_INDEX_TYPES][ROUNDED_MAX_NUM_INDICES] = {
    // All Zeroes / Not Initialized
    { { 0, 1, 2 }, { 0, 2, 3 } },
    
    // Zero Twos, Two Ones
    { { 0, 1, 2 }, { 1, 3, 2 }                                        },
    { { 0, 4, 2 }, { 0, 1, 4 }, { 1, 3, 4 }                           },
    { { 1, 2, 3 }, { 0, 1, 4 }, { 1, 3, 4 }                           },
    { { 0, 5, 4 }, { 0, 1, 5 }, { 1, 2, 5 }, { 2, 3, 5 }              },
    { { 0, 5, 4 }, { 0, 1, 5 }, { 1, 6, 5 }, { 1, 2, 6 }, { 2, 3, 6 } },
    { { 0, 1, 2 }                                                     },
    
    // (Zero Twos, Four Ones) / (One Two, Two Ones (0))
    { { 0, 1, 2 }, { 3, 4, 5 } },
    
    // One Two, Zero Ones
    { { 2, 3, 6 }, { 3, 4, 6 }, { 1, 7, 5 }, { 1, 5, 0 }, { 1, 2, 7 }, { 2, 6, 7 }              },
    { { 2, 3, 6 }, { 3, 4, 6 }, { 1, 7, 5 }, { 1, 5, 0 }, { 1, 2, 6 }, { 1, 6, 7 }              },
    { { 0, 1, 5 }, { 1, 6, 5 }, { 2, 3, 6 }, { 3, 4, 6 }, { 1, 2, 6 }                           },
    { { 0, 6, 5 }, { 1, 7, 6 }, { 2, 3, 8 }, { 3, 4, 8 }, { 1, 2, 7 }, { 2, 8, 7 }, { 0, 1, 6 } },
    
    // One Two, Two Ones
    { { 0, 6, 4 }, { 1, 2, 5 }, { 2, 3, 5 }              },
    { { 0, 6, 4 }, { 1, 2, 7 }, { 2, 3, 7 }, { 1, 7, 5 } },
    { { 0, 6, 4 }, { 0, 1, 6 }, { 2, 3, 5 }              },
    { { 0, 7, 4 }, { 0, 1, 7 }, { 2, 3, 5 }, { 1, 6, 7 } },
    
    // Two Twos, Zero Ones (0)
    { { 2, 3, 7 }, { 3, 4, 7 },              { 0, 1, 6 }, { 0, 6, 5 }              },
    { { 2, 3, 7 }, { 3, 4, 7 },              { 0, 1, 9 }, { 0, 9, 5 }, { 1, 6, 9 } },
    { { 2, 3, 8 }, { 3, 4, 8 }, { 2, 8, 7 }, { 0, 1, 6 }, { 0, 6, 5 }              },
    { { 2, 3, 8 }, { 3, 4, 8 }, { 2, 8, 7 }, { 0, 1, 9 }, { 0, 9, 5 }, { 1, 6, 9 } },
    
    // Two Twos, Zero Ones (1)
    { { 0, 6, 5 }, { 1, 2, 7 }, { 2, 4, 7 }, { 2, 3, 4 }              },
    { { 0, 6, 5 }, { 1, 2, 9 }, { 2, 4, 9 }, { 2, 3, 4 }, { 3, 4, 8 } },
    { { 0, 6, 5 }, { 1, 2, 7 }, { 2, 8, 7 }, { 2, 3, 8 }              },
    { { 0, 6, 5 }, { 1, 2, 9 }, { 2, 8, 9 }, { 2, 3, 8 }, { 1, 9, 7 } },
    
    // Two Twos, Two Ones
    { { 0, 1, 2 }, { 3, 4, 5 }, { 6, 7, 8 } },
    
    // Three Twos, Zero Ones
    { { 2, 6, 5 }, { 3, 8, 7 }, { 1, 4, 10 }, { 0, 1, 10 }, { 0, 10, 9 } },
    { { 1, 6, 5 }, { 2, 8, 7 }, { 3, 4,  9 }, { 0, 1,  5 }               },
    { { 0, 6, 5 }, { 1, 8, 7 }, { 3, 4,  9 }, { 2, 3,  9 }               },
    
    // Four Twos, Zero Ones
    { { 0, 1, 2 }, { 3, 4, 5 }, { 6, 7, 8 }, { 9, 10, 11 } }
};

constant uchar3* Utilities::getTriangleIndices(TriangleIndexType triangleIndexType)
{
    return allIndices[ushort(triangleIndexType)];
}



inline float2 getPoint(float2x2 line, float progress)
{
    return mix(line[0], line[1], progress);
}

template <typename T>
inline bool unpackMask(T mask, uchar index)
{
    return (mask & (1 << index)) != 0;
}

template <typename T>
inline void swap(thread T &lhs, thread T &rhs)
{
    T temp = lhs;
    lhs = rhs;
    rhs = temp;
}

inline void searchForElementCount(uchar numElements, uchar4 intersectionsPerSide,
                           thread uchar &sideIndex1, thread uchar &sideIndex2)
{
    sideIndex1 = 255;
    
    for (uchar i = 0; ; ++i)
    {
        if (intersectionsPerSide[i] == numElements)
        {
            if (sideIndex1 == 255) { sideIndex1 = i; }
            else                   { sideIndex2 = i; return; }
        }
    }
}



inline void zeroTwos_TwoOnes_0_common(INTERSECTION_PARAMS, thread uchar &sideIndex1, thread uchar &sideIndex2)
{
    searchForElementCount(1, intersectionsPerSide, sideIndex1, sideIndex2);
    
    if (increment(sideIndex2) == sideIndex1 ||
            (flip(sideIndex2) == sideIndex1 && unpackMask(corners1_insideMask, sideIndex2)))
    {
        swap(sideIndex1, sideIndex2);
    }
}

inline void zeroTwos_FourOnes_common(INTERSECTION_PARAMS, thread uchar4 &sideIndices)
{
    uchar intersectionID1 = intersectionIDs[0][0];
    uchar intersectionID2 = intersectionIDs[1][0];
    
    if (intersectionID1 == intersectionID2)
    {
        sideIndices = { 0, 1, 2, 3 };
    }
    else
    {
        sideIndices = { 1, 2, 3, 0 };
    }
}

inline void oneTwo_ZeroOnes_0_common_1(INTERSECTION_PARAMS, thread uchar &sideIndexForCorners, thread uchar2 &indices)
{
    for (uchar i = 0; ; ++i)
    {
        if (intersectionsPerSide[i] == 2)
        {
            sideIndexForCorners = i;
            break;
        }
    }
    
    indices = intersectionIDs[sideIndexForCorners];
}

inline void oneTwo_ZeroOnes_0_common_2(INTERSECTION_PARAMS, uchar2 indices)
{
    if (decrement(indices[0]) == indices[1])
    {
        vertices[6] = corners2.columns[indices[0]];
        
        triangleIndexType = oneTwo_ZeroOnes_2;
        geometryCounts = { 7, 5 };
    }
    else
    {
        vertices[6] = corners2.columns[increment(indices[1])];
        vertices[7] = corners2.columns[     flip(indices[1])];
        vertices[8] = corners2.columns[decrement(indices[1])];
        
        triangleIndexType = oneTwo_ZeroOnes_3;
        geometryCounts = { 9, 7 };
    }
}

inline void oneTwo_TwoOnes_4_common_1(INTERSECTION_PARAMS, thread uchar &mainSideIndex, thread uchar2 &altSideIndices)
{
    for (uchar i = 0; i < 4; ++i)
    {
        uchar numIntersections = intersectionsPerSide[i];
        
        if      (numIntersections == 2) { mainSideIndex = i; }
        else if (numIntersections == 1)
        {
            if (altSideIndices[0] == 255) { altSideIndices[0] = i; }
            else                          { altSideIndices[1] = i; }
        }
    }
    
    if (any(((altSideIndices + uchar2(-1, 1)) & 3) == mainSideIndex))
    {
        uchar temp = altSideIndices[0];
        altSideIndices[0] = altSideIndices[1];
        altSideIndices[1] = temp;
    }
}

inline void oneTwo_TwoOnes_4_common_2(INTERSECTION_PARAMS, uchar mainSideIndex, uchar2 altSideIndices)
{
    uchar2 mainIndices = intersectionIDs[mainSideIndex];
    
    if (flip(altSideIndices[0]) == mainSideIndex)
    {
        vertices[1] = corners1.columns[decrement(mainSideIndex)];
        
        if (intersectionIDs[altSideIndices.x][0] == mainIndices[0])
        {
            triangleIndexType = oneTwo_TwoOnes_1;
            geometryCounts = { 7, 3 };
        }
        else
        {
            vertices[7] = corners2.columns[mainIndices[0]];
            
            triangleIndexType = oneTwo_TwoOnes_2;
            geometryCounts = { 8, 4 };
        }
    }
    else
    {
        vertices[1] = corners1.columns[flip(mainSideIndex)];
        
        if (intersectionIDs[altSideIndices.y][0] == mainIndices[1])
        {
            triangleIndexType = oneTwo_TwoOnes_3;
            geometryCounts = { 7, 3 };
        }
        else
        {
            vertices[7] = corners2.columns[mainIndices[1]];
            geometryCounts = { 8, 4 };
        }
    }
}

inline void twoTwos_ZeroOnes_0_0_combined(INTERSECTION_PARAMS, uchar sideIndex1, uchar sideIndex2)
{
    uchar2 mainIndices1 = intersectionIDs[sideIndex1];
    uchar2 mainIndices2 = intersectionIDs[sideIndex2];
    
    vertices[1] = corners1.columns[     flip(sideIndex1)];
    vertices[2] = corners1.columns[decrement(sideIndex1)];
    vertices[3] = corners1.columns[          sideIndex1 ];
    
    vertices[8] = corners2.columns[mainIndices1[0]];
    
    if (flip(sideIndex1) == sideIndex2)
    {
        vertices[9] = corners2.columns[mainIndices2[0]];
        
        if (mainIndices2[1] == mainIndices1[0])
        {
            if (mainIndices2[0] == mainIndices1[1])
            {
                geometryCounts = { 8, 4 };
            }
            else
            {
                triangleIndexType = twoTwos_ZeroOnes_0_1;
                geometryCounts = { 10, 5 };
            }
        }
        else
        {
            if (mainIndices2[0] == mainIndices1[1])
            {
                triangleIndexType = twoTwos_ZeroOnes_0_2;
                geometryCounts = { 9, 5 };
            }
            else
            {
                triangleIndexType = twoTwos_ZeroOnes_0_3;
                geometryCounts = { 10, 6 };
            }
        }
    }
    else
    {
        vertices[9] = corners2.columns[increment(mainIndices2[1])];
        
        if (flip(mainIndices1[0]) == mainIndices1[1])
        {
            if (flip(mainIndices2[0]) == mainIndices2[1])
            {
                triangleIndexType = twoTwos_ZeroOnes_1_0;
                geometryCounts = { 8, 4 };
            }
            else
            {
                triangleIndexType = twoTwos_ZeroOnes_1_1;
                geometryCounts = { 10, 5 };
            }
        }
        else
        {
            if (flip(mainIndices2[0]) == mainIndices2[1])
            {
                triangleIndexType = twoTwos_ZeroOnes_1_2;
                geometryCounts = { 8, 4 };
            }
            else
            {
                triangleIndexType = twoTwos_ZeroOnes_1_3;
                geometryCounts = { 10, 5 };
            }
        }
    }
    
    maxPerimeterIndex = 7;
}

inline void threeTwos_ZeroOnes_0_common_1(INTERSECTION_PARAMS, thread uchar &sideIndexForCorners, thread uchar3 &sideIndices)
{
    if (any(intersectionsPerSide.xy != 2))
    {
        if (intersectionsPerSide[0] != 2) { sideIndices = { 1, 2, 3 }; }
        else                              { sideIndices = { 0, 2, 3 }; }
    }
    else
    {
        if (intersectionsPerSide[2] != 2) { sideIndices = { 0, 1, 3 }; }
        else                              { sideIndices = { 0, 1, 2 }; }
    }
    
    uchar2 intersectionIDArray[3] = {
        intersectionIDs[sideIndices[0]],
        intersectionIDs[sideIndices[1]],
        intersectionIDs[sideIndices[2]]
    };
    
    bool3 flipMask = uchar3(intersectionIDArray[0][0], intersectionIDArray[1][0], intersectionIDArray[2][0])
             == flip(uchar3(intersectionIDArray[0][1], intersectionIDArray[1][1], intersectionIDArray[2][1]));
    
    if (!any(flipMask))
    {
        if (flip(sideIndices[0]) == sideIndices[1]) { sideIndices = sideIndices.yzx; }
        else                                        { sideIndices = sideIndices.zxy; }
        
        sideIndexForCorners = sideIndices[2];
    }
    else
    {
        uchar sideIndex0Index;
        
        for (uchar i = 0; ; ++i)
        {
            if (flipMask[i])
            {
                sideIndex0Index = i;
                break;
            }
        }
        
        if      (sideIndex0Index == 1) { sideIndices = sideIndices.yzx; }
        else if (sideIndex0Index == 2) { sideIndices = sideIndices.zxy; }
        
        triangleIndexType = flip(sideIndices[0]) == sideIndices[1] ? threeTwos_ZeroOnes_1
                                                                   : threeTwos_ZeroOnes_2;
        
        sideIndexForCorners = sideIndices[0];
    }
}

inline void threeTwo_ZeroOnes_0_common_2(INTERSECTION_PARAMS, uchar3 sideIndices)
{
    if (triangleIndexType == threeTwos_ZeroOnes_0)
    {
        vertices[10] = corners2.columns[intersectionIDs[sideIndices.x][0]];
        
        geometryCounts = { 11, 5 };
    }
    else
    {
        geometryCounts = { 10, 4 };
    }
    
    maxPerimeterIndex = 9;
}



void Utilities::intersectionFunction(threadgroup void *tg_64bytes,
                                     INTERSECTION_PARAMS,
                                     
                                     ushort id_in_quadgroup,
                                     ushort quadgroup_id,
                                     ushort thread_id)
{
    auto projectedPoints = reinterpret_cast<threadgroup float2*>(tg_64bytes);
    uchar sideIndexForCorners;
    
    switch (triangleIndexType)
    {
        case zeroTwos_TwoOnes_0:
        {
            uchar sideIndex1, sideIndex2;
            zeroTwos_TwoOnes_0_common(CALL_INTERSECTION_PARAMS, sideIndex1, sideIndex2);
            
            if (id_in_quadgroup == 0)
            {
                uchar sideIndex = quadgroup_id == 0 ? sideIndex1 : sideIndex2;
                
                auto intersectionProgress = intersectionProgresses[sideIndex][0];
                auto targetSide = makeSide(corners1, sideIndex);
                
                projectedPoints[quadgroup_id] = getPoint(targetSide, intersectionProgress);
            }
            
            uchar intersectionID1 = intersectionIDs[sideIndex1][0];
            uchar intersectionID2 = intersectionIDs[sideIndex2][0];
            
            if (flip(sideIndex1) == sideIndex2)
            {
                vertices[0] = corners1.columns[decrement(sideIndex2)];
                vertices[1] = corners1.columns[sideIndex2];
                
                vertices[2] = projectedPoints[0];
                vertices[3] = projectedPoints[1];
                
                if (intersectionID1 == intersectionID2)
                {
                    geometryCounts = { 4, 2 };
                }
                else
                {
                    vertices[4] = corners2.columns[intersectionID2];
                    
                    triangleIndexType = zeroTwos_TwoOnes_1;
                    geometryCounts = { 5, 3 };
                }
                
                maxPerimeterIndex = 3;
            }
            else
            {
                if (unpackMask(corners1_insideMask, sideIndex2))
                {
                    vertices[0] = corners1.columns[increment(sideIndex2)];
                    vertices[1] = corners1.columns[     flip(sideIndex2)];
                    vertices[2] = corners1.columns[decrement(sideIndex2)];
                    
                    vertices[3] = projectedPoints[0];
                    vertices[4] = projectedPoints[1];
                    
                    if (intersectionID1 == intersectionID2)
                    {
                        triangleIndexType = zeroTwos_TwoOnes_2;
                        geometryCounts = { 5, 3 };
                    }
                    else if (increment(intersectionID2) == intersectionID1)
                    {
                        vertices[5] = corners2.columns[intersectionID1];
                        
                        triangleIndexType = zeroTwos_TwoOnes_3;
                        geometryCounts = { 6, 4 };
                    }
                    else
                    {
                        vertices[5] = corners2.columns[increment(intersectionID2)];
                        vertices[6] = corners2.columns[intersectionID1];
                        
                        triangleIndexType = zeroTwos_TwoOnes_4;
                        geometryCounts = { 7, 5 };
                    }
                    
                    maxPerimeterIndex = 4;
                }
                else
                {
                    vertices[0] = corners1.columns[sideIndex2];
                    vertices[1] = projectedPoints[1];
                    vertices[2] = projectedPoints[0];
                    
                    triangleIndexType = zeroTwos_TwoOnes_5;
                    geometryCounts = { 3, 1 };
                    maxPerimeterIndex = 2;
                }
            }
            
            return;
        }
        case zeroTwos_FourOnes:
        {
            uchar4 sideIndices;
            zeroTwos_FourOnes_common(CALL_INTERSECTION_PARAMS, sideIndices);
            
            if (quadgroup_id == 0)
            {
                uchar sideIndex = sideIndices[id_in_quadgroup];
                
                auto intersectionProgress = intersectionProgresses[sideIndex][0];
                auto targetSide = makeSide(corners1, sideIndex);
                
                projectedPoints[id_in_quadgroup] = getPoint(targetSide, intersectionProgress);
            }
            
            vertices[0] = corners1.columns[sideIndices[1]];
            vertices[1] = projectedPoints[1];
            vertices[2] = projectedPoints[0];
            
            vertices[3] = corners1.columns[sideIndices[3]];
            vertices[4] = projectedPoints[3];
            vertices[5] = projectedPoints[2];
            
            geometryCounts = { 6, 2 };
            maxPerimeterIndex = 5;
            
            return;
        }
        case oneTwo_ZeroOnes_0:
        {
            uchar2 indices;
            oneTwo_ZeroOnes_0_common_1(CALL_INTERSECTION_PARAMS, sideIndexForCorners, indices);
            
            if (id_in_quadgroup == 0)
            {
                auto intersectionProgress = intersectionProgresses[sideIndexForCorners][quadgroup_id];
                auto targetSide = makeSide(corners1, sideIndexForCorners);
                
                projectedPoints[quadgroup_id] = getPoint(targetSide, intersectionProgress);
            }
            
            if (any(flip(indices) == indices))
            {
                vertices[6] = corners2.columns[indices[0]];
                vertices[7] = corners2.columns[increment(indices[1])];
                
                auto distancesSquared = reinterpret_cast<threadgroup float*>(projectedPoints + 2);
                
                if (id_in_quadgroup == 0)
                {
                    distancesSquared[quadgroup_id] = distance_squared(projectedPoints[quadgroup_id],
                                                                         vertices[6 + quadgroup_id]);
                }
                
                if (distancesSquared[0] >= distancesSquared[1])
                {
                    triangleIndexType = oneTwo_ZeroOnes_1;
                }
                
                geometryCounts = { 8, 6 };
            }
            else
            {
                oneTwo_ZeroOnes_0_common_2(CALL_INTERSECTION_PARAMS, indices);
            }
            
            maxPerimeterIndex = 5;
            
            break; // assigning vertices 0 through 5 in code shared with another case
        }
        case oneTwo_TwoOnes_4:
        {
            uchar  mainSideIndex;
            uchar2 altSideIndices = { 255 };
            oneTwo_TwoOnes_4_common_1(CALL_INTERSECTION_PARAMS, mainSideIndex, altSideIndices);
            
            if (quadgroup_id == 0)
            {
                uchar sideIndex       = (id_in_quadgroup < 2) ? mainSideIndex : altSideIndices[id_in_quadgroup - 2];
                uchar withinSideIndex = id_in_quadgroup == 1;
                
                auto intersectionProgress = intersectionProgresses[sideIndex][withinSideIndex];
                auto targetSide = makeSide(corners1, sideIndex);
                
                projectedPoints[id_in_quadgroup] = getPoint(targetSide, intersectionProgress);
            }
            
            vertices[0] = corners1.columns[increment(mainSideIndex)];
            vertices[5] = projectedPoints[2];
            
            maxPerimeterIndex = 6;
            
            if (all(((altSideIndices + uchar2(1, -1)) & 3) == mainSideIndex))
            {
                vertices[1] = projectedPoints[3];
                vertices[2] = projectedPoints[1];
                
                vertices[3] = corners1.columns[mainSideIndex];
                vertices[4] = projectedPoints[0];
                
                triangleIndexType = oneTwo_TwoOnes_0;
                geometryCounts = { 6, 2 };
                
                return;
            }
            
            vertices[2] = corners1.columns[mainSideIndex];
            
            vertices[3] = projectedPoints[0];
            vertices[4] = projectedPoints[1];
            vertices[5] = projectedPoints[2];
            vertices[6] = projectedPoints[3];
            
            oneTwo_TwoOnes_4_common_2(CALL_INTERSECTION_PARAMS, mainSideIndex, altSideIndices);
            
            return;
        }
        case twoTwos_ZeroOnes_0_0:
        case twoTwos_TwoOnes:
        {
            uchar sideIndex1, sideIndex2, sideIndex3, sideIndex4;
            searchForElementCount(2, intersectionsPerSide, sideIndex1, sideIndex2);
            if (decrement(sideIndex1) == sideIndex2) { swap(sideIndex1, sideIndex2); }
            
            bool canMakeProjectedPoint = quadgroup_id == 0;
            
            if (triangleIndexType == twoTwos_TwoOnes)
            {
                searchForElementCount(1, intersectionsPerSide, sideIndex3, sideIndex4);
                if (decrement(sideIndex3) == sideIndex4) { swap(sideIndex3, sideIndex4); }
                
                canMakeProjectedPoint |= id_in_quadgroup < 2;
            }
            
            if (canMakeProjectedPoint)
            {
                uchar sideIndex, withinSideIndex;
                
                if (quadgroup_id == 0)
                {
                    sideIndex = (id_in_quadgroup < 2) ? sideIndex1 : sideIndex2;
                    withinSideIndex = id_in_quadgroup & 1;
                }
                else
                {
                    sideIndex = (id_in_quadgroup == 0) ? sideIndex3 : sideIndex4;
                    withinSideIndex = 0;
                }
                
                auto intersectionProgress = intersectionProgresses[sideIndex][withinSideIndex];
                auto targetSide = makeSide(corners1, sideIndex);
                
                projectedPoints[thread_id] = getPoint(targetSide, intersectionProgress);
            }
            
            vertices[0] = corners1.columns[increment(sideIndex1)];
            
            if (triangleIndexType == twoTwos_TwoOnes)
            {
                vertices[1] = projectedPoints[2];
                vertices[2] = projectedPoints[1];
                
                vertices[3] = corners1.columns[flip(sideIndex1)];
                vertices[4] = projectedPoints[4];
                vertices[5] = projectedPoints[3];
                
                vertices[6] = corners1.columns[sideIndex1];
                vertices[7] = projectedPoints[0];
                vertices[8] = projectedPoints[5];
                
                geometryCounts = { 9, 3 };
                maxPerimeterIndex = 8;
                
                return;
            }
            
            vertices[4] = projectedPoints[0];
            vertices[5] = projectedPoints[1];
            vertices[6] = projectedPoints[2];
            vertices[7] = projectedPoints[3];
            
            twoTwos_ZeroOnes_0_0_combined(CALL_INTERSECTION_PARAMS, sideIndex1, sideIndex2);
            
            return;
        }
        case threeTwos_ZeroOnes_0:
        {
            uchar3 sideIndices;
            threeTwos_ZeroOnes_0_common_1(CALL_INTERSECTION_PARAMS, sideIndexForCorners, sideIndices);
            
            if (thread_id < 6)
            {
                uchar sideIndex = sideIndices[thread_id >> 1];
                uchar withinSideIndex = thread_id & 1;
                
                auto intersectionProgress = intersectionProgresses[sideIndex][withinSideIndex];
                auto targetSide = makeSide(corners1, sideIndex);
                
                projectedPoints[thread_id] = getPoint(targetSide, intersectionProgress);
            }
            
            vertices[6] = projectedPoints[2];
            vertices[7] = projectedPoints[3];
            vertices[8] = projectedPoints[4];
            vertices[9] = projectedPoints[5];
            
            threeTwo_ZeroOnes_0_common_2(CALL_INTERSECTION_PARAMS, sideIndices);
            
            break; // assigning vertices 0 through 5 in code shared with another case
        }
        default:
        {
            uchar sideIndex       = thread_id >> 1;
            uchar withinSideIndex = thread_id & 1;
            
            auto intersectionProgress = intersectionProgresses[sideIndex][withinSideIndex];
            auto targetSide = makeSide(corners1, sideIndex);
            
            projectedPoints[thread_id] = getPoint(targetSide, intersectionProgress);
            
            vertices[0] = corners1[0];
            vertices[1] = projectedPoints[0];
            vertices[2] = projectedPoints[7];
            
            vertices[3] = corners1[1];
            vertices[4] = projectedPoints[2];
            vertices[5] = projectedPoints[1];
            
            vertices[6] = corners1[2];
            vertices[7] = projectedPoints[4];
            vertices[8] = projectedPoints[3];
            
            vertices[9]  = corners1[3];
            vertices[10] = projectedPoints[6];
            vertices[11] = projectedPoints[5];
            
            geometryCounts = { 12, 4 };
            maxPerimeterIndex = 11;
            
            return;
        }
    }
    
    uchar4 cornerIndices = (uchar4(sideIndexForCorners) - uchar4(3, 2, 1, 0)) & 3;
    
    vertices[0] = corners1.columns[cornerIndices[0]];
    vertices[1] = corners1.columns[cornerIndices[1]];
    vertices[2] = corners1.columns[cornerIndices[2]];
    vertices[3] = corners1.columns[cornerIndices[3]];
    
    vertices[4] = projectedPoints[0];
    vertices[5] = projectedPoints[1];
}






void Utilities::Serial::intersectionFunction(INTERSECTION_PARAMS)
{
    float2 projectedPoints[8];
    uchar sideIndexForCorners;
    
    switch (triangleIndexType)
    {
        case zeroTwos_TwoOnes_0:
        {
            uchar sideIndex1, sideIndex2;
            zeroTwos_TwoOnes_0_common(CALL_INTERSECTION_PARAMS, sideIndex1, sideIndex2);
            
            for (ushort quadgroup_id = 0; quadgroup_id < 2; ++quadgroup_id)
            {
                uchar sideIndex = quadgroup_id == 0 ? sideIndex1 : sideIndex2;
                
                auto intersectionProgress = intersectionProgresses[sideIndex][0];
                auto targetSide = makeSide(corners1, sideIndex);
                
                projectedPoints[quadgroup_id] = getPoint(targetSide, intersectionProgress);
            }
            
            uchar intersectionID1 = intersectionIDs[sideIndex1][0];
            uchar intersectionID2 = intersectionIDs[sideIndex2][0];
            
            if (flip(sideIndex1) == sideIndex2)
            {
                vertices[0] = corners1.columns[decrement(sideIndex2)];
                vertices[1] = corners1.columns[sideIndex2];
                
                vertices[2] = projectedPoints[0];
                vertices[3] = projectedPoints[1];
                
                if (intersectionID1 == intersectionID2)
                {
                    geometryCounts = { 4, 2 };
                }
                else
                {
                    vertices[4] = corners2.columns[intersectionID2];
                    
                    triangleIndexType = zeroTwos_TwoOnes_1;
                    geometryCounts = { 5, 3 };
                }
                
                maxPerimeterIndex = 3;
            }
            else
            {
                if (unpackMask(corners1_insideMask, sideIndex2))
                {
                    vertices[0] = corners1.columns[increment(sideIndex2)];
                    vertices[1] = corners1.columns[     flip(sideIndex2)];
                    vertices[2] = corners1.columns[decrement(sideIndex2)];
                    
                    vertices[3] = projectedPoints[0];
                    vertices[4] = projectedPoints[1];
                    
                    if (intersectionID1 == intersectionID2)
                    {
                        triangleIndexType = zeroTwos_TwoOnes_2;
                        geometryCounts = { 5, 3 };
                    }
                    else if (increment(intersectionID2) == intersectionID1)
                    {
                        vertices[5] = corners2.columns[intersectionID1];
                        
                        triangleIndexType = zeroTwos_TwoOnes_3;
                        geometryCounts = { 6, 4 };
                    }
                    else
                    {
                        vertices[5] = corners2.columns[increment(intersectionID2)];
                        vertices[6] = corners2.columns[intersectionID1];
                        
                        triangleIndexType = zeroTwos_TwoOnes_4;
                        geometryCounts = { 7, 5 };
                    }
                    
                    maxPerimeterIndex = 4;
                }
                else
                {
                    vertices[0] = corners1.columns[sideIndex2];
                    vertices[1] = projectedPoints[1];
                    vertices[2] = projectedPoints[0];
                    
                    triangleIndexType = zeroTwos_TwoOnes_5;
                    geometryCounts = { 3, 1 };
                    maxPerimeterIndex = 2;
                }
            }
            
            return;
        }
        case zeroTwos_FourOnes:
        {
            uchar4 sideIndices;
            zeroTwos_FourOnes_common(CALL_INTERSECTION_PARAMS, sideIndices);
            
            for (ushort id_in_quadgroup = 0; id_in_quadgroup < 4; ++id_in_quadgroup)
            {
                uchar sideIndex = sideIndices[id_in_quadgroup];
                
                auto intersectionProgress = intersectionProgresses[sideIndex][0];
                auto targetSide = makeSide(corners1, sideIndex);
                
                projectedPoints[id_in_quadgroup] = getPoint(targetSide, intersectionProgress);
            }
            
            vertices[0] = corners1.columns[sideIndices[1]];
            vertices[1] = projectedPoints[1];
            vertices[2] = projectedPoints[0];
            
            vertices[3] = corners1.columns[sideIndices[3]];
            vertices[4] = projectedPoints[3];
            vertices[5] = projectedPoints[2];
            
            geometryCounts = { 6, 2 };
            maxPerimeterIndex = 5;
            
            return;
        }
        case oneTwo_ZeroOnes_0:
        {
            uchar2 indices;
            oneTwo_ZeroOnes_0_common_1(CALL_INTERSECTION_PARAMS, sideIndexForCorners, indices);
            
            for (ushort quadgroup_id = 0; quadgroup_id < 2; ++quadgroup_id)
            {
                auto intersectionProgress = intersectionProgresses[sideIndexForCorners][quadgroup_id];
                auto targetSide = makeSide(corners1, sideIndexForCorners);
                
                projectedPoints[quadgroup_id] = getPoint(targetSide, intersectionProgress);
            }
            
            if (any(flip(indices) == indices))
            {
                vertices[6] = corners2.columns[indices[0]];
                vertices[7] = corners2.columns[increment(indices[1])];
                
                float2 distancesSquared;
                
                for (ushort quadgroup_id = 0; quadgroup_id < 2; ++quadgroup_id)
                {
                    distancesSquared[quadgroup_id] = distance_squared(projectedPoints[quadgroup_id],
                                                                         vertices[6 + quadgroup_id]);
                }
                
                if (distancesSquared[0] >= distancesSquared[1])
                {
                    triangleIndexType = oneTwo_ZeroOnes_1;
                }
                
                geometryCounts = { 8, 6 };
            }
            else
            {
                oneTwo_ZeroOnes_0_common_2(CALL_INTERSECTION_PARAMS, indices);
            }
            
            maxPerimeterIndex = 5;
            
            break; // assigning vertices 0 through 5 in code shared with another case
        }
        case oneTwo_TwoOnes_4:
        {
            uchar  mainSideIndex;
            uchar2 altSideIndices = { 255 };
            oneTwo_TwoOnes_4_common_1(CALL_INTERSECTION_PARAMS, mainSideIndex, altSideIndices);
            
            for (ushort id_in_quadgroup = 0; id_in_quadgroup < 4; ++id_in_quadgroup)
            {
                uchar sideIndex       = (id_in_quadgroup < 2) ? mainSideIndex : altSideIndices[id_in_quadgroup - 2];
                uchar withinSideIndex = id_in_quadgroup == 1;
                
                auto intersectionProgress = intersectionProgresses[sideIndex][withinSideIndex];
                auto targetSide = makeSide(corners1, sideIndex);
                
                projectedPoints[id_in_quadgroup] = getPoint(targetSide, intersectionProgress);
            }
            
            vertices[0] = corners1.columns[increment(mainSideIndex)];
            vertices[5] = projectedPoints[2];
            
            maxPerimeterIndex = 6;
            
            if (all(((altSideIndices + uchar2(1, -1)) & 3) == mainSideIndex))
            {
                vertices[1] = projectedPoints[3];
                vertices[2] = projectedPoints[1];
                
                vertices[3] = corners1.columns[mainSideIndex];
                vertices[4] = projectedPoints[0];
                
                triangleIndexType = oneTwo_TwoOnes_0;
                geometryCounts = { 6, 2 };
                
                return;
            }
            
            vertices[2] = corners1.columns[mainSideIndex];
            
            vertices[3] = projectedPoints[0];
            vertices[4] = projectedPoints[1];
            vertices[5] = projectedPoints[2];
            vertices[6] = projectedPoints[3];
            
            oneTwo_TwoOnes_4_common_2(CALL_INTERSECTION_PARAMS, mainSideIndex, altSideIndices);
            
            return;
        }
        case twoTwos_ZeroOnes_0_0:
        case twoTwos_TwoOnes:
        {
            uchar sideIndex1, sideIndex2, sideIndex3, sideIndex4;
            searchForElementCount(2, intersectionsPerSide, sideIndex1, sideIndex2);
            if (decrement(sideIndex1) == sideIndex2) { swap(sideIndex1, sideIndex2); }
            
            ushort maxThreadID = select(4, 6, triangleIndexType == twoTwos_TwoOnes);
            
            if (triangleIndexType == twoTwos_TwoOnes)
            {
                searchForElementCount(1, intersectionsPerSide,  sideIndex3, sideIndex4);
                if (decrement(sideIndex3) == sideIndex4) { swap(sideIndex3, sideIndex4); }
            }
            
            for (ushort thread_id = 0; thread_id < maxThreadID; ++thread_id)
            {
                ushort quadgroup_id    = thread_id >> 2;
                ushort id_in_quadgroup = thread_id & 3;
                
                uchar sideIndex, withinSideIndex;
                
                if (quadgroup_id == 0)
                {
                    sideIndex = (id_in_quadgroup < 2) ? sideIndex1 : sideIndex2;
                    withinSideIndex = id_in_quadgroup & 1;
                }
                else
                {
                    sideIndex = (id_in_quadgroup == 0) ? sideIndex3 : sideIndex4;
                    withinSideIndex = 0;
                }
                
                auto intersectionProgress = intersectionProgresses[sideIndex][withinSideIndex];
                auto targetSide = makeSide(corners1, sideIndex);
                
                projectedPoints[thread_id] = getPoint(targetSide, intersectionProgress);
            }
            
            vertices[0] = corners1.columns[increment(sideIndex1)];
            
            if (triangleIndexType == twoTwos_TwoOnes)
            {
                vertices[1] = projectedPoints[2];
                vertices[2] = projectedPoints[1];
                
                vertices[3] = corners1.columns[flip(sideIndex1)];
                vertices[4] = projectedPoints[4];
                vertices[5] = projectedPoints[3];
                
                vertices[6] = corners1.columns[sideIndex1];
                vertices[7] = projectedPoints[0];
                vertices[8] = projectedPoints[5];
                
                geometryCounts = { 9, 3 };
                maxPerimeterIndex = 8;
                
                return;
            }
            
            vertices[4] = projectedPoints[0];
            vertices[5] = projectedPoints[1];
            vertices[6] = projectedPoints[2];
            vertices[7] = projectedPoints[3];
            
            twoTwos_ZeroOnes_0_0_combined(CALL_INTERSECTION_PARAMS, sideIndex1, sideIndex2);
            
            return;
        }
        case threeTwos_ZeroOnes_0:
        {
            uchar3 sideIndices;
            threeTwos_ZeroOnes_0_common_1(CALL_INTERSECTION_PARAMS, sideIndexForCorners, sideIndices);
            
            for (ushort thread_id = 0; thread_id < 6; ++thread_id)
            {
                uchar sideIndex = sideIndices[thread_id >> 1];
                uchar withinSideIndex = thread_id & 1;
                
                auto intersectionProgress = intersectionProgresses[sideIndex][withinSideIndex];
                auto targetSide = makeSide(corners1, sideIndex);
                
                projectedPoints[thread_id] = getPoint(targetSide, intersectionProgress);
            }
            
            vertices[6] = projectedPoints[2];
            vertices[7] = projectedPoints[3];
            vertices[8] = projectedPoints[4];
            vertices[9] = projectedPoints[5];
            
            threeTwo_ZeroOnes_0_common_2(CALL_INTERSECTION_PARAMS, sideIndices);
            
            break; // assigning vertices 0 through 5 in code shared with another case
        }
        default:
        {
            for (ushort thread_id = 0; thread_id < 8; ++thread_id)
            {
                uchar sideIndex       = thread_id >> 1;
                uchar withinSideIndex = thread_id & 1;
                
                auto intersectionProgress = intersectionProgresses[sideIndex][withinSideIndex];
                auto targetSide = makeSide(corners1, sideIndex);
                
                projectedPoints[thread_id] = getPoint(targetSide, intersectionProgress);
            }
            
            vertices[0] = corners1[0];
            vertices[1] = projectedPoints[0];
            vertices[2] = projectedPoints[7];
            
            vertices[3] = corners1[1];
            vertices[4] = projectedPoints[2];
            vertices[5] = projectedPoints[1];
            
            vertices[6] = corners1[2];
            vertices[7] = projectedPoints[4];
            vertices[8] = projectedPoints[3];
            
            vertices[9]  = corners1[3];
            vertices[10] = projectedPoints[6];
            vertices[11] = projectedPoints[5];
            
            geometryCounts = { 12, 4 };
            maxPerimeterIndex = 11;
            
            return;
        }
    }
    
    uchar4 cornerIndices = (uchar4(sideIndexForCorners) - uchar4(3, 2, 1, 0)) & 3;
    
    vertices[0] = corners1.columns[cornerIndices[0]];
    vertices[1] = corners1.columns[cornerIndices[1]];
    vertices[2] = corners1.columns[cornerIndices[2]];
    vertices[3] = corners1.columns[cornerIndices[3]];
    
    vertices[4] = projectedPoints[0];
    vertices[5] = projectedPoints[1];
}
