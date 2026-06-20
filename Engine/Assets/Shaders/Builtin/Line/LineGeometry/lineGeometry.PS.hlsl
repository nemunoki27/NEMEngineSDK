//============================================================================
//	include
//============================================================================
#include "lineGeometry.hlsli"

//============================================================================
//	main
//============================================================================
float4 main(GSOutput input) : SV_TARGET0 {

	float safeOuter = max(input.outerHalfWidth, 1e-4f);
	float safeInner = clamp(input.halfWidth, 0.0f, safeOuter);

	float distanceFromCenter = abs(input.side) * safeOuter;

	// 内側は完全不透明、外側フェザー領域だけ滑らかに減衰
	float coverage = 1.0f - smoothstep(safeInner, safeOuter, distanceFromCenter);

	float4 color = input.color;
	color.a *= coverage;

	clip(color.a - (1.0f / 255.0f));
	return color;
}