//============================================================================
//	include
//============================================================================
#include "../FullscreenCopy/FullscreenCopy.hlsli"
#include "../Mesh/Common/deferredGBuffer.hlsli"

//============================================================================
//	定数
//============================================================================
static const float PI = 3.14159265f;

//============================================================================
//	GBuffer入力
//============================================================================
Texture2D<float4> gAlbedo : register(t0);
Texture2D<float4> gNormal : register(t1);
Texture2D<float4> gWorldPos : register(t2);
Texture2D<float4> gMaterial : register(t3);
Texture2D<float4> gEmissive : register(t4);
Texture2D<uint> gFlags : register(t5);

SamplerState gSampler : register(s0);

//============================================================================
//	ライト
//============================================================================
// 平行光源
struct DirectionalLight {

	float4 color;

	float3 direction;
	float intensity;

	float shadowStrength;
	float3 _pad1;
};
// 点光源
struct PointLight {

	float4 color;

	float3 pos;
	float intensity;

	float radius;
	float decay;
	float2 _pad0;
};
// スポットライト
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
// ライト数
cbuffer LightCounts : register(b0) {

	uint directionalCount;
	uint pointCount;
	uint spotCount;
	uint localCount;
};
StructuredBuffer<DirectionalLight> gDirectionalLights : register(t6);
StructuredBuffer<PointLight> gPointLights : register(t7);
StructuredBuffer<SpotLight> gSpotLights : register(t8);

//============================================================================
//	ライティングパス定数
//============================================================================

cbuffer DeferredLightingConstants : register(b1) {

	float3 cameraPos;
	float ambientIntensity;

	float4x4 inverseViewProjection;

	float4 skyboxColor;

	uint skyboxCubemapIndex;
	uint hasSkybox;
	uint2 viewportSize;

	float shadowNormalBias;
	float shadowMaxDistance;
	float2 _shadowPad;
};

// 無効キューブマップインデックス
static const uint kNoCubemap = 0xFFFFFFFF;

//============================================================================
//	平行光源影
//============================================================================

RaytracingAccelerationStructure gSceneTLAS : register(t10);

// 平行光源方向へシャドウレイを飛ばして遮蔽判定
bool TraceDirectionalShadow(float3 worldPos, float3 worldNormal, float3 lightDirection) {

	RayDesc rayDesc;
	rayDesc.Origin = worldPos + worldNormal * shadowNormalBias;
	rayDesc.Direction = normalize(-lightDirection);
	rayDesc.TMin = 0.001f;
	rayDesc.TMax = shadowMaxDistance;

	RayQuery < 0 > rayQuery;

	rayQuery.TraceRayInline(gSceneTLAS, 0, 0xFF, rayDesc);
	while (rayQuery.Proceed()) {
	}
	return rayQuery.CommittedStatus() == COMMITTED_TRIANGLE_HIT;
}

//============================================================================
//	PBR関数
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
float3 EvaluatePBRLight(float3 N, float3 V, float3 L, float3 radiance,
	float3 albedo, float metallic, float roughness, float3 F0) {

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

	return (diffuse + specular) * NdotL * radiance;
}

//============================================================================
//	背景、スカイボックス
//============================================================================

float3 SampleBackground(float2 texcoord) {

	// スカイボックスが無効なら処理しない、色をそのまま返す
	if (hasSkybox == 0u || skyboxCubemapIndex == kNoCubemap) {
		return skyboxColor.rgb;
	}

	// 入力テクスチャ座標からNDCを作ってinverseViewProjectionでワールド方向を復元
	float2 ndc = float2(texcoord.x * 2.0f - 1.0f, 1.0f - texcoord.y * 2.0f);
	float4 worldFar = mul(float4(ndc, 1.0f, 1.0f), inverseViewProjection);
	float3 direction = normalize(worldFar.xyz / worldFar.w - cameraPos);

	// キューブマップテクスチャ取得
	TextureCube<float4> cubemap = ResourceDescriptorHeap[NonUniformResourceIndex(skyboxCubemapIndex)];
	return cubemap.SampleLevel(gSampler, direction, 0.0f).rgb * skyboxColor.rgb;
}

