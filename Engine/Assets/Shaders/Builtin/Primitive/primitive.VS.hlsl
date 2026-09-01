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
	return BuildPrimitiveVertexOutput(
		v.position.xyz,
		v.normal,
		v.tangent,
		v.tangentSign,
		v.uv,
		ResolvePrimitiveVertexColor(v.position.xyz, instance),
		instance);
}
