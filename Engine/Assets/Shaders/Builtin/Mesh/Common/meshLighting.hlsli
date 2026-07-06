#ifndef NEM_MESH_LIGHTING_HLSLI
#define NEM_MESH_LIGHTING_HLSLI

//============================================================================
//	include
//============================================================================
#include "lightingCommon.hlsli"

//============================================================================
//	Mesh描画のライティング共通定義、VSOutput依存部分
//============================================================================

//============================================================================
//	ワールド法線の計算
//============================================================================
float3 ComputeWorldNormal(VSOutput input, uint normalTextureIndex, float2 uv) {

	float3 N = normalize(input.normal);
	if (normalTextureIndex == kNoTexture) {
		return N;
	}

	// TBN構築
	float3x3 TBN = BuildMeshTBN(input);
	Texture2D<float4> normalTex = ResourceDescriptorHeap[NonUniformResourceIndex(normalTextureIndex)];
	float3 tangentNormal = normalTex.Sample(gSampler, uv).xyz * 2.0f - 1.0f;

	return normalize(mul(tangentNormal, TBN));
}

#endif // NEM_MESH_LIGHTING_HLSLI
