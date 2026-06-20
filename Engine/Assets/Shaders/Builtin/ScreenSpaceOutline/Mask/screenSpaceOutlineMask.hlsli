#ifndef NEM_SCREEN_SPACE_OUTLINE_MASK_HLSLI
#define NEM_SCREEN_SPACE_OUTLINE_MASK_HLSLI

//============================================================================
//	include
//	Mesh共通のworld transform / 頂点ロード / メッシュレットカリングを再利用する
//============================================================================
#include "../../Mesh/Common/defaultMesh.hlsli"
#include "../Common/screenSpaceOutlineCommon.hlsli"

//============================================================================
//	resources
//============================================================================
// この描画単位のStyle IDとSubMesh制限。0は描画しない。restrictが0以上ならそのSubMeshのみ
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
#endif // NEM_SCREEN_SPACE_OUTLINE_MASK_HLSLI