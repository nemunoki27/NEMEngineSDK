//============================================================================
//	include
//============================================================================
#include "primitive2D.hlsli"
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
	return BuildPrimitive2DVertexOutput(
		v.position.xyz, v.uv, instance);
}
