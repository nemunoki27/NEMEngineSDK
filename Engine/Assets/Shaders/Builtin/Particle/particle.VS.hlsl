//============================================================================
//	include
//============================================================================
#include "particle.hlsli"
#include "../Mesh/Common/meshShaderSharedTypes.hlsli"

//============================================================================
//	resources
//============================================================================
StructuredBuffer<MeshVertex> gVertices : register(t0);
StructuredBuffer<ParticleInstance> gInstances : register(t1);

//============================================================================
//	main
//============================================================================
VSOutput main(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID) {

	MeshVertex v = gVertices[vertexID];
	ParticleInstance instance = gInstances[instanceID];

	VSOutput output;
	// 粒子ごとのワールド行列でSRTを反映する
	float4 worldPos = mul(float4(v.position.xyz, 1.0f), instance.worldMatrix);
	output.position = mul(worldPos, viewProjection);
	// フリップブックのコマ送りをUVへ反映する
	output.texcoord = v.uv * instance.uvScaleOffset.xy + instance.uvScaleOffset.zw;
	output.color = instance.color;
	output.emissive = instance.emissive;
	output.materialParams = instance.materialParams;

	return output;
}
