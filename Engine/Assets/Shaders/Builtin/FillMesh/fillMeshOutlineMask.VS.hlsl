//============================================================================
//	include
//============================================================================
#include "fillMeshOutlineMask.hlsli"

//============================================================================
//	resources
//============================================================================
cbuffer ViewConstants : register(b0) {

	float4x4 viewProjection;
};
cbuffer ObjectConstants : register(b1) {

	float4x4 worldMatrix;
	float4 color;
};
StructuredBuffer<FillMeshVertex> gVertices : register(t0);

//============================================================================
//	main
//============================================================================
MaskVSOutput main(uint vertexID : SV_VertexID) {

	FillMeshVertex v = gVertices[vertexID];

	// 通常描画と同じworld transformでマスクを描く
	float4 worldPos = mul(float4(v.position.xyz, 1.0f), worldMatrix);

	MaskVSOutput output;
	output.position = mul(worldPos, viewProjection);
	output.styleID = gMaskConstants.styleID;
	output.localSubMeshIndex = 0;
	return output;
}
