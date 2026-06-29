//============================================================================
//	include
//============================================================================
#include "fillMesh.hlsli"

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
VSOutput main(uint vertexID : SV_VertexID) {

	FillMeshVertex v = gVertices[vertexID];

	VSOutput output;
	// エンティティのワールド行列でSRTを反映する
	float4 worldPos = mul(float4(v.position.xyz, 1.0f), worldMatrix);
	output.position = mul(worldPos, viewProjection);
	output.worldPos = worldPos.xyz;
	output.normal = normalize(mul(v.normal.xyz, (float3x3)worldMatrix));

	return output;
}
