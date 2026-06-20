//============================================================================
//	include
//============================================================================
#include "screenSpaceOutlineMask.hlsli"

//============================================================================
//	main
//============================================================================
MaskVSOutput main(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID) {

	MeshVertex vertex = LoadMeshVertex(instanceID, vertexID);

	// 通常Mesh描画と同じworld transformを使う
	uint localSubMeshIndex = gVertexSubMeshIndices[vertexID];
	float4x4 worldMatrix = GetInstanceSubMeshWorldMatrix(instanceID, localSubMeshIndex);
	float4 worldPos = mul(vertex.position, worldMatrix);

	MaskVSOutput output;
	output.position = mul(worldPos, viewProjection);
	output.styleID = gMaskConstants.styleID;
	output.localSubMeshIndex = (int)localSubMeshIndex;
	return output;
}