//============================================================================
//	全ピクセルのマテリアル計算
//============================================================================
float4 ResolvePixel(VSOutput input, bool useShadow) {

	int3 pixel = int3(input.position.xy, 0);

	// サーフェスが無いピクセルは背景
	uint flags = gFlags.Load(pixel);
	if ((flags & kMaterialFlagSurface) == 0u) {
		return float4(SampleBackground(input.texcoord), 1.0f);
	}
	// GBufferデータ取得
	float3 albedo = gAlbedo.Load(pixel).rgb;
	float3 N = normalize(gNormal.Load(pixel).xyz * 2.0f - 1.0f);
	float3 worldPos = gWorldPos.Load(pixel).xyz;
	float4 material = gMaterial.Load(pixel);
	float metallic = material.r;
	float roughness = max(material.g, 0.04f);
	float ao = material.b;
	float3 emissive = gEmissive.Load(pixel).rgb;

	float3 V = normalize(cameraPos - worldPos);
	float3 F0 = lerp(0.04f.xxx, albedo, metallic);

	float3 Lo = 0.0f.xxx;

	// 平行光源
	[loop]
	for (uint di = 0; di < directionalCount; ++di) {

		DirectionalLight light = gDirectionalLights[di];
		float3 L = normalize(-light.direction);
		// 影計算を行うか、行わない場合は1.0fでそのまま返す
		float shadow = 1.0f;
		if (useShadow) {
			
			shadow = TraceDirectionalShadow(worldPos, N, light.direction) ? (1.0f - light.shadowStrength) : 1.0f;
		}
		float3 radiance = light.color.rgb * light.intensity * shadow;
		Lo += EvaluatePBRLight(N, V, L, radiance, albedo, metallic, roughness, F0);
	}
	// 点光源
	[loop]
	for (uint pi = 0; pi < pointCount; ++pi) {

		PointLight light = gPointLights[pi];
		float3 toLight = light.pos - worldPos;
		float dist = length(toLight);
		if (dist <= 1e-5f) {
			continue;
		}
		float attenuation = ComputeDistanceAttenuation(dist, light.radius, light.decay);
		if (attenuation <= 0.0f) {
			continue;
		}
		float3 L = toLight / dist;
		float3 radiance = light.color.rgb * light.intensity * attenuation;
		Lo += EvaluatePBRLight(N, V, L, radiance, albedo, metallic, roughness, F0);
	}
	// スポットライト
	[loop]
	for (uint si = 0; si < spotCount; ++si) {

		SpotLight light = gSpotLights[si];
		float3 toLight = light.pos - worldPos;
		float dist = length(toLight);
		if (dist <= 1e-5f) {
			continue;
		}
		float distanceAttenuation = ComputeDistanceAttenuation(dist, light.distance, light.decay);
		if (distanceAttenuation <= 0.0f) {
			continue;
		}
		float3 L = toLight / dist;
		float3 lightDir = normalize(light.direction);
		float cosTheta = dot(-L, lightDir);
		float coneRange = max(light.cosFalloffStart - light.cosAngle, 1e-4f);
		float coneAttenuation = saturate((cosTheta - light.cosAngle) / coneRange);
		coneAttenuation *= coneAttenuation;
		if (coneAttenuation <= 0.0f) {
			continue;
		}
		float3 radiance = light.color.rgb * light.intensity * distanceAttenuation * coneAttenuation;
		Lo += EvaluatePBRLight(N, V, L, radiance, albedo, metallic, roughness, F0);
	}

	// 環境光はAOで減衰、発光はそのまま加算する
	float3 ambient = ambientIntensity * albedo * ao;
	float3 color = Lo + ambient + emissive;

	return float4(color, 1.0f);
}

//============================================================================
//	main、影無し
//============================================================================
float4 main(VSOutput input) : SV_TARGET0 {

	return ResolvePixel(input, false);
}
//============================================================================
//	mainShadowed、影あり
//============================================================================
float4 mainShadowed(VSOutput input) : SV_TARGET0 {

	return ResolvePixel(input, true);
}