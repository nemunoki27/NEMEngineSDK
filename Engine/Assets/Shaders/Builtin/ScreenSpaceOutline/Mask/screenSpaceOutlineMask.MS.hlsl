//============================================================================
//	include
//============================================================================
#include "screenSpaceOutlineMask.hlsli"

groupshared float4x4 gMeshletWorldMatrix;

//============================================================================
//	main
//============================================================================
[outputtopology("triangle")]
[numthreads(128, 1, 1)]
void main(uint groupThreadID : SV_GroupThreadID, uint3 groupID : SV_GroupID, in payload MeshDispatchPayload payload,
	out vertices MaskVSOutput outVerts[64], out indices uint3 outTris[124]) {

	uint meshletIndex = payload.meshletIndices[groupID.x];
	uint instanceIndex = payload.instanceIndices[groupID.x];

	MeshletDrawDesc meshlet = gMeshlets[meshletIndex];
	SetMeshOutputCounts(meshlet.vertexCount, meshlet.primitiveCount);

	const uint localSubMeshIndex = meshlet.subMeshIndex;
	if (groupThreadID == 0) {

		gMeshletWorldMatrix = GetInstanceSubMeshWorldMatrix(instanceIndex, localSubMeshIndex);
	}
	GroupMemoryBarrierWithGroupSync();

	if (groupThreadID < meshlet.primitiveCount) {

		outTris[groupThreadID] = UnpackPrimitiveIndex(gMeshletPrimitiveIndices[meshlet.primitiveOffset + groupThreadID]);
	}

	if (groupThreadID < meshlet.vertexCount) {

		uint vertexIndex = LoadMeshletVertexIndex(meshlet.vertexOffset + groupThreadID);
		MeshVertex vertex = LoadMeshVertex(instanceIndex, vertexIndex);

		float4 worldPos = mul(vertex.position, gMeshletWorldMatrix);

		MaskVSOutput output;
		output.position = mul(worldPos, viewProjection);
		output.styleID = gMaskConstants.styleID;
		output.localSubMeshIndex = (int)localSubMeshIndex;

		outVerts[groupThreadID] = output;
	}
}
