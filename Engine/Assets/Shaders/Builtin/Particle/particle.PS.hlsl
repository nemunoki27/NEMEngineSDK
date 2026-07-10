//============================================================================
//	include
//============================================================================
#include "particle.hlsli"

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

	// マテリアル色と粒子色をテクスチャへ掛ける、ライティングは行わない
	float4 baseColor = baseColorTexture.Sample(gSampler, input.texcoord) * color * input.color;
	// アルファ棄却、閾値未満のピクセルは描かない
	clip(baseColor.a - input.materialParams.x);
	// 発光を加算する
	baseColor.rgb += input.emissive.rgb * input.emissive.w;

	PSOutput output;
	output.color = baseColor;
	return output;
}
