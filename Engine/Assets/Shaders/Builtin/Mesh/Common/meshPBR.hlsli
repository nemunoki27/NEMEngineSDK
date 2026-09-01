#ifndef NEM_MESH_PBR_HLSLI
#define NEM_MESH_PBR_HLSLI

//============================================================================
//	include
//============================================================================
#include "pbrShading.hlsli"

//============================================================================
//	MeshのPBR共通定義、サブメッシュバッファ依存部分
//============================================================================

//============================================================================
//	テクスチャサンプル
//============================================================================
float4 SamplePBRTexture(uint textureIndex, float2 uv, float4 fallbackValue) {

	if (textureIndex == kNoTexture) {
		return fallbackValue;
	}
	Texture2D<float4> texture = ResourceDescriptorHeap[NonUniformResourceIndex(textureIndex)];
	return texture.Sample(gSampler, uv);
}

//============================================================================
//	マテリアル解決
//============================================================================
ResolvedPBRMaterial ResolvePBRMaterial(VSOutput input) {

	SubMeshShaderData subMesh = GetInstanceSubMesh(input.instanceID, input.subMeshIndex);
	MeshMaterialParameters params = GetInstanceMeshMaterialParameters(input.instanceID, input.subMeshIndex);

	// UV変換
	float2 uv = mul(float4(input.uv, 0.0f, 1.0f), subMesh.uvMatrix).xy;

	// ベースカラー = マテリアル色 × ベースカラーテクスチャ
	float4 baseColor = SamplePBRTexture(params.baseColorTexture, uv, 1.0f.xxxx);
	baseColor *= params.color;

	// メタリックとラフネスは係数にmetallicRoughnessテクスチャを掛ける、glTF流でB=metallic G=roughness
	float4 mrSample = SamplePBRTexture(params.metallicRoughnessTexture, uv, 1.0f.xxxx);
	float metallicSample = SamplePBRTexture(params.metallicTexture, uv, 1.0f.xxxx).r;
	float roughnessSample = SamplePBRTexture(params.roughnessTexture, uv, 1.0f.xxxx).r;
	float metallic = saturate(params.metallic * mrSample.b * metallicSample);
	float roughness = saturate(params.roughness * mrSample.g * roughnessSample);
	roughness = max(roughness, 0.04f);

	// AOはocclusionテクスチャから取る、未指定なら白で1になる
	float ao = SamplePBRTexture(params.occlusionTexture, uv, 1.0f.xxxx).r;

	// ワールド法線
	float3 N = ComputeWorldNormal(input, params.normalTexture, uv);

	// 発光、色×強度にテクスチャを掛ける、強度0で発光オフ
	float3 emissive = params.emissiveColor.rgb * params.emissiveIntensity;
	emissive *= SamplePBRTexture(params.emissiveTexture, uv, 1.0f.xxxx).rgb;

	ResolvedPBRMaterial m;
	m.baseColor = baseColor;
	m.N = N;
	m.metallic = metallic;
	m.roughness = roughness;
	m.ao = ao;
	m.emissive = emissive;
	return m;
}

float ResolveMeshPBRAlphaClip(VSOutput input) {

	return GetInstanceMeshMaterialParameters(
		input.instanceID, input.subMeshIndex).alphaClip;
}

#endif // NEM_MESH_PBR_HLSLI
