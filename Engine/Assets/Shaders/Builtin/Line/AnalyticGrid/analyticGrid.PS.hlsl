//============================================================================
//	include
//============================================================================
#include "analyticGrid.hlsli"

//============================================================================
//	output
//============================================================================
struct PSOutput {
	
	float4 color : SV_TARGET0;
	float depth : SV_Depth;
};

//============================================================================
//	resources
//============================================================================
cbuffer GridPassConstants : register(b0) {

	float4x4 inverseViewProjectionMatrix;
	float4x4 viewProjectionMatrix;

	float4 cameraPositionAndPlaneY;
	float4 viewportSize;
	float4 stepData0;
	float4 stepData1;
	float4 thicknessFadeAndHorizon;

	float4 minorColor;
	float4 minorParams0;
	float4 minorParams1;

	float4 majorColor;
	float4 majorParams0;
	float4 majorParams1;

	float4 coarseColor;
	float4 coarseParams0;
	float4 coarseParams1;

	float4 axisXColor;
	float4 axisZColor;
	float4 axisParams;
};

//============================================================================
//	structures
//============================================================================
float Smoother01(float x) {

	x = saturate(x);
	return x * x * x * (x * (x * 6.0f - 15.0f) + 10.0f);
}

float SmootherStep(float a, float b, float x) {

	return Smoother01((x - a) / max(b - a, 1e-6f));
}

float ComputeDistanceFade(float distanceXZ, float startDistance, float endDistance, float power) {

	float safeEndDistance = max(endDistance, startDistance + 1e-5f);
	float t = saturate((distanceXZ - startDistance) / (safeEndDistance - startDistance));

	float fade = 1.0f - Smoother01(t);
	return pow(max(fade, 0.0f), max(power, 0.01f));
}

float ComputeEffectivePixelWidth(float baseHalfThickness,
	float farThicknessRate,
	float fadeFactor,
	float thicknessFadePower,
	float minHalfThickness) {

	float safeBaseHalfThickness = max(baseHalfThickness, 0.01f);
	float safeFarThicknessRate = saturate(farThicknessRate);
	float safeMinHalfThickness = max(minHalfThickness, 0.01f);

	float thicknessT = pow(saturate(fadeFactor), max(thicknessFadePower, 0.01f));
	float halfThickness = lerp(safeBaseHalfThickness * safeFarThicknessRate, safeBaseHalfThickness, thicknessT);
	halfThickness = max(halfThickness, safeMinHalfThickness);

	return halfThickness * 2.0f;
}

float ComputeCellPixels(float2 worldXZ, float step) {

	float safeStep = max(step, 1e-6f);
	float2 coord = worldXZ / safeStep;
	float2 deriv = max(fwidth(coord), float2(1e-6f, 1e-6f));

	return 1.0f / max(max(deriv.x, deriv.y), 1e-6f);
}

float ComputeRepeatingGridCoverageRaw(float2 worldXZ, float step, float pixelWidth, float aaScale) {

	float safeStep = max(step, 1e-6f);

	float2 coord = worldXZ / safeStep;
	float2 deriv = max(fwidth(coord), float2(1e-6f, 1e-6f));
	float2 dist = abs(frac(coord - 0.5f) - 0.5f);

	float halfWidthPx = max(pixelWidth * 0.5f, 0.5f);
	float2 halfWidthCoord = deriv * halfWidthPx;
	float2 aa = deriv * aaScale;

	float lineX = 1.0f - SmootherStep(halfWidthCoord.x, halfWidthCoord.x + aa.x, dist.x);
	float lineZ = 1.0f - SmootherStep(halfWidthCoord.y, halfWidthCoord.y + aa.y, dist.y);

	return lineX + lineZ - lineX * lineZ;
}

float ComputeGridDensityFade(float cellPixels) {

	return SmootherStep(1.25f, 7.0f, cellPixels);
}

float ComputeAdaptiveAAScale(float cellPixels) {

	float t = SmootherStep(1.0f, 10.0f, cellPixels);
	return lerp(3.25f, 1.75f, t);
}

float ComputeCleanCrossFadedCoverage(float2 worldXZ, float step0, float step1, float blend, float pixelWidth) {

	float safeBlend = Smoother01(saturate(blend));

	float cellPixels0 = ComputeCellPixels(worldXZ, step0);
	float cellPixels1 = ComputeCellPixels(worldXZ, step1);

	float density0 = ComputeGridDensityFade(cellPixels0);
	float density1 = ComputeGridDensityFade(cellPixels1);

	float aaScale0 = ComputeAdaptiveAAScale(cellPixels0);
	float aaScale1 = ComputeAdaptiveAAScale(cellPixels1);

	float coverage0 = ComputeRepeatingGridCoverageRaw(worldXZ, step0, pixelWidth, aaScale0);
	float coverage1 = ComputeRepeatingGridCoverageRaw(worldXZ, step1, pixelWidth, aaScale1);

	float weighted0 = coverage0 * density0 * (1.0f - safeBlend);
	float weighted1 = coverage1 * density1 * safeBlend;

	return max(weighted0, weighted1);
}

float ComputeAxisCoverage(float coord, float pixelWidth) {

	float deriv = max(fwidth(coord), 1e-6f);

	float halfWidthPx = max(pixelWidth * 0.5f, 0.5f);
	float halfWidthCoord = deriv * halfWidthPx;
	float aa = deriv * 1.75f;

	return 1.0f - SmootherStep(halfWidthCoord, halfWidthCoord + aa, abs(coord));
}

void BlendLayer(inout float4 accumPremul, float3 rgb, float alpha) {

	alpha = saturate(alpha);
	float oneMinus = 1.0f - accumPremul.a;

	accumPremul.rgb += rgb * alpha * oneMinus;
	accumPremul.a += alpha * oneMinus;
}

