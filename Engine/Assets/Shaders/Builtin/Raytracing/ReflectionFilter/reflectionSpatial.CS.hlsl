#include "reflectionFilterCommon.hlsli"

cbuffer PostProcessParameters : register(b1) {

	float depthSigma;
	float normalPower;
	float hitDistanceSigma;
	float stepWidth;
	float colorSigma;
	float positionSigma;
	float2 _pad0;

	float antiFirefly;
	float fireflySigma;
	float fireflyMinLuminance;
	float _pad1;
};

Texture2D<float4> gSourceColor : register(t0);
Texture2D<float> gSourceDepth : register(t1);
Texture2D<float4> gSourceNormal : register(t2);
Texture2D<float> gReflectionHitDistance : register(t3);
Texture2D<float4> gSourcePosition : register(t4);
Texture2D<float4> gSourceMaterial : register(t5);
RWTexture2D<float4> gDestColor : register(u0);

static const float kATrousKernel[5] = {
	0.0625f, 0.25f, 0.375f, 0.25f, 0.0625f
};
static const float kMirrorRoughness = 0.08f;
static const float kDiffuseReflectionRoughness = 0.35f;

float Luminance(float3 color) {

	return dot(color, float3(0.2126f, 0.7152f, 0.0722f));
}

bool IsValidReflection(float4 color) {

	return color.a > 1e-4f && all(color == color) &&
		all(abs(color) < 65504.0f.xxxx);
}

float4 RemoveIsolatedFirefly(uint2 pixel, uint2 outputSize,
	uint2 geometrySize, float4 centerColor, float centerDepth,
	float3 centerNormal) {

	if (!IsValidReflection(centerColor)) {
		return 0.0f.xxxx;
	}

	float logLuminanceSum = 0.0f;
	float logLuminanceSquaredSum = 0.0f;
	uint validNeighborCount = 0u;
	[unroll]
	for (int y = -1; y <= 1; ++y) {
		[unroll]
		for (int x = -1; x <= 1; ++x) {

			if (x == 0 && y == 0) {
				continue;
			}
			int2 samplePixel = clamp(
				int2(pixel) + int2(x, y),
				int2(0, 0), int2(outputSize) - 1);
			float4 sampleColor = gSourceColor.Load(int3(samplePixel, 0));
			if (!IsValidReflection(sampleColor)) {
				continue;
			}

			uint2 sampleGeometry = MapPixelToTexture(
				uint2(samplePixel), outputSize, geometrySize);
			float sampleDepth = gSourceDepth.Load(int3(sampleGeometry, 0));
			float3 sampleNormal = DecodeGBufferNormal(
				gSourceNormal.Load(int3(sampleGeometry, 0)).xyz);
			if (abs(sampleDepth - centerDepth) > 0.005f ||
				dot(sampleNormal, centerNormal) < 0.85f) {
				continue;
			}

			float logLuminance = log2(
				1.0f + max(Luminance(sampleColor.rgb), 0.0f));
			logLuminanceSum += logLuminance;
			logLuminanceSquaredSum += logLuminance * logLuminance;
			++validNeighborCount;
		}
	}
	if (validNeighborCount < 3u) {
		return centerColor;
	}

	float inverseCount = rcp(float(validNeighborCount));
	float mean = logLuminanceSum * inverseCount;
	float variance = max(
		logLuminanceSquaredSum * inverseCount - mean * mean, 0.0f);
	float logLimit = mean + max(fireflySigma, 0.5f) * sqrt(variance);
	float luminanceLimit = max(
		exp2(logLimit) - 1.0f, max(fireflyMinLuminance, 0.0f));
	float centerLuminance = max(Luminance(centerColor.rgb), 0.0f);
	centerColor.rgb *= min(
		1.0f, luminanceLimit / max(centerLuminance, 1e-4f));
	return centerColor;
}

