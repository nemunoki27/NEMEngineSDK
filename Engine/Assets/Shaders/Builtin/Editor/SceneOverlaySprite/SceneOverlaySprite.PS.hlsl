//============================================================================
//	resources
//============================================================================
Texture2D<float4> gSceneOverlayTexture : register(t0);
SamplerState gSceneOverlaySampler : register(s0);

//============================================================================
//	input / output
//============================================================================
struct VSOutput {
	float4 position : SV_POSITION;
	float2 uv : TEXCOORD0;
	float4 color : COLOR0;
};

struct PSOutput {
	float4 color : SV_TARGET0;
};

//============================================================================
//	main
//============================================================================
PSOutput main(VSOutput input) {

	float4 texel = gSceneOverlayTexture.Sample(gSceneOverlaySampler, input.uv);

	PSOutput output;
	output.color.rgb = texel.rgb * input.color.rgb;
	output.color.a = texel.a * input.color.a;
	return output;
}
