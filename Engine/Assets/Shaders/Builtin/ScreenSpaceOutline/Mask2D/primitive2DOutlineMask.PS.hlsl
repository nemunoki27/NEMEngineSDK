//============================================================================
//	include
//============================================================================
#include "../../Primitive/primitive2D.hlsli"
#include "../Common/screenSpaceOutlineCommon.hlsli"

//============================================================================
//	resources
//============================================================================
Texture2D<float4> baseColorTexture : register(t0, space2);
SamplerState gSampler : register(s0);

cbuffer MaterialParameters : register(b3) {

	float4 color;
};

cbuffer ScreenSpaceOutlineMaskConstantsBuffer : register(b1, space1) {

	ScreenSpaceOutlineMaskConstants gMaskConstants;
};

//============================================================================
//	main
//============================================================================
uint main(VSOutput input) : SV_Target0 {

	if (gMaskConstants.styleID == 0u) {
		discard;
	}

	const float4 textureColor = baseColorTexture.Sample(gSampler, input.texcoord);
	const float4 outputColor = textureColor * color;
	const float alpha = ResolveScreenSpaceOutlineAlpha(
		textureColor, outputColor, gMaskConstants.alphaSource);
	clip(alpha - (0.5f / 255.0f));
	return gMaskConstants.styleID;
}
