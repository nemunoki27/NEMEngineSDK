//============================================================================
//	include
//============================================================================
#include "particle.hlsli"

//============================================================================
//	resources
//============================================================================
struct TrailVertex {

	float3 position;
	float pad0;
	float2 uv;
	float2 pad1;
	float4 color;
};
StructuredBuffer<TrailVertex> gTrailVertices : register(t0);

//============================================================================
//	main
//============================================================================
VSOutput main(uint vertexID : SV_VertexID) {

	TrailVertex v = gTrailVertices[vertexID];

	VSOutput output;
	// 頂点はワールド空間で構築済みなのでそのまま投影する
	output.position = mul(float4(v.position, 1.0f), viewProjection);
	output.texcoord = v.uv;
	output.vertexColor = v.color;
	output.particleIndex = 0xffffffffu;

	return output;
}
