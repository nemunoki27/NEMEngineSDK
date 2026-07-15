//============================================================================
//	include
//============================================================================
#include "particleTrail.hlsli"

//============================================================================
//	main
//============================================================================
VSOutput main(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID) {

	const uint pointIndex = gTrailSegments[instanceID];
	const ParticleTrailPointData point0 = gTrailPoints[pointIndex];
	const ParticleTrailPointData point1 = gTrailPoints[pointIndex + 1u];

	if (vertexID == 0u) {
		return BuildTrailVertex(point0, -1.0f, 0.0f, point0.materialIndex);
	}
	if (vertexID == 1u || vertexID == 4u) {
		return BuildTrailVertex(point0, 1.0f, 1.0f, point0.materialIndex);
	}
	if (vertexID == 3u) {
		return BuildTrailVertex(point1, -1.0f, 0.0f, point0.materialIndex);
	}
	return BuildTrailVertex(point1, vertexID == 5u ? 1.0f : -1.0f,
		vertexID == 5u ? 1.0f : 0.0f, point0.materialIndex);
}
