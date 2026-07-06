#ifndef NEM_LIGHTING_COMMON_HLSLI
#define NEM_LIGHTING_COMMON_HLSLI

//============================================================================
//	VSOutputに依存しないライティング共通定義、MeshとPrimitiveで共有する
//============================================================================

//============================================================================
//	定数
//============================================================================
static const float PI = 3.14159265f;
static const uint kNoTexture = 0xFFFFFFFF;

//============================================================================
//	ライト定義
//============================================================================
cbuffer LightCounts : register(b2) {

	uint directionalCount;
	uint pointCount;
	uint spotCount;
	uint localCount;
};
struct DirectionalLight {

	float4 color;

	float3 direction;
	float intensity;

	float shadowStrength;
	float3 _pad1;
};
struct PointLight {

	float4 color;

	float3 pos;
	float intensity;

	float radius;
	float decay;
	float2 _pad0;
};
struct SpotLight {

	float4 color;

	float3 direction;
	float intensity;

	float3 pos;
	float distance;

	float decay;
	float cosAngle;
	float cosFalloffStart;
	float _pad0;
};
StructuredBuffer<DirectionalLight> gDirectionalLights : register(t4);
StructuredBuffer<PointLight> gPointLights : register(t5);
StructuredBuffer<SpotLight> gSpotLights : register(t6);

SamplerState gSampler : register(s0);

//============================================================================
//	距離減衰
//============================================================================
float ComputeDistanceAttenuation(float dist, float range, float decay) {

	if (range <= 0.0001f || dist >= range) {
		return 0.0f;
	}

	float x = saturate(dist / range);
	float smooth = 1.0f - x * x;
	smooth *= smooth;

	float d = max(decay, 0.0f);
	float distanceFalloff = 1.0f / max(pow(max(dist, 1.0f), d), 1.0f);

	return smooth * distanceFalloff;
}

#endif // NEM_LIGHTING_COMMON_HLSLI
