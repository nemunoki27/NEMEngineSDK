//============================================================================
//	include
//============================================================================
#define NEM_ENABLE_MESH_DISPLACEMENT
#include "defaultMesh.hlsli"

//============================================================================
//	main
//============================================================================
VSOutput main(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID) {

	return BuildMeshSurfaceVertex(vertexID, instanceID);
}
