//============================================================================
//	include
//============================================================================
// MeshVertex / MeshPackedVertex は共通ヘッダから取る(重複宣言しない)
#include "../Common/meshShaderSharedTypes.hlsli"

//============================================================================
//	resources
//============================================================================
cbuffer SkinningConstants : register(b0) {

	uint vertexCount;
	uint boneCount;
	uint skinnedInstanceCount;
	uint _pad0;
}
struct VertexInfluence {

	float4 weights;
	int4 jointIndices;
};
struct WellForGPU {

	float4x4 skeletonSpaceMatrix;
	float4x4 skeletonSpaceInverseTransposeMatrix;
};
StructuredBuffer<MeshVertex> gInputVertices : register(t0);
StructuredBuffer<VertexInfluence> gVertexInfluences : register(t1);
StructuredBuffer<WellForGPU> gSkinningPalette : register(t2);
RWStructuredBuffer<MeshVertex> gSkinnedVertices : register(u0);
RWStructuredBuffer<MeshPackedVertex> gSkinnedPackedVertices : register(u1);

//============================================================================
//	functions
//============================================================================
float4 SkinPosition(float4 position, VertexInfluence influence, uint paletteOffset) {

	float4 outPos = 0.0f.xxxx;
	float totalWeight = 0.0f;
	[unroll]
	for (uint i = 0; i < 4; ++i) {

		float w = influence.weights[i];
		int jointIndex = influence.jointIndices[i];
		if (w <= 0.0f || jointIndex < 0) {
			continue;
		}
		outPos += mul(position, gSkinningPalette[paletteOffset + (uint) jointIndex].skeletonSpaceMatrix) * w;
		totalWeight += w;
	}

	// ウェイトが無い頂点はそのまま返す
	if (totalWeight <= 0.0f) {
		return position;
	}
	outPos /= totalWeight;
	outPos.w = 1.0f;
	return outPos;
}

float3 SkinNormal(float3 normal, VertexInfluence influence, uint paletteOffset) {

	float3 outNormal = 0.0f.xxx;
	float totalWeight = 0.0f;
	[unroll]
	for (uint i = 0; i < 4; ++i) {

		float w = influence.weights[i];
		int jointIndex = influence.jointIndices[i];
		if (w <= 0.0f || jointIndex < 0) {
			continue;
		}
		outNormal += mul(normal, (float3x3) gSkinningPalette[paletteOffset + (uint) jointIndex].skeletonSpaceInverseTransposeMatrix) * w;
		totalWeight += w;
	}

	// ウェイト無しなら元法線
	if (totalWeight <= 0.0f) {
		return normalize(normal);
	}
	return normalize(outNormal / totalWeight);
}

uint QuantizeSnorm16(float value) {

	value = clamp(value, -1.0f, 1.0f);
	int q = (int)round(value * 32767.0f);
	return (uint)(q & 0xFFFF);
}

uint EncodeOctNormal(float3 normal) {

	float3 n = normalize(normal);
	float len = abs(n.x) + abs(n.y) + abs(n.z);
	if (len <= 0.00001f) {
		return 0u;
	}

	float2 f = n.xy / len;
	if (n.z < 0.0f) {

		float2 old = f;
		f.x = (1.0f - abs(old.y)) * (old.x >= 0.0f ? 1.0f : -1.0f);
		f.y = (1.0f - abs(old.x)) * (old.y >= 0.0f ? 1.0f : -1.0f);
	}
	return QuantizeSnorm16(f.x) | (QuantizeSnorm16(f.y) << 16);
}

//============================================================================
//	main
//============================================================================
[numthreads(256, 1, 1)]
void main(uint3 dispatchThreadID : SV_DispatchThreadID, uint3 groupID : SV_GroupID) {

	uint vertexIndex = dispatchThreadID.x;
	uint skinnedInstanceIndex = groupID.y;

	// 範囲外アクセスを防止
	if (vertexCount <= vertexIndex || skinnedInstanceCount <= skinnedInstanceIndex) {
		return;
	}

	// 頂点とスキニング情報を読み込む
	MeshVertex input = gInputVertices[vertexIndex];
	VertexInfluence influence = gVertexInfluences[vertexIndex];
	
	// スキニングパレットのオフセットを計算
	uint paletteOffset = skinnedInstanceIndex * boneCount;

	MeshVertex output = input;

	// 頂点のスキニング処理
	output.position = SkinPosition(input.position, influence, paletteOffset);
	output.normal = SkinNormal(input.normal, influence, paletteOffset);
	output.tangent = SkinNormal(input.tangent, influence, paletteOffset);
	// 接線の利き手はスキニングで変化しないため、入力からそのまま引き継ぐ
	output.tangentSign = input.tangentSign;

	// スキニング後の頂点を出力
	uint outputIndex = skinnedInstanceIndex * vertexCount + vertexIndex;
	gSkinnedVertices[outputIndex] = output;

	MeshPackedVertex packed;
	packed.normalOct = EncodeOctNormal(output.normal);
	packed.tangentOct = EncodeOctNormal(output.tangent);
	packed.tangentSign = output.tangentSign;
	packed.uv = output.uv;
	packed.position = output.position;
	gSkinnedPackedVertices[outputIndex] = packed;
}
