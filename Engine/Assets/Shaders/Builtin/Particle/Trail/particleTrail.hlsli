#ifndef NEM_PARTICLE_TRAIL_HLSLI
#define NEM_PARTICLE_TRAIL_HLSLI

//============================================================================
//	include
//============================================================================
#include "../Common/particle.hlsli"

//============================================================================
//	resources
//============================================================================
struct ParticleTrailPointData {

	float3 position;
	float halfWidth;
	float3 tangent;
	float ribbonT;
	float4 color;
	uint materialIndex;
	float3 pad0;
};

StructuredBuffer<ParticleTrailPointData> gTrailPoints : register(t0, space3);
StructuredBuffer<uint> gTrailSegments : register(t1, space3);

//============================================================================
//	functions
//============================================================================
float3 NormalizeTrailVector(float3 value, float3 fallback) {

	const float lengthSq = dot(value, value);
	return 1e-8f < lengthSq ? value * rsqrt(lengthSq) : fallback;
}

float3 GetTrailSide(ParticleTrailPointData trailPoint) {

	const float3 direction = NormalizeTrailVector(trailPoint.tangent, float3(0.0f, 0.0f, 1.0f));
	const float3 viewDirection = NormalizeTrailVector(
		cameraPosition - trailPoint.position, float3(0.0f, 0.0f, 1.0f));
	float3 side = cross(direction, viewDirection);
	if (dot(side, side) <= 1e-8f) {
		side = cross(direction, float3(0.0f, 1.0f, 0.0f));
	}
	if (dot(side, side) <= 1e-8f) {
		side = cross(direction, float3(1.0f, 0.0f, 0.0f));
	}
	return NormalizeTrailVector(side, float3(1.0f, 0.0f, 0.0f));
}

VSOutput BuildTrailVertex(ParticleTrailPointData trailPoint, float sideSign, float uvY, uint materialIndex) {

	VSOutput output;
	const float3 worldPosition = trailPoint.position +
		GetTrailSide(trailPoint) * trailPoint.halfWidth * sideSign;
	output.position = mul(float4(worldPosition, 1.0f), viewProjection);
	output.texcoord = float2(trailPoint.ribbonT, uvY);
	output.vertexColor = trailPoint.color;
	output.particleIndex = materialIndex;
	return output;
}

#endif // NEM_PARTICLE_TRAIL_HLSLI
