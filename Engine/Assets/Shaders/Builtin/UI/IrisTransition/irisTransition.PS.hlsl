//============================================================================
//	include
//============================================================================
#include "../../Sprite/defaultSprite.hlsli"

//============================================================================
//	output
//============================================================================
struct PSOutput {

	float4 color : SV_TARGET0;
};

//============================================================================
//	resources
//============================================================================
cbuffer MaterialParameters : register(b3) {

	float4 transitionColor;
	float2 center;
	float progress;
	float edgeSoftness;
	float2 viewportSize;
	float invertMask;
	float _padding;
};

//============================================================================
//	main
//============================================================================
PSOutput main(VSOutput input) {

	// 中心から最も遠い画面端までの距離
	float2 farthestCorner = max(center, viewportSize - center);
	// 画面全体を覆うために必要な最大半径
	float maxRadius = length(farthestCorner);
	// ぼかし幅
	float softness = max(edgeSoftness, 0.0001f);
	// 進行度0.0f~1.0fに制限
	float normalizedProgress = saturate(progress);

	// 反転設定からマスクの計算方向を判定
	bool isInvert = invertMask < 0.5f;

	// 現在のマスク半径
	float radius = 0.0f;
	// 外側から中心へ閉じる
	if (isInvert) {

		radius = lerp(maxRadius + softness, -softness, normalizedProgress);
	}
	// 中心から外側へ広げる
	else {

		radius = lerp(-softness, maxRadius + softness, normalizedProgress);
	}
	// 現在のピクセルと中心の距離
	float distanceFromCenter = length(input.position.xy - center);
	// 円周のぼかしを含む距離マスク
	float radialMask = smoothstep(radius - softness, radius + softness, distanceFromCenter);
	// 反転設定を最終マスクへ反映
	float mask = isInvert ? radialMask : 1.0f - radialMask;

	PSOutput output;
	// 遮蔽色へマスクの濃度を適用
	output.color = float4(transitionColor.rgb, transitionColor.a * mask);
	return output;
}
