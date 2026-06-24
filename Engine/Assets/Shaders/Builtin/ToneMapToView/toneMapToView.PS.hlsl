//============================================================================
//	include
//============================================================================
#include "../FullscreenCopy/fullscreenCopy.hlsli"

//============================================================================
//	resources
//============================================================================
Texture2D<float4> gTexture : register(t0);
SamplerState gSampler : register(s0);

//============================================================================
//	constants
//============================================================================
static const float kExposure = 1.0f;
static const float kGamma = 2.2f;
static const float kInvGamma = 1.0f / kGamma;

//============================================================================
//	functions
//============================================================================
float3 ToneMapReinhard(float3 color) {

	return color / (color + 1.0f);
}

float3 ToneMapACES(float3 color) {

	const float a = 2.51f;
	const float b = 0.03f;
	const float c = 2.43f;
	const float d = 0.59f;
	const float e = 0.14f;

	return saturate((color * (a * color + b)) / (color * (c * color + d) + e));
}

float3 LinearToGamma(float3 color) {

	return pow(saturate(color), kInvGamma);
}

//============================================================================
//	main
//============================================================================
float4 main(VSOutput input) : SV_TARGET0 {

	float4 src = gTexture.Sample(gSampler, input.texcoord);

	float3 hdrColor = max(src.rgb, 0.0f);

	// 露出
	hdrColor *= kExposure;

	// HDR -> LDR
	float3 ldrColor = ToneMapACES(hdrColor);
	ldrColor = LinearToGamma(ldrColor);

	return float4(ldrColor, 1.0f);
}
