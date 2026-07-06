//============================================================================
//	include
//============================================================================
#include "primitive.hlsli"
#include "../Mesh/Common/meshShaderSharedTypes.hlsli"

//============================================================================
//	resources
//============================================================================
StructuredBuffer<MeshVertex> gVertices : register(t0);
StructuredBuffer<PrimitiveInstance> gInstances : register(t1);

//============================================================================
//	main
//============================================================================
VSOutput main(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID) {

	MeshVertex v = gVertices[vertexID];
	PrimitiveInstance instance = gInstances[instanceID];

	VSOutput output;
	// インスタンスごとのワールド行列でSRTを反映する
	float4 worldPos = mul(float4(v.position.xyz, 1.0f), instance.worldMatrix);
	output.position = mul(worldPos, viewProjection);
	output.worldPos = worldPos.xyz;
	output.normal = normalize(mul(v.normal, (float3x3)instance.worldMatrix));
	output.tangent = normalize(mul(v.tangent, (float3x3)instance.worldMatrix));
	output.tangentSign = v.tangentSign;
	output.texcoord = mul(float4(v.uv, 0.0f, 1.0f), instance.uvMatrix).xy;
	output.flags = instance.flags;

	return output;
}
