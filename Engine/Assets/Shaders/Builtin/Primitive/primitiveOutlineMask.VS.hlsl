//============================================================================
//	include
//============================================================================
#include "primitiveOutlineMask.hlsli"
#include "../Mesh/Common/meshShaderSharedTypes.hlsli"

//============================================================================
//	resources
//============================================================================
StructuredBuffer<MeshVertex> gVertices : register(t0);
StructuredBuffer<PrimitiveInstance> gInstances : register(t1);

//============================================================================
//	main
//============================================================================
MaskVSOutput main(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID) {

	MeshVertex v = gVertices[vertexID];
	PrimitiveInstance instance = gInstances[instanceID];

	// 通常描画と同じworld transformでマスクを描く
	float4 worldPos = mul(float4(v.position.xyz, 1.0f), instance.worldMatrix);

	MaskVSOutput output;
	output.position = mul(worldPos, viewProjection);
	output.styleID = gMaskConstants.styleID;
	output.localSubMeshIndex = 0;
	return output;
}
