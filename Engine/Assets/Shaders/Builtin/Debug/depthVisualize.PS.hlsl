//============================================================================
//	include
//============================================================================
#include "../FullscreenCopy/FullscreenCopy.hlsli"

//============================================================================
//	resources
//============================================================================
Texture2D<float> gDepth : register(t0);
SamplerState gSampler : register(s0);

//============================================================================
//	main
//	GBufferデバッグ表示用に深度を可視化する
//	透視深度はfar側へ強く偏るので線形化し、近=暗 遠=明のグレースケールにする
//	near/farは可視化用の概算値、相対的な深度構造の確認が目的
//============================================================================
float4 main(VSOutput input) : SV_TARGET {

	float depth = gDepth.Sample(gSampler, input.texcoord);

	// depth>=1は背景なので白寄りにせず黒で潰す、描画されていない領域と区別する
	if (depth >= 1.0f) {
		return float4(0.0f, 0.0f, 0.0f, 1.0f);
	}

	const float nearZ = 0.1f;
	const float farZ = 100.0f;

	// 非線形な深度をビュー空間の距離へ戻す
	float linearZ = nearZ * farZ / (farZ - depth * (farZ - nearZ));

	// 近距離を見やすくするため距離を圧縮してグレースケール化する
	float g = saturate(linearZ / farZ);
	g = pow(g, 0.45f);

	return float4(g, g, g, 1.0f);
}
