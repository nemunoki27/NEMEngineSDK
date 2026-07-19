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

	const float2 farthestCorner = max(center, viewportSize - center);
	const float maxRadius = length(farthestCorner);
	const float softness = max(edgeSoftness, 0.0001f);
	const float normalizedProgress = saturate(progress);
	const float radius = invertMask < 0.5f ?
		lerp(maxRadius + softness, -softness, normalizedProgress) :
		lerp(-softness, maxRadius + softness, normalizedProgress);
	const float distanceFromCenter = length(input.position.xy - center);
	const float radialMask = smoothstep(
		radius - softness, radius + softness, distanceFromCenter);
	const float mask = invertMask < 0.5f ? radialMask : 1.0f - radialMask;

	PSOutput output;
	output.color = float4(
		transitionColor.rgb, transitionColor.a * mask);
	return output;
}
