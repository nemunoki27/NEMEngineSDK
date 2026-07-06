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
	float metallic = saturate(params.Metallic * mrSample.b);
	float roughness = saturate(params.Roughness * mrSample.g);
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

// 半透明の前方描画で使う、全ライトのPBRライティングを合算する
float3 EvaluateForwardPBRLighting(VSOutput input, ResolvedPBRMaterial m) {

	// ライティングしないサーフェイスはベースカラーと発光をそのまま出す
	uint instanceFlags = gMeshInstances[input.instanceID].flags;
	if ((instanceFlags & MESH_INSTANCE_FLAG_LIGHTING) == 0u) {
		return m.baseColor.rgb + m.emissive;
	}

	float3 V = normalize(renderCameraPos - input.worldPos);
	float3 F0 = lerp(0.04f.xxx, m.baseColor.rgb, m.metallic);

	float3 Lo = 0.0f.xxx;
	[loop]
	for (uint i = 0; i < directionalCount; ++i) {

		Lo += EvaluatePBRDirectionalLight(gDirectionalLights[i], m.N, V,
			m.baseColor.rgb, m.metallic, m.roughness, F0);
	}

	[loop]
	for (uint pi = 0; pi < pointCount; ++pi) {

		Lo += EvaluatePBRPointLight(gPointLights[pi], input.worldPos, m.N, V,
			m.baseColor.rgb, m.metallic, m.roughness, F0);
	}
	[loop]
	for (uint si = 0; si < spotCount; ++si) {

		Lo += EvaluatePBRSpotLight(gSpotLights[si], input.worldPos, m.N, V,
			m.baseColor.rgb, m.metallic, m.roughness, F0);
	}

	// 環境光はAOで減衰、環境光を受けないサーフェイスは加算しない
	float3 ambient = 0.0f.xxx;
	if ((instanceFlags & MESH_INSTANCE_FLAG_RECEIVE_IBL) != 0u) {
		ambient = 0.03f * m.baseColor.rgb * m.ao;
	}

	return Lo + ambient + m.emissive;
}
#endif // NEM_MESH_PBR_HLSLI
