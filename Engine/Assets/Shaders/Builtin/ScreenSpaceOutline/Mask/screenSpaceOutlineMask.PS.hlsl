//============================================================================
//	include
//============================================================================
#include "screenSpaceOutlineMask.hlsli"

//============================================================================
//	main
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
