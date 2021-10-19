//
//  Utilities_Implementation.metal
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/13/21.
//

#include <metal_stdlib>
#include "Utilities.metal"
using namespace metal;

namespace Utilities = CircleIntersectionUtilities;

void Utilities::getIntersectionAngleRange(threadgroup void *tg_8bytes_angleRange,
                                          float2 origin1, float2 origin2,
                                          float radius,
                                          ushort quadgroup_id)
{
    float2 delta = origin2 - origin1;
    float deltaLengthSquared = length_squared(delta);
    
    float2 coords_squared = { 0.25 * deltaLengthSquared };
    coords_squared.y = fma(radius, radius, -coords_squared.x);
    
    auto tg_coords = reinterpret_cast<threadgroup float*>(tg_8bytes_angleRange);
    tg_coords[quadgroup_id] = fast::sqrt(coords_squared[quadgroup_id]);
    
    float2 coords = { tg_coords[0] };
    if (coords.x >= radius)
    {
        tg_coords[0] = NAN;
        return;
    }
    coords.y = tg_coords[1];
    
    float2 yComponent = float2(-delta.y, delta.x) * fast::rsqrt(deltaLengthSquared);
    if (quadgroup_id == 1) { coords.y = -coords.y; }
    yComponent *= coords.y;
    
    delta = fma(delta, 0.5, yComponent);
    
    float thread_angle = fast::atan2(delta.y, delta.x);
    tg_coords[quadgroup_id] = thread_angle;
    
    if (quadgroup_id == 1 && tg_coords[0] > thread_angle)
    {
        tg_coords[1] = thread_angle + (2 * M_PI_F);
    }
}

void Utilities::Serial::getIntersectionAngleRange(thread void *t_8bytes_angleRange,
                                                  float2 origin1, float2 origin2,
                                                  float radius)
{
    float2 delta = origin2 - origin1;
    float deltaLengthSquared = length_squared(delta);
    
    float2 coords_squared = { 0.25 * deltaLengthSquared };
    coords_squared.y = fma(radius, radius, -coords_squared.x);
    
    auto t_coords = reinterpret_cast<thread float*>(t_8bytes_angleRange);
    t_coords[0] = fast::sqrt(coords_squared[0]);
    t_coords[1] = fast::sqrt(coords_squared[1]);
    
    float2 coords = { t_coords[0] };
    if (coords.x >= radius)
    {
        t_coords[0] = NAN;
        return;
    }
    coords.y = t_coords[1];
    
    for (ushort quadgroup_id = 0; quadgroup_id < 2; ++quadgroup_id)
    {
        float2 yComponent = float2(-delta.y, delta.x) * fast::rsqrt(deltaLengthSquared);
        if (quadgroup_id == 1) { coords.y = -coords.y; }
        yComponent *= coords.y;
        
        delta = fma(delta, 0.5, yComponent);
        
        float thread_angle = fast::atan2(delta.y, delta.x);
        t_coords[quadgroup_id] = thread_angle;
    }
    
    if (t_coords[0] > t_coords[1])
    {
        t_coords[1] += 2 * M_PI_F;
    }
}



// Runs on 2 parallel threads
inline float2 intersectLines(threadgroup void *tg_8bytes,
                             float2x2 line1, float2x2 line2,
                             ushort quadgroup_id)
{
#define RETURN_NAN  \
float2 output;      \
output.x = NAN;     \
return output;      \
    
    float2 delta1 = line1[1] - line1[0];
    float2 delta2 = line2[1] - line2[0];
    
    float denominator = fma(delta1.x, delta2.y, -delta1.y * delta2.x);
    if (abs(denominator) <= FLT_MIN) { RETURN_NAN; }
    
    float determinant1 = fma(line1[1].x, line1[0].y, -line1[1].y * line1[0].x);
    float determinant2 = fma(line2[1].x, line2[0].y, -line2[1].y * line2[0].x);
    
    float thread_numerator = -delta1[quadgroup_id] * determinant2;
    thread_numerator = fma(determinant1, delta2[quadgroup_id], thread_numerator);
    
    auto tg_coords = reinterpret_cast<threadgroup float*>(tg_8bytes);
    tg_coords[quadgroup_id] = fast::divide(thread_numerator, denominator);
    
    float2 intersection(tg_coords[0], tg_coords[1]);
    if (isinf(intersection.x) || isinf(intersection.y)) { RETURN_NAN; }
    
    return intersection;
}

