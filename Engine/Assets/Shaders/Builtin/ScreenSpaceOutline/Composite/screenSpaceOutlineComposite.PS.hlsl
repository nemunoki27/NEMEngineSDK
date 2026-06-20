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

// 遮蔽判定あり (実際に見えている対象)
Texture2D<uint> gOutlineMask : register(t0);
// Dilation 後の領域
Texture2D<uint> gDilatedOutlineMask : register(t1);
// 遮蔽判定なし (選択対象本来のシルエット)
Texture2D<uint> gProjectedCoverageMask : register(t2);
// Style 設定
StructuredBuffer<ScreenSpaceOutlineStyleGPU> gOutlineStyles : register(t3);

//============================================================================
//	main
// DilatedMask - OriginalMask の外周だけをStyleの色で描く
// Mesh内部(元maskが非0)は塗らず、背景側の輪郭だけalpha blendで合成する
//============================================================================
float4 main(float4 position : SV_Position) : SV_Target0 {

	int2 pixel = int2(position.xy);

	uint sourceStyle = gOutlineMask.Load(int3(pixel, 0));
	uint dilatedStyle = gDilatedOutlineMask.Load(int3(pixel, 0));

	// 外周(元mask=0 かつ dilated!=0)かつstyleID範囲内のときだけStyleを読んで判定
	if (sourceStyle == 0u && dilatedStyle != 0u && dilatedStyle <= gStyleCount) {

		ScreenSpaceOutlineStyleGPU style = gOutlineStyles[dilatedStyle - 1u];

		// ExteriorPreferred 指定がある場合、選択対象本来のシルエット(Projected Coverage)
		// よりも内側の輪郭(遮蔽物によってVisible Maskに開いた穴の縁)を描画しない
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
