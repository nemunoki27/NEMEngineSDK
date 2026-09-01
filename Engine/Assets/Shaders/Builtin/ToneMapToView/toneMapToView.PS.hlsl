//============================================================================
//	include
//============================================================================
#include "../FullscreenCopy/fullscreenCopy.hlsli"

//============================================================================
//	resources
//============================================================================
Texture2D<float4> gTexture : register(t0);
StructuredBuffer<float4> gExposureState : register(t1);
SamplerState gSampler : register(s0);

//============================================================================
//	constants
//============================================================================
cbuffer ColorPipelineConstants : register(b0) {

	uint width;
	uint height;
	uint exposureMode;
	uint resetExposure;

	float manualEV100;
	float exposureCompensation;
	float minEV100;
	float maxEV100;

	float histogramLowPercent;
	float histogramHighPercent;
	float speedUp;
	float speedDown;

	float deltaTime;
	float usePreExposure;
	float filmicSlope;
	float filmicToe;

	float filmicShoulder;
	float filmicBlackClip;
	float filmicWhiteClip;
	float _pad0;

	float4 colorFilter;
	float3 whiteBalance;
	float _pad1;
	float3 saturation;
	float _pad2;
	float3 contrast;
	float _pad3;
	float3 gamma;
	float _pad4;
	float3 gain;
	float _pad5;
	float3 offset;
	float _pad6;

	uint outputMode;
	float paperWhiteNits;
	float maxLuminanceNits;
	float _pad7;
};

//============================================================================
//	functions
//============================================================================
float3 ACESFitted(float3 color) {

	const float3x3 inputMatrix = {
		0.59719f, 0.35458f, 0.04823f,
		0.07600f, 0.90834f, 0.01566f,
		0.02840f, 0.13383f, 0.83777f,
	};
	const float3x3 outputMatrix = {
		 1.60475f, -0.53108f, -0.07367f,
		-0.10208f,  1.10813f, -0.00605f,
		-0.00327f, -0.07276f,  1.07602f,
	};
	color = mul(inputMatrix, color);
	const float3 numerator = color * (color + 0.0245786f) - 0.000090537f;
	const float3 denominator = color * (0.983729f * color + 0.4329510f) +
		0.238081f;
	color = numerator / denominator;
	return saturate(mul(outputMatrix, color));
}

float3 ApplyColorGrading(float3 color) {

	color *= colorFilter.rgb * whiteBalance;
	const float luminance = dot(color, float3(0.2126f, 0.7152f, 0.0722f));
	color = luminance.xxx + (color - luminance.xxx) * saturation;
	color = (color - 0.18f) * contrast + 0.18f;
	color = pow(max(color, 0.0f), 1.0f / max(gamma, 0.01f));
	return color * gain + offset;
}

float3 ApplyFilmicControls(float3 color) {

	color = pow(saturate(color), 1.0f + filmicToe * 1.5f);
	color = 1.0f - pow(1.0f - color, 1.0f + filmicShoulder * 2.0f);
	const float range = max(1.0f - filmicBlackClip - filmicWhiteClip, 0.001f);
	return saturate((color - filmicBlackClip) / range);
}

//============================================================================
//	main
//============================================================================
float4 main(VSOutput input) : SV_TARGET0 {

	float4 src = gTexture.Sample(gSampler, input.texcoord);

	float3 hdrColor = max(src.rgb, 0.0f);

	// 前フレーム露出から現在露出への比で時間的なPre-Exposureを補正する
	const float currentExposure = max(gExposureState[0].x, 1.0e-6f);
	const float previousExposure = usePreExposure != 0.0f ?
		max(gExposureState[0].y, 1.0e-6f) : 1.0f;
	hdrColor *= previousExposure;
	hdrColor *= currentExposure / previousExposure;
	hdrColor = ApplyColorGrading(hdrColor);

	// HDR -> LDR
	float3 ldrColor = ACESFitted(hdrColor * filmicSlope);
	ldrColor = ApplyFilmicControls(ldrColor);
	if (outputMode != 0) {
		// 通常の白はPaper Whiteへ置き、強い発光だけをDisplay最大輝度まで展開する
		const float peakRatio = max(maxLuminanceNits /
			max(paperWhiteNits, 1.0f), 1.0f);
		const float scenePeak = max(hdrColor.r,
			max(hdrColor.g, hdrColor.b));
		const float highlight = saturate((scenePeak - 1.0f) /
			max(scenePeak + 3.0f, 1.0f));
		ldrColor *= lerp(1.0f, peakRatio, highlight);
	}

	// 出力先はLinear FLOAT、最終sRGB RTVで一度だけ伝達関数を適用する
	return float4(ldrColor, 1.0f);
}
