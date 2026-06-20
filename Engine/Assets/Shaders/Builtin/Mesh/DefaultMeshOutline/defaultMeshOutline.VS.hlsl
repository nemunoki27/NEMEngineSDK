//============================================================================
//	include
//============================================================================
#include "../Common/defaultMeshOutline.hlsli"

//============================================================================
//	main
//============================================================================
OutlineVertexOutput main(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID) {

	MeshVertex vertex = LoadMeshVertex(instanceID, vertexID);
	uint localSubMeshIndex = gVertexSubMeshIndices[vertexID];

	float4x4 worldMatrix = GetInstanceSubMeshWorldMatrix(instanceID, localSubMeshIndex);
	float4x4 normalMatrix = GetInstanceSubMeshNormalMatrix(instanceID, localSubMeshIndex);
	return BuildOutlineVertex(instanceID, localSubMeshIndex, vertex, worldMatrix, normalMatrix);
}
