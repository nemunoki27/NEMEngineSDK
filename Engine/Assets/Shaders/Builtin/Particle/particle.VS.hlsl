//============================================================================
//	include
//============================================================================
#include "particle.hlsli"
#include "../Mesh/Common/meshShaderSharedTypes.hlsli"

//============================================================================
//	resources
//============================================================================
StructuredBuffer<MeshVertex> gVertices : register(t0);

//============================================================================
//	main
//============================================================================
VSOutput main(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID) {

	MeshVertex v = gVertices[vertexID];
	ParticleGeometryData instance = gParticleGeometry[instanceID];

	VSOutput output;
	// 粒子ごとのワールド行列でSRTを反映する
	float4 worldPos = mul(float4(v.position.xyz, 1.0f), instance.worldMatrix);
	output.position = mul(worldPos, viewProjection);
	output.texcoord = v.uv;
	output.vertexColor = instance.vertexColor;
	output.particleIndex = instanceID;

	return output;
}
