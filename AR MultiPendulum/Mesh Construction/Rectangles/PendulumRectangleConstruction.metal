//
//  PendulumRectangleConstruction.metal
//  AR MultiPendulum
//
//  Created by Philip Turner on 7/8/21.
//

#include <metal_stdlib>
#include <ARHeadsetKit/ARObjectUtilities.h>
#include "PendulumRectangleUtilities.h"
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

constant uchar2 perimeterSearchParams[21] = {
    uchar2(0, 0),
    uchar2(0, 1),
    uchar2(0, 2),
    
    uchar2(1, 0),
    uchar2(1, 1),
    uchar2(1, 2),
    
    uchar2(2, 0),
    uchar2(2, 1),
    uchar2(2, 2),
    
    uchar2(3, 0),
    uchar2(3, 1),
    uchar2(3, 2),
    
    uchar2(4, 0),
    uchar2(4, 1),
    uchar2(4, 2),
    
    uchar2(5, 0),
    uchar2(5, 1),
    uchar2(5, 2),
    
    uchar2(6, 0),
    uchar2(6, 1),
    uchar2(6, 2),
};

kernel void makePendulumRectangleMesh(constant float2x2        *rectangles          [[ buffer(0) ]],
                                      constant ComputeUniforms &computeUniforms     [[ buffer(1) ]],
                                      constant VertexUniforms  &vertexUniforms      [[ buffer(2) ]],
                                      
                                      device   float2          *vertexBuffer        [[ buffer(3) ]],
                                      device   ushort4         *triangleIndexBuffer [[ buffer(4) ]],
                                      device   ushort3         *lineIndexBuffer     [[ buffer(5) ]],
                                      
                                      device   atomic_uint     *totalVertexCount    [[ buffer(6) ]],
                                      device   atomic_uint     *totalTriangleCount  [[ buffer(7) ]],
                                      device   atomic_uint     *totalLineCount      [[ buffer(8) ]],
                                      
                                      device   half2x2         *depthRanges         [[ buffer(10) ]],
                                      
                                      // threadgroup size must be 8
                                      ushort2 id        [[ threadgroup_position_in_grid ]],
                                      ushort2 grid_size [[ threadgroups_per_grid ]],
                                      ushort  thread_id [[ thread_index_in_threadgroup ]])
{
    ushort quadgroup_id = thread_id >> 2;
    uint originalRectangleID = mad24(id.x, grid_size.y, id.y);
    uint rectangleID = originalRectangleID;
    
    if (all(ushort2(id.y, quadgroup_id) != 0)) { rectangleID -= 1; }
    auto rectangle = rectangles[rectangleID];
    
    float2 delta = rectangle[1] - rectangle[0];
    float deltaLengthSquared = length_squared(delta);
    
    threadgroup bool shouldReturnEarly[1];
    if (thread_id == 0) { shouldReturnEarly[0] = deltaLengthSquared < computeUniforms.minDistanceSquared; }
    if (*shouldReturnEarly) { return; }
    
    float depthMultiplier = ((grid_size.x - id.x) << 1) - 1;
    float depth = computeUniforms.halfDepth * depthMultiplier;
    
    delta *= precise::rsqrt(deltaLengthSquared);
    
    // Create corners
    
    ushort id_in_quadgroup = thread_id & 3;
    
    ushort endPointID;
    float parallelShift   = computeUniforms.minDistance;
    float orthogonalShift = computeUniforms.rectangleHalfWidth;
    
    if (id_in_quadgroup == 0 || id_in_quadgroup == 3)
    {
        endPointID = 0;
    }
    else
    {
        endPointID = 1;
        parallelShift = -parallelShift;
    }
    
    if (id_in_quadgroup < 2) { orthogonalShift = -orthogonalShift; }

    float2 thread_corners = fma(delta, parallelShift, rectangle.columns[endPointID]);
    thread_corners = fma({ -delta.y, delta.x }, orthogonalShift, thread_corners);
    
    // Test if rectangle is outside of the user's frame of view
    
    float4 cullVertex;
    cullVertex.z = depth;
    cullVertex.w = 1;
    
    threadgroup float2 shuffledUpCorners[4];
    
    if (quadgroup_id == 0)
    {
        cullVertex.xy = thread_corners;
        shuffledUpCorners[id_in_quadgroup] = thread_corners;
    }
    if (!(quadgroup_id == 0))
    {
        cullVertex.xy = shuffledUpCorners[id_in_quadgroup];
        cullVertex.z = -cullVertex.z;
    }
    
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
    
    // Create front/back geometry (triangles)
    
    using namespace RectangleIntersectionUtilities;
    
    threadgroup float2 threadgroup_corners[2][4];
    threadgroup_corners[quadgroup_id][id_in_quadgroup] = thread_corners;
    
    float4x2 corners1 = {
        threadgroup_corners[0][0],
        threadgroup_corners[0][1],
        threadgroup_corners[0][2],
        threadgroup_corners[0][3],
    };

    float4x2 corners2 = {
        threadgroup_corners[1][0],
        threadgroup_corners[1][1],
        threadgroup_corners[1][2],
        threadgroup_corners[1][3],
    };
    
    bool initializedMesh = false;
    
    float2 possibleProgresses;
    
    if (id.y != 0)
    {
        ushort indexStart = quadgroup_id << 1;
        
        threadgroup bool combinedShouldReturnEarly[1];
        *combinedShouldReturnEarly = false;
        
        float2x2 line1 = makeSide(corners1, id_in_quadgroup);
        
        for (ushort i = 0; i < 2; ++i)
        {
            float2x2 line2 = makeSide(corners2, indexStart + i);
            possibleProgresses[i] = getIntersectionProgress(line1, line2, combinedShouldReturnEarly);
        }
        
        if (*combinedShouldReturnEarly == false) { initializedMesh = true; }
    }
    
    
    
    float2 intersectionProgresses;
    uchar2 intersectionIDs;
    uchar4 intersectionsPerSide;
    
    TriangleIndexType triangleIndexType;
    
    uchar corners1_insideMask;
    
    if (initializedMesh)
    {
        threadgroup float2 shuffledDownProgresses[4];
        threadgroup uchar combinedNumValidCandidates[4];
        
        if (quadgroup_id == 1)
        {
            shuffledDownProgresses[id_in_quadgroup] = possibleProgresses;
        }
        if (!(quadgroup_id == 1))
        {
            uchar numValidCandidates = 0;
            
            for (uchar i = 0; i < 2; ++i)
            {
                if (!isnan(possibleProgresses[i]))
                {
                    intersectionProgresses[numValidCandidates] = possibleProgresses[i];
                    intersectionIDs       [numValidCandidates] = i;
                    
                    ++numValidCandidates;
                }
            }
            
            float2 retrievedProgresses = shuffledDownProgresses[id_in_quadgroup];
            
            for (uchar i = 0; i < 2; ++i)
            {
                if (!isnan(retrievedProgresses[i]))
                {
                    intersectionProgresses[numValidCandidates] = retrievedProgresses[i];
                    intersectionIDs       [numValidCandidates] = i + 2;
                    
                    ++numValidCandidates;
                }
            }
            
            combinedNumValidCandidates[id_in_quadgroup] = numValidCandidates;
        }
        
        for (uchar i = 0; i < 4; ++i)
        {
            intersectionsPerSide[i] = combinedNumValidCandidates[i];
        }
        
        uint numOnes = popcount(as_type<uint>(intersectionsPerSide & 1));
        uint numTwos = popcount(as_type<uint>(intersectionsPerSide & 2));
        
        triangleIndexType = getTriangleIndexType(numOnes, numTwos);
        
        if (triangleIndexType == allZeroes || triangleIndexType == zeroTwos_TwoOnes_0)
        {
            threadgroup bool threadgroup_corners1_areInside[4];
            threadgroup_corners1_areInside[id_in_quadgroup] = true;
            
            float2 selectedCorner1 = corners1.columns[id_in_quadgroup];
            
            ushort i     = quadgroup_id << 1;
            ushort i_end = i + 2;
            
            for (; i < i_end; ++i)
            {
                float2 sideDelta   = corners2.columns[(i + 1) & 3] - corners2.columns[i];
                float2 cornerDelta = selectedCorner1               - corners2.columns[i];
                
                if (fma(sideDelta.x, cornerDelta.y, -sideDelta.y * cornerDelta.x) < 0)
                {
                    threadgroup_corners1_areInside[id_in_quadgroup] = false;
                }
            }
            
            bool4 combinedCorners1_areInside = {
                threadgroup_corners1_areInside[0],
                threadgroup_corners1_areInside[1],
                threadgroup_corners1_areInside[2],
                threadgroup_corners1_areInside[3]
            };
            
            if (triangleIndexType == allZeroes)
            {
                initializedMesh = false;
            }
            else
            {
                uchar4 maskElements = select(0, uchar4(1, 2, 4, 8), combinedCorners1_areInside);
                maskElements.xy |= maskElements.zw;
                
                corners1_insideMask = maskElements[0] | maskElements[1];
            }
        }
    }
    else
    {
        triangleIndexType = notInitialized;
    }
    
    uchar3 geometryCounts; // vertex, triangle, line
    ushort maxPerimeterIndex;
    
    float2 vertices[12];
    
    if (initializedMesh)
    {
        threadgroup float2 threadgroup_intersectionProgresses[4];
        threadgroup uchar2 threadgroup_intersectionIDs[4];
        
        if (quadgroup_id == 0)
        {
            threadgroup_intersectionProgresses[id_in_quadgroup] = intersectionProgresses;
            threadgroup_intersectionIDs       [id_in_quadgroup] = intersectionIDs;
        }
        
        float2 intersectionProgresses[4];
        uchar2 intersectionIDs       [4];
        
        for (uchar i = 0; i < 4; ++i)
        {
            intersectionProgresses[i] = threadgroup_intersectionProgresses[i];
            intersectionIDs       [i] = threadgroup_intersectionIDs       [i];
        }
        
        threadgroup ulong4 tg_64bytes[2];

        intersectionFunction(tg_64bytes,
                             CALL_INTERSECTION_PARAMS,

                             id_in_quadgroup,
                             quadgroup_id,
                             thread_id);
    }
    else
    {
        geometryCounts = { 4, 2 };
        maxPerimeterIndex = 3;
        
        vertices[0] = corners1[0];
        vertices[1] = corners1[1];
        vertices[2] = corners1[2];
        vertices[3] = corners1[3];
    }
    
    constant uchar3 *triangleIndices = getTriangleIndices(triangleIndexType);
    
    // Create side geometry (lines)
    
    threadgroup float2 tg_targetDelta[1];
    if (quadgroup_id == 0) { *tg_targetDelta = delta; }
    delta = *tg_targetDelta;
    
    threadgroup bool verticesAreCorner[12];
    
    for (ushort i = thread_id; i < geometryCounts[0]; i += 8)
    {
        float2 selectedVertex = vertices[i];
        verticesAreCorner[i] = false;

        for (uchar j = 0; j < 4; ++j)
        {
            if (all(selectedVertex == corners1.columns[j]))
            {
                verticesAreCorner[i] = true;
            }
        }
    }
    
    threadgroup uchar2 lineIndices[8];
    threadgroup uint numLines[1];
    *numLines = 0;
    
    ushort numSearchParams = (geometryCounts[1] << 1) + geometryCounts[1];
    
    for (ushort paramIndex = thread_id; paramIndex < numSearchParams; paramIndex += 8)
    {
        ushort2 ij = ushort2(perimeterSearchParams[paramIndex]);
        uchar3 selectedTriangleIndices = triangleIndices[ij[0]];
        
        ushort k = (ij[1] == 2) ? 0 : ij[1] + 1;
        uchar2 indices(selectedTriangleIndices[ij[1]], selectedTriangleIndices[k]);
        if (any(indices > maxPerimeterIndex)) { continue; }
        
        bool2 isCornerMask(verticesAreCorner[indices[0]], verticesAreCorner[indices[1]]);
        if (!any(isCornerMask)) { continue; }
        
        
        
        float2 segmentDelta = vertices[indices[1]] - vertices[indices[0]];
        float segmentDeltaLengthSquared = -0.99 * length_squared(segmentDelta);
        
        float dotProduct1 = dot(segmentDelta, delta);
        if (fma(dotProduct1, dotProduct1, segmentDeltaLengthSquared) < 0)
        {
            continue;
        }
        
        auto atomicNumLinesRef = reinterpret_cast<threadgroup atomic_uint*>(numLines);
        uint retrievedNumLines = atomic_fetch_add_explicit(atomicNumLinesRef, 1, memory_order_relaxed);
        
        lineIndices[retrievedNumLines] = indices;
    }
    
    simdgroup_barrier(mem_flags::mem_threadgroup);
    
    geometryCounts[2] = *numLines;
    
    // Write mesh to device memory
    
    threadgroup ushort offsets[3];
    bool amplifyingAnyPendulums = computeUniforms.doingAmplification;
    bool amplifyingSelectedPendulum = id.x + 1 < grid_size.x;
    
    if (thread_id < 3)
    {
        device atomic_uint *target;
        
        if (thread_id == 0)
        {
            target = totalVertexCount;
            
            half2x2 selectedDepthRanges;
            float halfDepth   = computeUniforms.halfDepth;
            float insideDepth = fma(halfDepth, -2, depth);
            
            float depthOffset = clamp(2e-4 - halfDepth, -1e-4, float(0));
            depth       += depthOffset;
            insideDepth -= depthOffset;
            
            if (amplifyingAnyPendulums)
            {
                if (amplifyingSelectedPendulum)
                {
                    selectedDepthRanges[0] = half2(-depth, -insideDepth);
                    selectedDepthRanges[1] = half2( insideDepth,  depth);
                }
                else
                {
                    selectedDepthRanges[0] = half2(insideDepth, depth);
                }
            }
            else
            {
                selectedDepthRanges[0] = half2(-depth, -insideDepth);
            }
            
            depthRanges[originalRectangleID] = selectedDepthRanges;
        }
        else if (thread_id == 1) { target = totalTriangleCount; }
        else                     { target = totalLineCount; }
        
        offsets[thread_id] = atomic_fetch_add_explicit(target, geometryCounts[thread_id], memory_order_relaxed);
    }
    
    ushort vertexOffset = offsets[0];
    auto selectedVertices = vertexBuffer + vertexOffset;
    
    for (ushort i = thread_id; i < geometryCounts[0]; i += 8)
    {
        selectedVertices[i] = vertices[i];
    }
    
    ushort depthRangeData = (originalRectangleID << 1) + select(1, 0, amplifyingAnyPendulums && amplifyingSelectedPendulum);
    
    auto selectedTriangleIndices = triangleIndexBuffer + offsets[1];
    auto selectedLineIndices     = lineIndexBuffer     + offsets[2];
    
    for (ushort i = thread_id; i < geometryCounts[1]; i += 8)
    {
        selectedTriangleIndices[i] = ushort4(vertexOffset + ushort3(triangleIndices[i]), depthRangeData);
    }
    
    for (ushort i = thread_id; i < geometryCounts[2]; i += 8)
    {
        selectedLineIndices[i] = ushort3(vertexOffset + ushort2(lineIndices[i]), depthRangeData);
    }
}



