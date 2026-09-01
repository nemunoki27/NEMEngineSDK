#include "../Common/defaultMesh.hlsli"

groupshared MeshDispatchPayload payload;

//============================================================================
//	main
//============================================================================
[numthreads(32, 1, 1)]
void main(uint groupThreadID : SV_GroupThreadID, uint3 groupID : SV_GroupID) {

	const uint localMeshletIndex = groupID.x * 32u + groupThreadID;
	const uint instanceIndex = groupID.y;
	uint meshletIndex = 0u;
	bool inRange = instanceIndex < instanceCount;
	if (inRange) {

		const uint lodIndex = ResolveMeshLOD(gMeshInstances[instanceIndex]);
		inRange = localMeshletIndex < lodMeshletCounts[lodIndex];
		meshletIndex = lodMeshletOffsets[lodIndex] + localMeshletIndex;
	}
	const bool visible = inRange && IsMeshletVisible(meshletIndex, instanceIndex);

	const uint visibleOffset = WavePrefixCountBits(visible);
	const uint visibleCount = WaveActiveCountBits(visible);
	if (visible) {

		payload.meshletIndices[visibleOffset] = meshletIndex;
		payload.instanceIndices[visibleOffset] = instanceIndex;
	}
	GroupMemoryBarrierWithGroupSync();

	DispatchMesh(visibleCount, 1, 1, payload);
}
