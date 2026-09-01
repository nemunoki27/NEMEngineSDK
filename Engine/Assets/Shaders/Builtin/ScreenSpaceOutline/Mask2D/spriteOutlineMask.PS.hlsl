//============================================================================
//	include
//============================================================================
#include "../../Sprite/defaultSprite.hlsli"
#include "../Common/screenSpaceOutlineCommon.hlsli"

//============================================================================
//	resources
//============================================================================
Texture2D<float4> baseColorTexture : register(t0, space2);
SamplerState gSampler : register(s0);

cbuffer MaterialParameters : register(b3) {

	float4 color;
};

struct PSInstance {

	float4x4 uvMatrix;
};
StructuredBuffer<PSInstance> gPSInstances : register(t2);

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

	const PSInstance instance = gPSInstances[input.instanceID];
	const float2 uv = mul(
		float4(input.texcoord, 0.0f, 1.0f), instance.uvMatrix).xy;
	const float4 textureColor = baseColorTexture.Sample(gSampler, uv);
	const float4 outputColor = textureColor * color;
	const float alpha = ResolveScreenSpaceOutlineAlpha(
		textureColor, outputColor, gMaskConstants.alphaSource);
	clip(alpha - (0.5f / 255.0f));
	return gMaskConstants.styleID;
}
