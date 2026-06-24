#ifndef NEM_MESH_LIGHTING_HLSLI
#define NEM_MESH_LIGHTING_HLSLI

//============================================================================
//	Mesh描画のライティング共通定義
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

//============================================================================
//	ワールド法線の計算、法線マップを考慮する
//============================================================================
float3 ComputeWorldNormal(VSOutput input, uint normalTextureIndex, float2 uv) {

	float3 N = normalize(input.normal);
	if (normalTextureIndex == kNoTexture) {
		return N;
	}

	// TBN構築は共通helperへ集約している、tangentSignとorientationSign補正込み
	float3x3 TBN = BuildMeshTBN(input);

	Texture2D<float4> normalTex = ResourceDescriptorHeap[NonUniformResourceIndex(normalTextureIndex)];
	float3 tangentNormal = normalTex.Sample(gSampler, uv).xyz * 2.0f - 1.0f;

	return normalize(mul(tangentNormal, TBN));
}

#endif // NEM_MESH_LIGHTING_HLSLI
