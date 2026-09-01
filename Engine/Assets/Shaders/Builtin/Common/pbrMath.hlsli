#ifndef NEM_PBR_MATH_HLSLI
#define NEM_PBR_MATH_HLSLI

//============================================================================
//	include
//============================================================================
#include "mathConstants.hlsli"

//============================================================================
//	PBR functions
//============================================================================
// hlsl魔導書PBR参照
float EvalD(float NdotH, float roughness) {

	float a = roughness * roughness;
	float a2 = a * a;
	float denom = NdotH * NdotH * (a2 - 1.0f) + 1.0f;
	return a2 / max(PI * denom * denom, 1e-7f);
}

float EvalG1(float NdotX, float roughness) {

	float r = roughness + 1.0f;
	float k = (r * r) / 8.0f;
	return NdotX / max(NdotX * (1.0f - k) + k, 1e-7f);
}

float EvalG(float NdotV, float NdotL, float roughness) {

	return EvalG1(NdotV, roughness) * EvalG1(NdotL, roughness);
}

float3 FresnelSchlick(float cosTheta, float3 F0) {

	return F0 + (1.0f - F0) * pow(saturate(1.0f - cosTheta), 5.0f);
}

float3 DisneyDiffuse(float NdotL, float NdotV, float LdotH, float roughness, float3 albedo) {

	float energyBias = lerp(0.0f, 0.5f, roughness);
	float energyFactor = lerp(1.0f, 1.0f / 1.51f, roughness);
	float Fd90 = energyBias + 2.0f * LdotH * LdotH * roughness;
	float FL = 1.0f + (Fd90 - 1.0f) * pow(1.0f - NdotL, 5.0f);
	float FV = 1.0f + (Fd90 - 1.0f) * pow(1.0f - NdotV, 5.0f);
	return albedo * FL * FV * energyFactor / PI;
}

#endif // NEM_PBR_MATH_HLSLI
