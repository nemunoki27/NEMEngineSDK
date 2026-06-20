//============================================================================
//	include
//============================================================================
#include "screenSpaceOutlineMask.hlsli"

//============================================================================
//	main
//	見えているMesh表面にStyleIDを書き込む、0や対象外SubMeshはdiscardする
//============================================================================
uint main(MaskVSOutput input) : SV_Target0 {

	if (input.styleID == 0u) {
		discard;
	}
	if (gMaskConstants.restrictSubMeshIndex >= 0 &&
		input.localSubMeshIndex != gMaskConstants.restrictSubMeshIndex) {
		discard;
	}
	return input.styleID;
}
