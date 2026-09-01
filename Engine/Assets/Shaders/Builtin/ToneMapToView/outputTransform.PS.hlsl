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
cbuffer OutputTransformConstants : register(b0) {

	uint outputMode;
	float paperWhiteNits;
	float maxLuminanceNits;
	float _pad0;
};

//============================================================================
//	functions
//============================================================================
float3 LinearRec709ToRec2020(float3 color) {

	const float3x3 conversion = {
		0.6274040f, 0.3292820f, 0.0433136f,
		0.0690970f, 0.9195400f, 0.0113612f,
		0.0163916f, 0.0880132f, 0.8955950f,
	};
	return mul(conversion, color);
}

float3 LinearToPQ(float3 color) {

	const float m1 = 2610.0f / 16384.0f;
	const float m2 = 2523.0f / 32.0f;
	const float c1 = 3424.0f / 4096.0f;
	const float c2 = 2413.0f / 128.0f;
	const float c3 = 2392.0f / 128.0f;
	const float3 powered = pow(saturate(color), m1);
	return pow((c1 + c2 * powered) / (1.0f + c3 * powered), m2);
}

//============================================================================
//	main
//============================================================================
float4 main(VSOutput input) : SV_TARGET0 {

	const float4 src = gTexture.Sample(gSampler, input.texcoord);
	if (outputMode == 1) {

		const float3 rec2020 = max(LinearRec709ToRec2020(src.rgb), 0.0f);
		const float3 normalizedNits = rec2020 * paperWhiteNits / 10000.0f;
		return float4(LinearToPQ(normalizedNits), src.a);
	}
	if (outputMode == 2) {
		return float4(src.rgb * paperWhiteNits / 80.0f, src.a);
	}
	return src;
}
