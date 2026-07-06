#ifndef NEM_FILL_MESH_OUTLINE_MASK_HLSLI
#define NEM_FILL_MESH_OUTLINE_MASK_HLSLI

//============================================================================
//	include
//============================================================================
#include "fillMesh.hlsli"
#include "../ScreenSpaceOutline/Common/screenSpaceOutlineCommon.hlsli"

//============================================================================
//	resources
//============================================================================
// この描画単位のStyle IDとSubMesh制限
cbuffer ScreenSpaceOutlineMaskConstantsBuffer : register(b1, space1) {

	ScreenSpaceOutlineMaskConstants gMaskConstants;
};

//============================================================================
//	output
//============================================================================
struct MaskVSOutput {

	float4 position : SV_Position;
	// 補間しないStyleIDと、頂点が属するローカルSubMeshインデックス
	nointerpolation uint styleID : OUTLINESTYLE0;
	nointerpolation int localSubMeshIndex : OUTLINESUBMESH0;
};

#endif // NEM_FILL_MESH_OUTLINE_MASK_HLSLI