void Utilities::combineAngleRanges(threadgroup void *tg_64bytes,
                                   thread float2 *angleRanges,
                                   thread float2 *arcSharedPoints,
                                   thread ushort &numValidIntersections,
                                   thread float2 &endPoint, thread half2 &endNormal,
                                   bool onlyFindingEndPoint,
                                   
                                   float2 origin, float radius,
                                   ushort id_in_quadgroup,
                                   ushort quadgroup_id)
{
    bool returningTwoRanges;
    auto ranges = angleRanges;
    
    if (!onlyFindingEndPoint)
    {
        if (angleRanges[0][0] > angleRanges[1][0])
        {
            float2 temp    = angleRanges[0];
            angleRanges[0] = angleRanges[1];
            angleRanges[1] = temp;
        }
        
        float adjustedEnd = ranges[1][1] - (2 * M_PI_F);
        
        if (ranges[0][1] <= ranges[1][0])
        {
            if (adjustedEnd <= ranges[0][0])
            {
                numValidIntersections = 0;
                return;
            }
            else if (adjustedEnd < ranges[0][1])
            {
                returningTwoRanges = false;
                ranges[1][0] -= 2 * M_PI_F;
                ranges[1][1]  = adjustedEnd;
            }
            else
            {
                ranges[1][0] = NAN;
            }
        }
        else if (ranges[0][1] < ranges[1][1])
        {
            returningTwoRanges = adjustedEnd >= ranges[0][0];
            
            if (returningTwoRanges)
            {
                ranges[1][1] = adjustedEnd;
                
                float temp   = ranges[0][0];
                ranges[0][0] = ranges[1][0];
                ranges[1][0] = temp;
            }
            else
            {
                float2 temp = ranges[0];
                ranges[0] = ranges[1];
                ranges[1] = temp;
            }
        }
        else
        {
            ranges[0] = ranges[1];
            ranges[1][0] = NAN;
        }
    }
    
    auto tg_endPoints = reinterpret_cast<threadgroup float2*>(tg_64bytes);
    auto tg_endNormals = reinterpret_cast<threadgroup half2*>(tg_endPoints + 4);
    
    ushort rangeIndex = id_in_quadgroup >> 1;
    float cosval;
    float sinval = fast::sincos(ranges[rangeIndex][id_in_quadgroup & 1], cosval);
    
    tg_endPoints[id_in_quadgroup] = fma(radius, float2(cosval, sinval), origin);
    tg_endNormals[id_in_quadgroup] = half2(cosval, sinval);
    
    auto endPoints1 = arcSharedPoints;
    endPoints1[1] = tg_endPoints[1];
    endPoint = endPoints1[1];
    endNormal = tg_endNormals[1];
    
    if (onlyFindingEndPoint) { return; }
    endPoints1[0] = tg_endPoints[0];
    
    if (isnan(ranges[1][0]))
    {
        numValidIntersections = 1;
    }
    else
    {
        float2 endPoints2[2];
        endPoints2[0] = tg_endPoints[2];
        endPoints2[1] = tg_endPoints[3];
        
        if (!returningTwoRanges || quadgroup_id == 1)
        {
            endPoint = endPoints2[1];
            endNormal = tg_endNormals[3];
        }
        
        if (returningTwoRanges)
        {
            arcSharedPoints[1] = endPoints1[0];
            arcSharedPoints[0] = endPoints2[0];
            
            if (quadgroup_id == 1)
            {
                endPoint = endPoints2[1];
                endNormal = tg_endNormals[3];
            }
            
            return;
        }
        
        numValidIntersections = 1;
        ranges[0][1] = ranges[1][1];
        
        float2 intersection = intersectLines(tg_64bytes,
                                             float2x2(endPoints1[0], endPoints1[1]),
                                             float2x2(endPoints2[0], endPoints2[1]),
                                             rangeIndex);
        
        if (!isnan(intersection.x))
        {
            arcSharedPoints[0] = intersection;
            return;
        }
        
        endPoints1[1] = endPoints2[1];
    }
    
    arcSharedPoints[0] = (endPoints1[0] + endPoints1[1]) * 0.5;
}



inline float2 intersectLines(float2x2 line1, float2x2 line2)
{
    float2 delta1 = line1[1] - line1[0];
    float2 delta2 = line2[1] - line2[0];
    
    float denominator = fma(delta1.x, delta2.y, -delta1.y * delta2.x);
    if (abs(denominator) <= FLT_MIN) { RETURN_NAN; }
    
    float determinant1 = fma(line1[1].x, line1[0].y, -line1[1].y * line1[0].x);
    float determinant2 = fma(line2[1].x, line2[0].y, -line2[1].y * line2[0].x);
    
    float2 intersectionCoords;
    
    for (ushort quadgroup_id = 0; quadgroup_id < 2; ++quadgroup_id)
    {
        float thread_numerator = -delta1[quadgroup_id] * determinant2;
        thread_numerator = fma(determinant1, delta2[quadgroup_id], thread_numerator);
        
        intersectionCoords[quadgroup_id] = fast::divide(thread_numerator, denominator);
    }
    
    if (any(isinf(intersectionCoords))) { RETURN_NAN; }
    
    return intersectionCoords;
}

