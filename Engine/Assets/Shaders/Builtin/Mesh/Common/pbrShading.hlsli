#ifndef NEM_PBR_SHADING_HLSLI
#define NEM_PBR_SHADING_HLSLI

//============================================================================
//	include
//============================================================================
#include "lightingCommon.hlsli"
#include "../../Common/pbrMath.hlsli"

//============================================================================
//	バッファ非依存のPBR共通、MeshとPrimitiveで共有する
//============================================================================

//============================================================================
//	マテリアル解決結果
//============================================================================
struct ResolvedPBRMaterial {

	float4 baseColor;
	float3 N;
	float metallic;
	float roughness;
	float ao;
	float3 emissive;
};

//============================================================================
//	ライト評価
//============================================================================
float3 EvaluatePBRRadiance(float3 N, float3 V, float3 L,
	float3 radiance, float3 albedo, float metallic,
	float roughness, float3 F0) {

	float NdotL = saturate(dot(N, L));
	if (NdotL <= 0.0f) {
		return 0.0f.xxx;
	}

	float NdotV = saturate(dot(N, V));
	float3 H = normalize(V + L);
	float NdotH = saturate(dot(N, H));
	float HdotV = saturate(dot(H, V));
	float LdotH = saturate(dot(L, H));

	float3 F = FresnelSchlick(HdotV, F0);
	float D = EvalD(NdotH, roughness);
	float G = EvalG(NdotV, NdotL, roughness);

	float3 specular =
		D * G * F / max(4.0f * NdotV * NdotL, 1e-4f);
	float3 kD = (1.0f - F) * (1.0f - metallic);
	float3 diffuse =
		kD * DisneyDiffuse(NdotL, NdotV, LdotH, roughness, albedo);

	return (diffuse + specular) * NdotL * radiance;
}

// PBR平行光源
float3 EvaluatePBRDirectionalLight(DirectionalLight light, float3 N, float3 V,
	float3 albedo, float metallic, float roughness, float3 F0) {

	float3 L = normalize(-light.direction);
	float NdotL = saturate(dot(N, L));
	if (NdotL <= 0.0f) {
		return 0.0f.xxx;
	}

	float NdotV = saturate(dot(N, V));
	float3 H = normalize(V + L);
	float NdotH = saturate(dot(N, H));
	float HdotV = saturate(dot(H, V));
	float LdotH = saturate(dot(L, H));

	float3 F = FresnelSchlick(HdotV, F0);
	float D = EvalD(NdotH, roughness);
	float G = EvalG(NdotV, NdotL, roughness);

	float3 specular = D * G * F / max(4.0f * NdotV * NdotL, 1e-4f);
	float3 kD = (1.0f - F) * (1.0f - metallic);
	float3 diffuse = kD * DisneyDiffuse(NdotL, NdotV, LdotH, roughness, albedo);

	return (diffuse + specular) * NdotL * light.color.rgb * light.intensity;
}

// PBR点光源
float3 EvaluatePBRPointLight(PointLight light, float3 worldPos, float3 N, float3 V,
	float3 albedo, float metallic, float roughness, float3 F0) {

	float3 toLight = light.pos - worldPos;
	float dist = length(toLight);
	if (dist <= 1e-5f) {
		return 0.0f.xxx;
	}

	float3 L = toLight / dist;
	float NdotL = saturate(dot(N, L));
	if (NdotL <= 0.0f) {
		return 0.0f.xxx;
	}

	float attenuation = ComputeDistanceAttenuation(dist, light.radius, light.decay);
	if (attenuation <= 0.0f) {
		return 0.0f.xxx;
	}

	float NdotV = saturate(dot(N, V));
	float3 H = normalize(V + L);
	float NdotH = saturate(dot(N, H));
	float HdotV = saturate(dot(H, V));
	float LdotH = saturate(dot(L, H));

	float3 F = FresnelSchlick(HdotV, F0);
	float D = EvalD(NdotH, roughness);
	float G = EvalG(NdotV, NdotL, roughness);

	float3 specular = D * G * F / max(4.0f * NdotV * NdotL, 1e-4f);
	float3 kD = (1.0f - F) * (1.0f - metallic);
	float3 diffuse = kD * DisneyDiffuse(NdotL, NdotV, LdotH, roughness, albedo);

	return (diffuse + specular) * NdotL * light.color.rgb * light.intensity * attenuation;
}

// PBRスポットライト
float3 EvaluatePBRSpotLight(SpotLight light, float3 worldPos, float3 N, float3 V,
	float3 albedo, float metallic, float roughness, float3 F0) {

	float3 toLight = light.pos - worldPos;
	float dist = length(toLight);
	if (dist <= 1e-5f) {
		return 0.0f.xxx;
	}

	float3 L = toLight / dist;
	float NdotL = saturate(dot(N, L));
	if (NdotL <= 0.0f) {
		return 0.0f.xxx;
	}

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

	float NdotV = saturate(dot(N, V));
	float3 H = normalize(V + L);
	float NdotH = saturate(dot(N, H));
	float HdotV = saturate(dot(H, V));
	float LdotH = saturate(dot(L, H));

	float3 F = FresnelSchlick(HdotV, F0);
	float D = EvalD(NdotH, roughness);
	float G = EvalG(NdotV, NdotL, roughness);

	float3 specular = D * G * F / max(4.0f * NdotV * NdotL, 1e-4f);
	float3 kD = (1.0f - F) * (1.0f - metallic);
	float3 diffuse = kD * DisneyDiffuse(NdotL, NdotV, LdotH, roughness, albedo);

	return (diffuse + specular) * NdotL * light.color.rgb * light.intensity * distanceAttenuation * coneAttenuation;
}

// PBR矩形面光源
float3 EvaluatePBRRectLight(RectLight light, float3 worldPos, float3 N, float3 V,
	float3 albedo, float metallic, float roughness, float3 F0) {

	float centerDistance = length(light.pos - worldPos);
	float attenuation = ComputeDistanceAttenuation(
		centerDistance, light.attenuationRadius, light.decay);
	float barnAttenuation =
		ComputeRectBarnAttenuation(light, worldPos);
	if (attenuation <= 0.0f || barnAttenuation <= 0.0f) {
		return 0.0f.xxx;
	}

	float3 result = 0.0f.xxx;
	[unroll]
	for (uint sampleIndex = 0u;
		sampleIndex < kRectLightSampleCount; ++sampleIndex) {

		float3 samplePos =
			GetRectLightSamplePosition(light, sampleIndex);
		float3 toLight = samplePos - worldPos;
		float sampleDistance = length(toLight);
		if (sampleDistance <= 1e-5f) {
			continue;
		}

		float3 L = toLight / sampleDistance;
		float sourceFacing =
			saturate(dot(-L, light.direction));
		float3 radiance = light.color.rgb * light.intensity *
			attenuation * barnAttenuation * sourceFacing;
		result += EvaluatePBRRadiance(
			N, V, L, radiance, albedo, metallic, roughness, F0);
	}
	return result / float(kRectLightSampleCount);
}

#endif // NEM_PBR_SHADING_HLSLI
