#ifndef NEM_LIGHTING_COMMON_HLSLI
#define NEM_LIGHTING_COMMON_HLSLI

//============================================================================
//	VSOutputに依存しないライティング共通定義、MeshとPrimitiveで共有する
//============================================================================

//============================================================================
//	include
//============================================================================
#include "../../Common/mathConstants.hlsli"

//============================================================================
//	定数
//============================================================================
static const uint kNoTexture = 0xFFFFFFFF;

//============================================================================
//	ライト定義
//============================================================================
#ifndef NEM_LIGHT_COUNTS_REGISTER
#define NEM_LIGHT_COUNTS_REGISTER b2
#endif
#ifndef NEM_DIRECTIONAL_LIGHTS_REGISTER
#define NEM_DIRECTIONAL_LIGHTS_REGISTER t4
#endif
#ifndef NEM_POINT_LIGHTS_REGISTER
#define NEM_POINT_LIGHTS_REGISTER t5
#endif
#ifndef NEM_SPOT_LIGHTS_REGISTER
#define NEM_SPOT_LIGHTS_REGISTER t6
#endif
#ifndef NEM_RECT_LIGHTS_REGISTER
#define NEM_RECT_LIGHTS_REGISTER t7
#endif
#ifndef NEM_LIGHTING_SAMPLER_REGISTER
#define NEM_LIGHTING_SAMPLER_REGISTER s0
#endif

cbuffer LightCounts : register(NEM_LIGHT_COUNTS_REGISTER) {

	uint directionalCount;
	uint pointCount;
	uint spotCount;
	uint rectCount;

	uint localCount;
	uint3 _lightCountPad;
};
struct DirectionalLight {

	float4 color;

	float3 direction;
	float intensity;

	float shadowStrength;
	float shadowAngularRadius;
	float2 _pad1;
};
struct PointLight {

	float4 color;

	float3 pos;
	float intensity;

	float radius;
	float decay;
	float shadowStrength;
	float shadowRadius;
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
	float shadowStrength;

	float shadowRadius;
	float3 _pad0;
};
struct RectLight {

	float4 color;

	float3 direction;
	float intensity;

	float3 pos;
	float attenuationRadius;

	float3 right;
	float sourceWidth;

	float3 up;
	float sourceHeight;

	float decay;
	float barnDoorAngle;
	float barnDoorLength;
	float shadowStrength;
};
StructuredBuffer<DirectionalLight> gDirectionalLights :
	register(NEM_DIRECTIONAL_LIGHTS_REGISTER);
StructuredBuffer<PointLight> gPointLights :
	register(NEM_POINT_LIGHTS_REGISTER);
StructuredBuffer<SpotLight> gSpotLights :
	register(NEM_SPOT_LIGHTS_REGISTER);
StructuredBuffer<RectLight> gRectLights :
	register(NEM_RECT_LIGHTS_REGISTER);

SamplerState gSampler : register(NEM_LIGHTING_SAMPLER_REGISTER);

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

// 矩形面を安定して積分するための固定サンプル
static const uint kRectLightSampleCount = 4u;
static const float2 kRectLightSamples[kRectLightSampleCount] = {
	float2(-0.375f, -0.125f),
	float2(0.125f, -0.375f),
	float2(-0.125f, 0.375f),
	float2(0.375f, 0.125f)
};

float3 GetRectLightSamplePosition(RectLight light, uint sampleIndex) {

	float2 sampleUV = kRectLightSamples[sampleIndex];
	return light.pos +
		light.right * (sampleUV.x * max(light.sourceWidth, 0.0f)) +
		light.up * (sampleUV.y * max(light.sourceHeight, 0.0f));
}

// バーンドアで矩形外側へ広がる光の範囲と境界の鋭さを制御する
float ComputeRectBarnAttenuation(RectLight light, float3 worldPos) {

	float3 fromLight = worldPos - light.pos;
	float forward = dot(fromLight, light.direction);
	if (forward <= 0.0f) {
		return 0.0f;
	}
	if (light.barnDoorLength <= 0.0001f) {
		return 1.0f;
	}

	float spread = tan(radians(clamp(
		light.barnDoorAngle, 0.0f, 89.0f))) * forward;
	float widthLimit = max(light.sourceWidth, 0.0f) * 0.5f + spread;
	float heightLimit = max(light.sourceHeight, 0.0f) * 0.5f + spread;
	float lateralX = abs(dot(fromLight, light.right));
	float lateralY = abs(dot(fromLight, light.up));
	float edgeSoftness = max(
		forward / (1.0f + light.barnDoorLength * 4.0f), 0.001f);

	float widthAttenuation =
		1.0f - smoothstep(widthLimit, widthLimit + edgeSoftness, lateralX);
	float heightAttenuation =
		1.0f - smoothstep(heightLimit, heightLimit + edgeSoftness, lateralY);
	return widthAttenuation * heightAttenuation;
}

#endif // NEM_LIGHTING_COMMON_HLSLI
