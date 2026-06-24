//============================================================================
//	include
//============================================================================
#include "../Common/screenSpaceOutlineCommon.hlsli"

//============================================================================
//	resources
//============================================================================
cbuffer CompositeConstants : register(b0) {

	uint gStyleCount;
	uint3 _compositePad;
};

// 遮蔽判定ありの可視mask
Texture2D<uint> gOutlineMask : register(t0);
// Dilation後の領域
Texture2D<uint> gDilatedOutlineMask : register(t1);
// 遮蔽判定なしのシルエットmask
Texture2D<uint> gProjectedCoverageMask : register(t2);
// Style設定
StructuredBuffer<ScreenSpaceOutlineStyleGPU> gOutlineStyles : register(t3);

//============================================================================
//	main
//============================================================================
float4 main(float4 position : SV_Position) : SV_Target0 {

	int2 pixel = int2(position.xy);

	uint sourceStyle = gOutlineMask.Load(int3(pixel, 0));
	uint dilatedStyle = gDilatedOutlineMask.Load(int3(pixel, 0));

	// 外周かつstyleID範囲内のときだけStyleを読んで判定
	if (sourceStyle == 0u && dilatedStyle != 0u && dilatedStyle <= gStyleCount) {

		ScreenSpaceOutlineStyleGPU style = gOutlineStyles[dilatedStyle - 1u];

		// ExteriorPreferred指定時はシルエットより内側の輪郭を描かない
		if (style.regionMode == 1u /* ExteriorPreferred */) {

			uint projectedStyle = gProjectedCoverageMask.Load(int3(pixel, 0));
			if (projectedStyle != 0u) {
				discard;
			}
		}

		return style.color;
	}

	discard;
	return float4(0.0f, 0.0f, 0.0f, 0.0f);
}
