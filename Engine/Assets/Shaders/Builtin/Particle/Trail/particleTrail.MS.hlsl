//============================================================================
//	include
//============================================================================
#include "particleTrail.hlsli"

//============================================================================
//	resources
//============================================================================
cbuffer ParticleTrailConstants : register(b1) {

	uint segmentCount;
	uint3 _pad;
};

#define PARTICLE_TRAIL_GROUP_SEGMENTS 32

//============================================================================
//	main
//============================================================================
[numthreads(PARTICLE_TRAIL_GROUP_SEGMENTS, 1, 1)]
[outputtopology("triangle")]
void main(uint groupThreadID : SV_GroupThreadID, uint3 groupID : SV_GroupID,
	out vertices VSOutput verts[PARTICLE_TRAIL_GROUP_SEGMENTS * 4],
	out indices uint3 tris[PARTICLE_TRAIL_GROUP_SEGMENTS * 2]) {

	const uint segmentBase = groupID.x * PARTICLE_TRAIL_GROUP_SEGMENTS;
	const uint outputSegmentCount = segmentBase < segmentCount ?
		min((uint)PARTICLE_TRAIL_GROUP_SEGMENTS, segmentCount - segmentBase) : 0u;
	SetMeshOutputCounts(outputSegmentCount * 4u, outputSegmentCount * 2u);
	if (groupThreadID >= outputSegmentCount) {
		return;
	}

	const uint pointIndex = gTrailSegments[segmentBase + groupThreadID];
	const ParticleTrailPointData point0 = gTrailPoints[pointIndex];
	const ParticleTrailPointData point1 = gTrailPoints[pointIndex + 1u];
	const uint vertexBase = groupThreadID * 4u;
	const uint triangleBase = groupThreadID * 2u;

	verts[vertexBase] = BuildTrailVertex(point0, -1.0f, 0.0f, point0.materialIndex);
	verts[vertexBase + 1u] = BuildTrailVertex(point0, 1.0f, 1.0f, point0.materialIndex);
	verts[vertexBase + 2u] = BuildTrailVertex(point1, -1.0f, 0.0f, point0.materialIndex);
	verts[vertexBase + 3u] = BuildTrailVertex(point1, 1.0f, 1.0f, point0.materialIndex);
	tris[triangleBase] = uint3(vertexBase, vertexBase + 1u, vertexBase + 2u);
	tris[triangleBase + 1u] = uint3(vertexBase + 2u, vertexBase + 1u, vertexBase + 3u);
}