[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadID : SV_DispatchThreadID) {

	uint2 outputSize;
	gDestColor.GetDimensions(outputSize.x, outputSize.y);
	if (any(dispatchThreadID.xy >= outputSize)) {
		return;
	}

	uint2 geometrySize;
	gSourceDepth.GetDimensions(geometrySize.x, geometrySize.y);
	uint2 centerGeometry = MapPixelToTexture(
		dispatchThreadID.xy, outputSize, geometrySize);
	float centerDepth = gSourceDepth.Load(int3(centerGeometry, 0));
	float3 centerNormal = DecodeGBufferNormal(
		gSourceNormal.Load(int3(centerGeometry, 0)).xyz);
	float3 centerPosition = gSourcePosition.Load(
		int3(centerGeometry, 0)).xyz;
	float centerHitDistance = gReflectionHitDistance.Load(
		int3(dispatchThreadID.xy, 0));
	float4 centerColor = gSourceColor.Load(
		int3(dispatchThreadID.xy, 0));
	bool centerValid = IsValidReflection(centerColor);
	if (0.5f < antiFirefly) {

		gDestColor[dispatchThreadID.xy] = RemoveIsolatedFirefly(
			dispatchThreadID.xy, outputSize, geometrySize,
			centerColor, centerDepth, centerNormal);
		return;
	}
	// 無効画素は反射対象外なので近傍の有効反射を拡散しない
	if (!centerValid) {
		gDestColor[dispatchThreadID.xy] = 0.0f.xxxx;
		return;
	}
	float roughness = saturate(
		gSourceMaterial.Load(int3(centerGeometry, 0)).g);
	float filterAmount = smoothstep(
		kMirrorRoughness, kDiffuseReflectionRoughness, roughness);
	if (filterAmount <= 1e-4f) {
		gDestColor[dispatchThreadID.xy] = centerColor;
		return;
	}
	float centerLuminance = Luminance(centerColor.rgb);

	float4 accumulated = 0.0f.xxxx;
	float accumulatedWeight = 0.0f;
	int filterStep = max((int)round(stepWidth), 1);
	[unroll]
	for (int y = -2; y <= 2; ++y) {
		[unroll]
		for (int x = -2; x <= 2; ++x) {

			int2 samplePixel = clamp(
				int2(dispatchThreadID.xy) + int2(x, y) * filterStep,
				int2(0, 0), int2(outputSize) - 1);
			uint2 sampleGeometry = MapPixelToTexture(
				uint2(samplePixel), outputSize, geometrySize);
			float sampleDepth = gSourceDepth.Load(int3(sampleGeometry, 0));
			float3 sampleNormal = DecodeGBufferNormal(
				gSourceNormal.Load(int3(sampleGeometry, 0)).xyz);
			float3 samplePosition = gSourcePosition.Load(
				int3(sampleGeometry, 0)).xyz;
			float sampleHitDistance = gReflectionHitDistance.Load(
				int3(samplePixel, 0));
			float4 sampleColor = gSourceColor.Load(
				int3(samplePixel, 0));
			if (!IsValidReflection(sampleColor)) {
				continue;
			}
			float spatialWeight = kATrousKernel[x + 2] *
				kATrousKernel[y + 2];
			float depthWeight = exp(-abs(sampleDepth - centerDepth) *
				max(depthSigma, 1.0f));
			float normalWeight = pow(saturate(dot(
				centerNormal, sampleNormal)), max(normalPower, 1.0f));
			float positionWeight = exp(-distance(
				centerPosition, samplePosition) *
				max(positionSigma, 0.0f) / float(filterStep));
			float hitScale = max(max(centerHitDistance,
				sampleHitDistance), 1.0f);
			float hitWeight = centerValid ?
				exp(-abs(sampleHitDistance - centerHitDistance) /
					hitScale * max(hitDistanceSigma, 1.0f)) : 1.0f;
			float sampleLuminance = Luminance(sampleColor.rgb);
			float luminanceScale = max(max(abs(centerLuminance),
				abs(sampleLuminance)), 0.25f);
			float colorWeight = centerValid ? exp(-abs(
				sampleLuminance - centerLuminance) / luminanceScale *
				max(colorSigma, 0.0f)) : 1.0f;
			float weight = spatialWeight * depthWeight *
				normalWeight * positionWeight * hitWeight * colorWeight;
			accumulated += sampleColor * weight;
			accumulatedWeight += weight;
		}
	}
	float4 filteredColor = accumulatedWeight > 1e-5f ?
		accumulated / accumulatedWeight : centerColor;
	gDestColor[dispatchThreadID.xy] = lerp(
		centerColor, filteredColor, filterAmount);
}