void Utilities::Serial::combineAngleRanges(thread float2 *angleRanges,
                                           thread float2 *arcSharedPoints,
                                           thread ushort &numValidIntersections,
                                           thread float2 *endPoints, thread half2 *endNormals,
                                           bool onlyFindingEndPoint,
                                           
                                           float2 origin, float radius)
{
    bool returningTwoRanges;
    auto ranges = angleRanges;
    
    if (!onlyFindingEndPoint)
    {
        if (angleRanges[0][0] > angleRanges[1][0])
        {
            float2 temp    = angleRanges[0];
            angleRanges[0] = angleRanges[1];
            angleRanges[1] = temp;
        }
        
        float adjustedEnd = ranges[1][1] - (2 * M_PI_F);
        
        if (ranges[0][1] <= ranges[1][0])
        {
            if (adjustedEnd <= ranges[0][0])
            {
                numValidIntersections = 0;
                return;
            }
            else if (adjustedEnd < ranges[0][1])
            {
                returningTwoRanges = false;
                ranges[1][0] -= 2 * M_PI_F;
                ranges[1][1]  = adjustedEnd;
            }
            else
            {
                ranges[1][0] = NAN;
            }
        }
        else if (ranges[0][1] < ranges[1][1])
        {
            returningTwoRanges = adjustedEnd >= ranges[0][0];
            
            if (returningTwoRanges)
            {
                ranges[1][1] = adjustedEnd;
                
                float temp   = ranges[0][0];
                ranges[0][0] = ranges[1][0];
                ranges[1][0] = temp;
            }
            else
            {
                float2 temp = ranges[0];
                ranges[0] = ranges[1];
                ranges[1] = temp;
            }
        }
        else
        {
            ranges[0] = ranges[1];
            ranges[1][0] = NAN;
        }
    }
    
    float2 t_endPoints[4];
    half2 t_endNormals[4];
    
    for (ushort id_in_quadgroup = 0; id_in_quadgroup < 4; ++id_in_quadgroup)
    {
        ushort rangeIndex = id_in_quadgroup >> 1;
        float cosval;
        float sinval = fast::sincos(ranges[rangeIndex][id_in_quadgroup & 1], cosval);
        
        t_endPoints[id_in_quadgroup] = fma(radius, float2(cosval, sinval), origin);
        t_endNormals[id_in_quadgroup] = half2(cosval, sinval);
    }
    
    auto endPoints1 = arcSharedPoints;
    endPoints1[1] = t_endPoints[1];
    
    for (ushort quadgroup_id = 0; quadgroup_id < 2; ++quadgroup_id)
    {
        endPoints[quadgroup_id] = endPoints1[1];
        endNormals[quadgroup_id] = t_endNormals[1];
    }
    
    if (onlyFindingEndPoint) { return; }
    endPoints1[0] = t_endPoints[0];
    
    if (isnan(ranges[1][0]))
    {
        numValidIntersections = 1;
    }
    else
    {
        float2 endPoints2[2];
        endPoints2[0] = t_endPoints[2];
        endPoints2[1] = t_endPoints[3];
        
        for (ushort quadgroup_id = 0; quadgroup_id < 2; ++quadgroup_id)
        {
            if (!returningTwoRanges || quadgroup_id == 1)
            {
                endPoints[quadgroup_id]  = endPoints2[1];
                endNormals[quadgroup_id] = t_endNormals[3];
            }
        }
        
        if (returningTwoRanges)
        {
            arcSharedPoints[1] = endPoints1[0];
            arcSharedPoints[0] = endPoints2[0];
            
            endPoints[1] = endPoints2[1];
            endNormals[1] = t_endNormals[3];
            
            return;
        }
        
        numValidIntersections = 1;
        ranges[0][1] = ranges[1][1];
        
        float2 intersection = intersectLines(float2x2(endPoints1[0], endPoints1[1]),
                                             float2x2(endPoints2[0], endPoints2[1]));
        
        if (!isnan(intersection.x))
        {
            arcSharedPoints[0] = intersection;
            return;
        }
        
        endPoints1[1] = endPoints2[1];
    }
    
    arcSharedPoints[0] = (endPoints1[0] + endPoints1[1]) * 0.5;
}