//============================================================================
//	main
//============================================================================
PSOutput main(VSOutput input) {

	PSOutput output;
	
	output.color = float4(0.0f, 0.0f, 0.0f, 0.0f);
	output.depth = 1.0f;

	float2 safeViewport = max(viewportSize.xy, float2(1.0f, 1.0f));
	float2 uv = input.position.xy / safeViewport;
	float2 ndc = float2(uv.x * 2.0f - 1.0f, 1.0f - uv.y * 2.0f);

	float4 nearWorld = mul(float4(ndc, 0.0f, 1.0f), inverseViewProjectionMatrix);
	float4 farWorld = mul(float4(ndc, 1.0f, 1.0f), inverseViewProjectionMatrix);

	if (abs(nearWorld.w) < 1e-6f || abs(farWorld.w) < 1e-6f) {
		discard;
	}

	nearWorld /= nearWorld.w;
	farWorld /= farWorld.w;

	float3 cameraPosition = cameraPositionAndPlaneY.xyz;
	float gridPlaneY = cameraPositionAndPlaneY.w;

	float3 rayDirection = normalize(farWorld.xyz - nearWorld.xyz);
	float denom = rayDirection.y;

	// 地平線付近でplaneとほぼ平行
	if (abs(denom) < 1e-6f) {
		discard;
	}

	float t = (gridPlaneY - cameraPosition.y) / denom;
	if (t <= 0.0f) {
		discard;
	}

	float3 worldPos = cameraPosition + rayDirection * t;

	float4 gridClip = mul(float4(worldPos, 1.0f), viewProjectionMatrix);
	if (gridClip.w <= 1e-6f) {
		discard;
	}

	float gridDepth = gridClip.z / gridClip.w;
	if (gridDepth < 0.0f || 1.0f < gridDepth) {
		discard;
	}

	float distanceXZ = length(worldPos.xz - cameraPosition.xz);

	float horizonFade = SmootherStep(
	thicknessFadeAndHorizon.z,
	thicknessFadeAndHorizon.w,
	abs(rayDirection.y));
	
	float stepBlend = saturate(stepData1.w);

	float4 accumPremul = float4(0.0f, 0.0f, 0.0f, 0.0f);

	//============================================================================
	// minor
	//============================================================================
	{
		float fade = ComputeDistanceFade(distanceXZ, minorParams0.z, minorParams0.w, minorParams1.x) * horizonFade;
		float pixelWidth = ComputeEffectivePixelWidth(
			minorParams0.x,
			minorParams0.y,
			fade,
			thicknessFadeAndHorizon.x,
			thicknessFadeAndHorizon.y);

		float coverage = ComputeCleanCrossFadedCoverage(
			worldPos.xz,
			stepData0.x,
			stepData1.x,
			stepBlend,
			pixelWidth);

		float alpha = minorColor.a * fade * coverage;
		BlendLayer(accumPremul, minorColor.rgb, alpha);
	}

	//============================================================================
	// major
	//============================================================================
	{
		float fade = ComputeDistanceFade(distanceXZ, majorParams0.z, majorParams0.w, majorParams1.x) * horizonFade;
		float pixelWidth = ComputeEffectivePixelWidth(
			majorParams0.x,
			majorParams0.y,
			fade,
			thicknessFadeAndHorizon.x,
			thicknessFadeAndHorizon.y);

		float coverage = ComputeCleanCrossFadedCoverage(
			worldPos.xz,
			stepData0.y,
			stepData1.y,
			stepBlend,
			pixelWidth);

		float alpha = majorColor.a * fade * coverage;
		BlendLayer(accumPremul, majorColor.rgb, alpha);
	}

	//============================================================================
	// coarse
	//============================================================================
	{
		float fade = ComputeDistanceFade(distanceXZ, coarseParams0.z, coarseParams0.w, coarseParams1.x) * horizonFade;
		float pixelWidth = ComputeEffectivePixelWidth(
			coarseParams0.x,
			coarseParams0.y,
			fade,
			thicknessFadeAndHorizon.x,
			thicknessFadeAndHorizon.y);

		float coverage = ComputeCleanCrossFadedCoverage(
			worldPos.xz,
			stepData0.z,
			stepData1.z,
			stepBlend,
			pixelWidth);

		float alpha = coarseColor.a * fade * coverage;
		BlendLayer(accumPremul, coarseColor.rgb, alpha);
	}

	//============================================================================
	// axis
	//============================================================================
	{
		float axisVisibleDistance = max(axisParams.w, 1.0f);
		float axisFade = ComputeDistanceFade(distanceXZ, 0.0f, axisVisibleDistance, 1.0f) * horizonFade;
		float axisPixelWidth = max(axisParams.x * 2.0f, thicknessFadeAndHorizon.y * 2.0f);

		// z = 0 が X axis
		float axisXCoverage = ComputeAxisCoverage(worldPos.z, axisPixelWidth);
		float axisXAlpha = axisXColor.a * axisFade * axisXCoverage;
		BlendLayer(accumPremul, axisXColor.rgb, axisXAlpha);

		// x = 0 が Z axis
		float axisZCoverage = ComputeAxisCoverage(worldPos.x, axisPixelWidth);
		float axisZAlpha = axisZColor.a * axisFade * axisZCoverage;
		BlendLayer(accumPremul, axisZColor.rgb, axisZAlpha);
	}

	if (accumPremul.a <= (1.0f / 255.0f)) {
		discard;
	}

	output.color.a = accumPremul.a;
	output.color.rgb = accumPremul.rgb / max(accumPremul.a, 1e-6f);
	output.depth = gridDepth;

	return output;
}