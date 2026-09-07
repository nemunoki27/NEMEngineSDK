//============================================================================
//	include
//============================================================================
#include "primitive2D.hlsli"

//============================================================================
//	resources
//============================================================================
cbuffer MaterialParameters : register(b3) {

	float4 color;
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

	// ベースカラー = マテリアル色 × テクスチャ、ライティングは行わない
	const float2 uv = ResolvePrimitivePixelUV(input.texcoord,
		input.uvCoordinates, input.ringParams, input.uvBasis);
	float4 baseColor = baseColorTexture.Sample(gSampler, uv) * color;

	PSOutput output;
	output.color = baseColor;
	return output;
}
