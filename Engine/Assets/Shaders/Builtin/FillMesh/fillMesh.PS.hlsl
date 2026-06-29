//============================================================================
//	include
//============================================================================
#include "fillMesh.hlsli"
#include "../Mesh/Common/deferredGBuffer.hlsli"

//============================================================================
//	resources
//============================================================================
cbuffer ObjectConstants : register(b1) {

	float4x4 worldMatrix;
	float4 color;
};

//============================================================================
//	lighting
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

//============================================================================
//	output
//============================================================================
struct TransparentPSOutput {

	float4 color : SV_TARGET0;
};

//============================================================================
//	functions
//============================================================================
float HalfLambert(float3 N, float3 L) {

	float ndl = dot(N, L);
	float h = saturate(ndl * 0.5f + 0.5f);
	return h * h;
}

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

float3 EvaluateDirectional(DirectionalLight light, float3 N) {

	float3 L = normalize(-light.direction);
	return HalfLambert(N, L) * light.color.rgb * light.intensity;
}

float3 EvaluatePoint(PointLight light, float3 worldPos, float3 N) {

	float3 toLight = light.pos - worldPos;
	float dist = length(toLight);
	if (dist <= 1e-5f) {
		return 0.0f.xxx;
	}

	float3 L = toLight / dist;
	float attenuation = ComputeDistanceAttenuation(dist, light.radius, light.decay);
	if (attenuation <= 0.0f) {
		return 0.0f.xxx;
	}
	return HalfLambert(N, L) * light.color.rgb * light.intensity * attenuation;
}

float3 EvaluateSpot(SpotLight light, float3 worldPos, float3 N) {

	float3 toLight = light.pos - worldPos;
	float dist = length(toLight);
	if (dist <= 1e-5f) {
		return 0.0f.xxx;
	}

	float3 L = toLight / dist;
	float distanceAttenuation = ComputeDistanceAttenuation(dist, light.distance, light.decay);
	if (distanceAttenuation <= 0.0f) {
		return 0.0f.xxx;
	}

	float3 lightDir = normalize(light.direction);
	float cosTheta = dot(-L, lightDir);
	float coneRange = max(light.cosFalloffStart - light.cosAngle, 1e-4f);
	float coneAttenuation = saturate((cosTheta - light.cosAngle) / coneRange);
	coneAttenuation *= coneAttenuation;
	if (coneAttenuation <= 0.0f) {
		return 0.0f.xxx;
	}
	return HalfLambert(N, L) * light.color.rgb * light.intensity * distanceAttenuation * coneAttenuation;
}

TransparentPSOutput ResolveTransparent(VSOutput input) {

	float3 N = normalize(input.normal);
	float3 lit = 0.0f.xxx;

	[loop]
	for (uint i = 0; i < directionalCount; ++i) {
		lit += EvaluateDirectional(gDirectionalLights[i], N);
	}
	[loop]
	for (uint pi = 0; pi < pointCount; ++pi) {
		lit += EvaluatePoint(gPointLights[pi], input.worldPos, N);
	}
	[loop]
	for (uint si = 0; si < spotCount; ++si) {
		lit += EvaluateSpot(gSpotLights[si], input.worldPos, N);
	}

	float3 ambient = 0.03f * color.rgb;
	float3 finalColor = color.rgb * lit + ambient;

	TransparentPSOutput output;
	output.color = float4(finalColor, color.a);
	return output;
}

//============================================================================
//	main
//============================================================================
GBufferOutput main(VSOutput input) {

	// 色のみのアルベドでGBufferへ書く、法線は面の向き
	MeshSurface surface;
	surface.albedo = color.rgb;
	surface.normal = normalize(input.normal);
	surface.worldPos = input.worldPos;
	surface.metallic = 0.0f;
	surface.roughness = 1.0f;
	surface.occlusion = 1.0f;
	surface.emissive = float3(0.0f, 0.0f, 0.0f);

	GBufferOutput output = EncodeGBuffer(surface);
	// Transparentフェーズのブレンドにα値を反映する、Opaqueのディファード照明はalbedo.rgbのみ使う
	output.albedo.a = color.a;
	return output;
}

//============================================================================
//	mainTransparent
//============================================================================
TransparentPSOutput mainTransparent(VSOutput input) {

	return ResolveTransparent(input);
}