kernel void makePendulumRectangleMesh2(constant float2x2        *rectangles          [[ buffer(0) ]],
                                       constant ComputeUniforms &computeUniforms     [[ buffer(1) ]],
                                       constant VertexUniforms  &vertexUniforms      [[ buffer(2) ]],
                                       
                                       device   float2          *vertexBuffer        [[ buffer(3) ]],
                                       device   ushort4         *triangleIndexBuffer [[ buffer(4) ]],
                                       device   ushort3         *lineIndexBuffer     [[ buffer(5) ]],
                                       
                                       device   atomic_uint     *totalVertexCount    [[ buffer(6) ]],
                                       device   atomic_uint     *totalTriangleCount  [[ buffer(7) ]],
                                       device   atomic_uint     *totalLineCount      [[ buffer(8) ]],
                                       
                                       device   half2x2         *depthRanges         [[ buffer(10) ]],
                                       
                                       ushort2 id        [[ thread_position_in_grid ]],
                                       ushort2 grid_size [[ threads_per_grid ]])
{
    ushort2 rectangleIDs(mad24(id.x, grid_size.y, id.y));
    if (id.y > 0) { rectangleIDs[1] -= 1; }
    
    float2x2 selectedRectangles[2] = {
        rectangles[as_type<short>(rectangleIDs[0])],
        rectangles[as_type<short>(rectangleIDs[1])]
    };
    
    float2 deltas[2] = {
        selectedRectangles[0][1] - selectedRectangles[0][0],
        selectedRectangles[1][1] - selectedRectangles[1][0]
    };
    
    float deltaLengthsSquared[2] = {
        length_squared(deltas[0]),
        length_squared(deltas[1])
    };
    
    if (deltaLengthsSquared[0] < computeUniforms.minDistanceSquared)
    {
        return;
    }
    
    float depthMultiplier = ((grid_size.x - id.x) << 1) - 1;
    float depth = computeUniforms.halfDepth * depthMultiplier;
    
    deltas[0] *= precise::rsqrt(deltaLengthsSquared[0]);
    deltas[1] *= precise::rsqrt(deltaLengthsSquared[1]);
    
    // Create corners
    
    float4x2 cornerArray[2];
    auto corners = reinterpret_cast<thread float2*>(cornerArray);
    
    float parallelShift   = computeUniforms.minDistance;
    float orthogonalShift = computeUniforms.rectangleHalfWidth;
    
    for (ushort thread_id = 0; thread_id < 8; ++thread_id)
    {
        ushort quadgroup_id = thread_id >> 2;
        ushort id_in_quadgroup = thread_id & 3;
        
        ushort endPointID;
        
        if (id_in_quadgroup == 0 || id_in_quadgroup == 3)
        {
            endPointID = 0;
            parallelShift = copysign(parallelShift, 1);
        }
        else
        {
            endPointID = 1;
            parallelShift = copysign(parallelShift, -1);
        }
        
        orthogonalShift = copysign(orthogonalShift, select(1, -1, id_in_quadgroup < 2));
        
        float2 delta = deltas[quadgroup_id];
        float2 thread_corners = fma(delta, parallelShift, selectedRectangles[quadgroup_id].columns[endPointID]);
        corners[thread_id] = fma({ -delta.y, delta.x }, orthogonalShift, thread_corners);
    }
    
    // Test if rectangle is outside of the user's frame of view
    
    float4 cullVertices[8];
    
    for (ushort thread_id = 0; thread_id < 8; ++thread_id)
    {
        ushort quadgroup_id = thread_id >> 2;
        ushort id_in_quadgroup = thread_id & 3;
        
        float4 cullVertex;
        cullVertex.xy = corners[id_in_quadgroup];
        cullVertex.z = copysign(depth, select(-1, 1, quadgroup_id == 0));
        cullVertex.w = 1;
        
        cullVertices[thread_id] = vertexUniforms.cullTransform * cullVertex;
    }
    
    if (ARObjectUtilities::Serial::shouldCull(cullVertices))
    {
        return;
    }
    
    // Create front/back geometry (triangles)
    
    using namespace RectangleIntersectionUtilities;
    using namespace RectangleIntersectionUtilities::Serial;
    
    float4x2 corners1 = cornerArray[0];
    float4x2 corners2 = cornerArray[1];
    
    bool initializedMesh = false;
    
    float2 possibleProgresses_array[8];
    
    if (id.y != 0)
    {
        bool shouldReturnEarly = false;
        
        for (ushort thread_id = 0; thread_id < 8; ++thread_id)
        {
            ushort quadgroup_id = thread_id >> 2;
            ushort id_in_quadgroup = thread_id & 3;
            ushort indexStart = quadgroup_id << 1;
            
            float2x2 line1 = makeSide(corners1, id_in_quadgroup);
            
            possibleProgresses_array[thread_id][0] = getIntersectionProgress(line1, makeSide(corners2, indexStart),
                                                                             shouldReturnEarly);

            possibleProgresses_array[thread_id][1] = getIntersectionProgress(line1, makeSide(corners2, indexStart + 1),
                                                                             shouldReturnEarly);
        }
        
        if (shouldReturnEarly == false) { initializedMesh = true; }
    }
    
    
    
    float2 intersectionProgresses[4];
    uchar2 intersectionIDs[4];
    uchar4 intersectionsPerSide;
    
    TriangleIndexType triangleIndexType;
    
    uchar corners1_insideMask;
    
    if (initializedMesh)
    {
        for (ushort id_in_quadgroup = 0; id_in_quadgroup < 4; ++id_in_quadgroup)
        {
            float2 possibleProgresses = possibleProgresses_array[id_in_quadgroup];
            ushort numValidCandidates = 0;
            
            for (uchar i = 0; i < 2; ++i)
            {
                if (!isnan(possibleProgresses[i]))
                {
                    intersectionProgresses[numValidCandidates] = possibleProgresses[i];
                    intersectionIDs       [numValidCandidates] = i;
                    
                    ++numValidCandidates;
                }
            }
            
            float2 retrievedProgresses = possibleProgresses_array[id_in_quadgroup + 4];
            
            for (uchar i = 0; i < 2; ++i)
            {
                if (!isnan(retrievedProgresses[i]))
                {
                    intersectionProgresses[numValidCandidates] = retrievedProgresses[i];
                    intersectionIDs       [numValidCandidates] = i + 2;
                    
                    ++numValidCandidates;
                }
            }
            
            intersectionsPerSide[id_in_quadgroup] = numValidCandidates;
        }
        
        uint numOnes = popcount(as_type<uint>(intersectionsPerSide & 1));
        uint numTwos = popcount(as_type<uint>(intersectionsPerSide & 2));
        
        triangleIndexType = getTriangleIndexType(numOnes, numTwos);
        
        if (triangleIndexType == allZeroes || triangleIndexType == zeroTwos_TwoOnes_0)
        {
            bool4 corners1_areInside(true);
            
            for (ushort thread_id = 0; thread_id < 8; ++thread_id)
            {
                ushort quadgroup_id = thread_id >> 2;
                ushort id_in_quadgroup = thread_id & 3;
                
                float2 selectedCorner1 = corners1.columns[id_in_quadgroup];
                
                ushort i     = quadgroup_id << 1;
                ushort i_end = i + 2;
                
                for (; i < i_end; ++i)
                {
                    float2 sideDelta   = corners2.columns[(i + 1) & 3] - corners2.columns[i];
                    float2 cornerDelta = selectedCorner1               - corners2.columns[i];
                    
                    if (fma(sideDelta.x, cornerDelta.y, -sideDelta.y * cornerDelta.x) < 0)
                    {
                        corners1_areInside[id_in_quadgroup] = false;
                    }
                }
            }
            
            if (triangleIndexType == allZeroes)
            {
                initializedMesh = false;
            }
            else
            {
                uchar4 maskElements = select(0, uchar4(1, 2, 4, 8), corners1_areInside);
                maskElements.xy |= maskElements.zw;
                
                corners1_insideMask = maskElements[0] | maskElements[1];
            }
        }
    }
    else
    {
        triangleIndexType = notInitialized;
    }
    
    uchar3 geometryCounts; // vertex, triangle, line
    ushort maxPerimeterIndex;
    
    float2 vertices[12];
    
    if (initializedMesh)
    {
        intersectionFunction(CALL_INTERSECTION_PARAMS);
    }
    else
    {
        geometryCounts = { 4, 2 };
        maxPerimeterIndex = 3;
        
        vertices[0] = corners1[0];
        vertices[1] = corners1[1];
        vertices[2] = corners1[2];
        vertices[3] = corners1[3];
    }
    
    constant uchar3 *triangleIndices = getTriangleIndices(triangleIndexType);
    
    // Create side geometry (lines)
    
    float2 delta = deltas[0];
    
    bool verticesAreCorner[12];
    
    for (ushort i = 0; i < geometryCounts[0]; ++i)
    {
        float2 selectedVertex = vertices[i];
        verticesAreCorner[i] = false;

        for (uchar j = 0; j < 4; ++j)
        {
            if (all(selectedVertex == corners1.columns[j]))
            {
                verticesAreCorner[i] = true;
            }
        }
    }
    
    uchar2 lineIndices[8];
    ushort numLines = 0;
    
    ushort numSearchParams = (geometryCounts[1] << 1) + geometryCounts[1];
    
    for (ushort paramIndex = 0; paramIndex < numSearchParams; ++paramIndex)
    {
        ushort2 ij = ushort2(perimeterSearchParams[paramIndex]);
        uchar3 selectedTriangleIndices = triangleIndices[ij[0]];
        
        ushort k = (ij[1] == 2) ? 0 : ij[1] + 1;
        uchar2 indices(selectedTriangleIndices[ij[1]], selectedTriangleIndices[k]);
        if (any(indices > maxPerimeterIndex)) { continue; }
        
        bool2 isCornerMask(verticesAreCorner[indices[0]], verticesAreCorner[indices[1]]);
        if (!any(isCornerMask)) { continue; }
        
        
        
        float2 segmentDelta = vertices[indices[1]] - vertices[indices[0]];
        float segmentDeltaLengthSquared = -0.99 * length_squared(segmentDelta);
        
        float dotProduct1 = dot(segmentDelta, delta);
        if (fma(dotProduct1, dotProduct1, segmentDeltaLengthSquared) < 0)
        {
            continue;
        }
        
        lineIndices[numLines] = indices;
        ++numLines;
    }
    
    geometryCounts[2] = numLines;
    
    // Write mesh to device memory
    
    ushort offsets[3];
    bool amplifyingAnyPendulums = computeUniforms.doingAmplification;
    bool amplifyingSelectedPendulum = id.x + 1 < grid_size.x;
    
    for (ushort thread_id = 0; thread_id < 3; ++thread_id)
    {
        device atomic_uint *target;
        
        if (thread_id == 0)
        {
            target = totalVertexCount;
            
            half2x2 selectedDepthRanges;
            float halfDepth   = computeUniforms.halfDepth;
            float insideDepth = fma(halfDepth, -2, depth);
            
            float depthOffset = clamp(2e-4 - halfDepth, -1e-4, float(0));
            depth       += depthOffset;
            insideDepth -= depthOffset;
            
            if (amplifyingAnyPendulums)
            {
                if (amplifyingSelectedPendulum)
                {
                    selectedDepthRanges[0] = half2(-depth, -insideDepth);
                    selectedDepthRanges[1] = half2( insideDepth,  depth);
                }
                else
                {
                    selectedDepthRanges[0] = half2(insideDepth, depth);
                }
            }
            else
            {
                selectedDepthRanges[0] = half2(-depth, -insideDepth);
            }
            
            depthRanges[rectangleIDs[0]] = selectedDepthRanges;
        }
        else if (thread_id == 1) { target = totalTriangleCount; }
        else                     { target = totalLineCount; }
        
        offsets[thread_id] = atomic_fetch_add_explicit(target, geometryCounts[thread_id], memory_order_relaxed);
    }
    
    ushort vertexOffset = offsets[0];
    auto selectedVertices = vertexBuffer + vertexOffset;
    
    for (ushort i = 0; i < geometryCounts[0]; ++i)
    {
        selectedVertices[as_type<short>(i)] = vertices[i];
    }
    
    ushort depthRangeData = (rectangleIDs[0] << 1) + select(1, 0, amplifyingAnyPendulums && amplifyingSelectedPendulum);
    
    auto selectedTriangleIndices = triangleIndexBuffer + offsets[1];
    auto selectedLineIndices     = lineIndexBuffer     + offsets[2];
    
    for (ushort i = 0; i < geometryCounts[1]; ++i)
    {
        selectedTriangleIndices[as_type<short>(i)] = ushort4(vertexOffset + ushort3(triangleIndices[i]), depthRangeData);
    }
    
    for (ushort i = 0; i < geometryCounts[2]; ++i)
    {
        selectedLineIndices[as_type<short>(i)] = ushort3(vertexOffset + ushort2(lineIndices[i]), depthRangeData);
    }
}
