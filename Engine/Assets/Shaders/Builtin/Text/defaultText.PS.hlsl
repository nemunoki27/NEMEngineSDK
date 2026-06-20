//============================================================================
//	include
//============================================================================
#include "defaultText.hlsli"

//============================================================================
//	output
//============================================================================
struct PSOutput {

	float4 color : SV_TARGET0;
};

//============================================================================
//	resources
//============================================================================
Texture2D<float4> gAtlas : register(t1);
SamplerState gSampler : register(s0);

struct PSInstance {

	float4 color;
	float4 outlineColor;
	float2 atlasSize;
	float pxRange;
	float outlineWidthPx;
	uint enableOutline;
	float padding0;
	float padding1;
	float padding2;
};
StructuredBuffer<PSInstance> gPSInstances : register(t2);

//============================================================================
//	functions
//============================================================================
// RGBの中央値を計算する関数
float Median(float r, float g, float b) {

	return max(min(r, g), min(max(r, g), b));
}

// スクリーン上のピクセル距離を計算する関数
float ComputeScreenPxRange(float2 uv, float pxRange, float2 atlasSize) {

	float2 unitRange = float2(pxRange / atlasSize.x, pxRange / atlasSize.y);
	float2 screenTexSize = rcp(fwidth(uv));
	return max(0.5f * dot(unitRange, screenTexSize), 1.0f);
}

//============================================================================
//	main
//============================================================================
PSOutput main(VSOutput input) {

	PSInstance instance = gPSInstances[input.instanceID];

	// テクスチャからMSDFをサンプリング
	float3 msdf = gAtlas.Sample(gSampler, input.texcoord).rgb;
	float signedDistance = Median(msdf.r, msdf.g, msdf.b) - 0.5f;
	float screenPxDistance = ComputeScreenPxRange(input.texcoord, instance.pxRange, instance.atlasSize) * signedDistance;

	// 文字本体のカバレッジ
	float fillAlpha = saturate(screenPxDistance + 0.5f);

	PSOutput output;

	// アウトライン有効時は本体より広い距離でカバレッジを取り、縁を別色で塗る
	if (instance.enableOutline != 0u && instance.outlineWidthPx > 0.0f) {

		float outerAlpha = saturate(screenPxDistance + instance.outlineWidthPx + 0.5f);
		// 縁はoutlineColor、内側へ向かって本体色へ補間する
		float3 rgb = lerp(instance.outlineColor.rgb, instance.color.rgb, fillAlpha);
		float regionAlpha = lerp(instance.outlineColor.a, instance.color.a, fillAlpha);
		float alpha = outerAlpha * regionAlpha;

		// グリフ外の透明ピクセルを捨てる、3Dの深度書き込みで遮蔽させないため
		if (alpha < (1.0f / 255.0f)) {
			discard;
		}
		output.color = float4(rgb, alpha);
		return output;
	}

	// アウトライン無効時は本体のみ
	float alpha = fillAlpha * instance.color.a;
	if (alpha < (1.0f / 255.0f)) {
		discard;
	}
	output.color = float4(instance.color.rgb, alpha);

	return output;
}