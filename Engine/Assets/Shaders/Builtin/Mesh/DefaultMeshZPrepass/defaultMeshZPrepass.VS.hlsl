//============================================================================
//	include
//============================================================================
#include "../Common/defaultMesh.hlsli"

//============================================================================
//	main
//============================================================================
DepthVSOutput main(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID) {

	MeshVertex vertex = LoadMeshVertex(instanceID, vertexID);

	// 頂点が属するサブメッシュのローカル行列を親行列に掛ける
	uint localSubMeshIndex = gVertexSubMeshIndices[vertexID];
	float4x4 worldMatrix = GetInstanceSubMeshWorldMatrix(instanceID, localSubMeshIndex);
	float4 worldPos = mul(vertex.position, worldMatrix);

	DepthVSOutput output;
	
	output.position = mul(worldPos, viewProjection);

	return output;
}
