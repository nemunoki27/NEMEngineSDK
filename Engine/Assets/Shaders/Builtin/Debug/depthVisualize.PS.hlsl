//============================================================================
//	include
//============================================================================
#include "../FullscreenCopy/fullscreenCopy.hlsli"

//============================================================================
//	resources
//============================================================================
cbuffer DepthVisualizeConstants : register(b0) {

	float gProjectionA;
	float gProjectionB;
	float gNearClip;
	float gFarClip;

	uint gPerspective;
	uint3 _pad;
};

Texture2D<float> gDepth : register(t0);

//============================================================================
//	main
//============================================================================
float4 main(VSOutput input) : SV_TARGET0 {

	uint width = 0;
	uint height = 0;
	gDepth.GetDimensions(width, height);

	const uint2 pixel = min(
		uint2(input.texcoord * float2(width, height)),
		uint2(width - 1, height - 1));
	const float depth = saturate(gDepth.Load(int3(pixel, 0)));

	float visualDepth = 0.0f;
	if (gPerspective != 0) {

		// 非線形深度をView空間距離へ戻し、広い範囲を確認できるよう対数表示する
		const float denominator = depth - gProjectionA;
		const float viewDepth = abs(denominator) > 1.0e-6f ?
			gProjectionB / denominator : gFarClip;
		const float nearClip = max(gNearClip, 1.0e-5f);
		const float farClip = max(gFarClip, nearClip + 1.0e-5f);
		visualDepth = log2(max(viewDepth / nearClip, 1.0f)) /
			log2(farClip / nearClip);
	} else {

		// 正射影深度は射影行列からView空間距離へ線形に戻す
		const float viewDepth = (depth - gProjectionB) /
			max(abs(gProjectionA), 1.0e-6f);
		visualDepth = (viewDepth - gNearClip) /
			max(gFarClip - gNearClip, 1.0e-5f);
	}
	visualDepth = saturate(visualDepth);
	return float4(visualDepth.xxx, 1.0f);
}
