//============================================================================
//	include
//============================================================================
#include "../primitive2D.hlsli"

//============================================================================
//	resources
//============================================================================
cbuffer MaterialParameters : register(b3) {

	float4 color;
	float progress;
	uint fillDirection;
	uint primitiveType;
	float _pad;
};
Texture2D<float4> baseColorTexture : register(t0, space2);
SamplerState gSampler : register(s0);

//============================================================================
//	output
//============================================================================
struct PSOutput {

	float4 color : SV_TARGET0;
};

//============================================================================
//	main
//============================================================================
PSOutput main(VSOutput input) {

	const float ratio = saturate(progress);
	if (ratio <= 0.0f) {
		discard;
	}

	bool discardPixel = false;
	if (primitiveType == 1u) {

		const bool reverse = fillDirection == 1u || fillDirection == 3u;
		discardPixel = reverse ?
			input.localTexcoord.x < 1.0f - ratio :
			ratio < input.localTexcoord.x;
	} else {

		switch (fillDirection) {
		case 1u:
			discardPixel = input.localTexcoord.x < 1.0f - ratio;
			break;
		case 2u:
			discardPixel = ratio < input.localTexcoord.y;
			break;
		case 3u:
			discardPixel = input.localTexcoord.y < 1.0f - ratio;
			break;
		case 0u:
		default:
			discardPixel = ratio < input.localTexcoord.x;
			break;
		}
	}
	if (discardPixel) {
		discard;
	}

	PSOutput output;
	output.color = baseColorTexture.Sample(gSampler, input.texcoord) * color;
	return output;
}
