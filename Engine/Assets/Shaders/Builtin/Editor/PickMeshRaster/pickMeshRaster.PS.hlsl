//============================================================================
//	include
//============================================================================
#include "../../Mesh/Common/defaultMesh.hlsli"

//============================================================================
//	main
//============================================================================
uint4 main(VSOutput input) : SV_Target0 {

	MeshInstance instance = gMeshInstances[input.instanceID];
	return uint4(
		instance.entityIndex,
		instance.entityGeneration,
		input.subMeshIndex,
		1u);
}
