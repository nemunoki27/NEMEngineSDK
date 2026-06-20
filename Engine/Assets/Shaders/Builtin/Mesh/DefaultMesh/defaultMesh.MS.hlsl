//============================================================================
//	include
//============================================================================
#include "../Common/defaultMesh.hlsli"

groupshared float4x4 gMeshletWorldMatrix;
groupshared float4x4 gMeshletNormalMatrix;
groupshared float gMeshletOrientationSign;

//============================================================================
//	main
//============================================================================
[outputtopology("triangle")]
[numthreads(128, 1, 1)]
void main(uint groupThreadID : SV_GroupThreadID, uint3 groupID : SV_GroupID, in payload MeshDispatchPayload payload,
	out vertices VSOutput outVerts[64], out indices uint3 outTris[124]) {

	uint meshletIndex = payload.meshletIndices[groupID.x];
	uint instanceIndex = payload.instanceIndices[groupID.x];

	MeshletDrawDesc meshlet = gMeshlets[meshletIndex];
	SetMeshOutputCounts(meshlet.vertexCount, meshlet.primitiveCount);

	const uint localSubMeshIndex = meshlet.subMeshIndex;
	if (groupThreadID == 0) {

		gMeshletWorldMatrix = GetInstanceSubMeshWorldMatrix(instanceIndex, localSubMeshIndex);
		gMeshletNormalMatrix = GetInstanceSubMeshNormalMatrix(instanceIndex, localSubMeshIndex);
		gMeshletOrientationSign = GetInstanceSubMeshOrientationSign(instanceIndex, localSubMeshIndex);
	}
	GroupMemoryBarrierWithGroupSync();

	if (groupThreadID < meshlet.primitiveCount) {

		outTris[groupThreadID] = UnpackPrimitiveIndex(gMeshletPrimitiveIndices[meshlet.primitiveOffset + groupThreadID]);
	}

	if (groupThreadID < meshlet.vertexCount) {

		uint vertexIndex = LoadMeshletVertexIndex(meshlet.vertexOffset + groupThreadID);
		MeshVertex vertex = LoadMeshVertex(instanceIndex, vertexIndex);

		// 頂点が属するサブメッシュのローカル行列を親行列に掛ける
		float4 worldPos = mul(vertex.position, gMeshletWorldMatrix);

		VSOutput output;
		output.position = mul(worldPos, viewProjection);
		output.worldPos = worldPos.xyz;
		// VS経路と同じく、法線はnormalMatrix、接線はworldMatrixで変換する
		output.normal = TransformMeshNormalToWorld(vertex.normal, gMeshletNormalMatrix);
		output.tangent = TransformMeshTangentToWorld(vertex.tangent, gMeshletWorldMatrix);
		output.uv = vertex.uv;
		output.instanceID = instanceIndex;
		output.subMeshIndex = localSubMeshIndex;
		output.tangentSign = vertex.tangentSign;
		output.orientationSign = gMeshletOrientationSign;

		outVerts[groupThreadID] = output;
	}
}
