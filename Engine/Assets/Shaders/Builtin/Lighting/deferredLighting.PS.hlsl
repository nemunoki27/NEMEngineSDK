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
//	SceneMainのcolorアタッチメント並びと一致させる、worldPosはGBufferから直接読む
//============================================================================
Texture2D<float4> gAlbedo   : register(t0);
Texture2D<float4> gNormal   : register(t1);
Texture2D<float4> gWorldPos : register(t2);
Texture2D<float4> gMaterial : register(t3);
Texture2D<float4> gEmissive : register(t4);
Texture2D<uint>   gFlags    : register(t5);

//============================================================================
//	ライト
//	構造体レイアウトはGPUアップロード側と一致させる、meshLighting.hlsliと同一定義
//============================================================================
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
//	背景skyboxの復元と環境光に使う
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

SamplerState gSampler : register(s0);

static const uint kNoCubemap = 0xFFFFFFFF;

//============================================================================
//	InlineRayQueryによる平行光源シャドウ
//	LightingPassがTLASとinlineRTを使えるときだけmainShadowedを選び、ここを通る
//============================================================================
RaytracingAccelerationStructure gSceneTLAS : register(t10);

// サーフェスから平行光源方向へシャドウレイを飛ばし、遮蔽されていればtrueを返す
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
//	meshPBR.PSと同じBRDF、Deferred側で共有せず独立に持つ
//============================================================================
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

// 1ライト分のCook-Torranceを評価する、方向Lと放射輝度radianceは呼び出し側で用意する
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
//	背景
//	ジオメトリが無い画素はskyboxを引く、未設定なら指定色を返す
//============================================================================
float3 SampleBackground(float2 texcoord) {

	if (hasSkybox == 0u || skyboxCubemapIndex == kNoCubemap) {
		return skyboxColor.rgb;
	}

	// texcoordからNDCを作りinverseViewProjectionでワールド方向を復元する
	float2 ndc = float2(texcoord.x * 2.0f - 1.0f, 1.0f - texcoord.y * 2.0f);
	float4 worldFar = mul(float4(ndc, 1.0f, 1.0f), inverseViewProjection);
	float3 dir = normalize(worldFar.xyz / worldFar.w - cameraPos);

	TextureCube<float4> cubemap = ResourceDescriptorHeap[NonUniformResourceIndex(skyboxCubemapIndex)];
	return cubemap.SampleLevel(gSampler, dir, 0.0f).rgb * skyboxColor.rgb;
}

//============================================================================
//	ResolvePixel
//	GBufferを読み全ライトをPBRで合算する、useShadowで平行光源のシャドウ有無を切り替える
//============================================================================
float4 ResolvePixel(VSOutput input, bool useShadow) {

	int3 pixel = int3(input.position.xy, 0);

	// サーフェスが無い画素は背景として描く
	uint flags = gFlags.Load(pixel);
	if ((flags & kMaterialFlagSurface) == 0u) {
		return float4(SampleBackground(input.texcoord), 1.0f);
	}

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

	// 平行光源、useShadow時はTLASへシャドウレイを飛ばして遮蔽を反映する
	[loop]
	for (uint di = 0; di < directionalCount; ++di) {

		DirectionalLight light = gDirectionalLights[di];
		float3 L = normalize(-light.direction);
		float shadow = 1.0f;
		if (useShadow) {
			shadow = TraceDirectionalShadow(worldPos, N, light.direction) ?
				(1.0f - light.shadowStrength) : 1.0f;
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
//	main / mainShadowed
//	mainはシャドウ無し、mainShadowedはTLASによる平行光源シャドウ付き
//	LightingPassがTLASとinlineRTの可否で2つのPSOを使い分ける
//============================================================================
float4 main(VSOutput input) : SV_TARGET0 {

	return ResolvePixel(input, false);
}

float4 mainShadowed(VSOutput input) : SV_TARGET0 {

	return ResolvePixel(input, true);
}
