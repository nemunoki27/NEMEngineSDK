#include "reflectionFilterCommon.hlsli"

cbuffer PostProcessFrameConstants : register(b0) {

	float2 resolution;
	float2 invResolution;
	float time;
	float deltaTime;
	uint frameIndex;
	float _framePad0;
	float cameraNear;
	float cameraFar;
	float2 _framePad1;
	float3 cameraWorldPos;
	float _framePad2;
	float4x4 cameraView;
	float4x4 cameraViewInverse;
	float4x4 cameraProjection;
	float4x4 cameraProjectionInverse;
};

cbuffer PostProcessParameters : register(b1) {

	float historyWeight;
	float positionThreshold;
	float motionRejectionScale;
	float _pad0;

	float normalThreshold;
	float historyClampSigma;
	float2 _pad1;

	float reflectionPositionThreshold;
	float3 _pad2;
};

Texture2D<float4> gSourceColor : register(t0);
Texture2D<float4> gHistoryColor : register(t1);
Texture2D<float> gSourceDepth : register(t2);
Texture2D<float4> gSourcePosition : register(t3);
Texture2D<float2> gSourceMotion : register(t4);
Texture2D<float4> gSourceNormal : register(t5);
Texture2D<float4> gHistoryGeometry : register(t6);
Texture2D<float2> gHistoryNormal : register(t7);
Texture2D<float4> gCurrentHitGeometry : register(t8);
Texture2D<float4> gHistoryHitGeometry : register(t9);
RWTexture2D<float4> gDestColor : register(u0);
RWTexture2D<float4> gHistoryGeometryOutput : register(u1);
RWTexture2D<float2> gHistoryNormalOutput : register(u2);
RWTexture2D<float4> gHistoryHitGeometryOutput : register(u3);

bool IsValidReflection(float4 color) {

	return color.a > 1e-4f && all(color == color) &&
		all(abs(color) < 65504.0f.xxxx);
}

bool ResolveHistory(float2 previousUV, uint2 outputSize,
	float3 worldPosition, float3 worldNormal, float positionLimit,
	float4 currentHitGeometry, out float4 historyColor) {

	historyColor = 0.0f.xxxx;
	if (any(previousUV < 0.0f.xx) || any(previousUV > 1.0f.xx)) {
		return false;
	}

	float2 historyPosition = previousUV * float2(outputSize) - 0.5f;
	int2 basePixel = int2(floor(historyPosition));
	float2 fractionValue = frac(historyPosition);
	float totalWeight = 0.0f;
	[unroll]
	for (int y = 0; y < 2; ++y) {
		[unroll]
		for (int x = 0; x < 2; ++x) {

			int2 samplePixel = basePixel + int2(x, y);
			if (any(samplePixel < int2(0, 0)) ||
				any(samplePixel >= int2(outputSize))) {
				continue;
			}
			float4 sampleColor = gHistoryColor.Load(int3(samplePixel, 0));
			float4 sampleGeometry =
				gHistoryGeometry.Load(int3(samplePixel, 0));
			float4 sampleHitGeometry =
				gHistoryHitGeometry.Load(int3(samplePixel, 0));
			if (!IsValidReflection(sampleColor) || sampleGeometry.a <= 0.0f) {
				continue;
			}
			bool currentHit = currentHitGeometry.w > 0.5f;
			bool historyHit = sampleHitGeometry.w > 0.5f;
			if (currentHit != historyHit ||
				(currentHit && distance(sampleHitGeometry.xyz,
					currentHitGeometry.xyz) > reflectionPositionThreshold)) {

				continue;
			}

			float positionError = distance(
				sampleGeometry.xyz, worldPosition);
			if (positionError > positionLimit) {
				continue;
			}
			float3 sampleNormal = DecodeOctahedralNormal(
				gHistoryNormal.Load(int3(samplePixel, 0)));
			float normalAgreement = dot(sampleNormal, worldNormal);
			if (normalAgreement < normalThreshold) {
				continue;
			}

			float2 bilinearAxis = 1.0f - abs(
				fractionValue - float2(x, y));
			float weight = bilinearAxis.x * bilinearAxis.y;
			weight *= 1.0f - smoothstep(
				positionLimit * 0.25f, positionLimit, positionError);
			weight *= smoothstep(normalThreshold, 1.0f, normalAgreement);
			historyColor += sampleColor * weight;
			totalWeight += weight;
		}
	}
	if (totalWeight <= 1e-4f) {
		return false;
	}
	historyColor /= totalWeight;
	return IsValidReflection(historyColor);
}

void ClampHistoryToNeighborhood(uint2 pixel, uint2 outputSize,
	uint2 geometrySize, float3 worldPosition, float3 worldNormal,
	float positionLimit, inout float3 historyColor) {

	float3 colorSum = 0.0f.xxx;
	float3 colorSquaredSum = 0.0f.xxx;
	uint validNeighborCount = 0u;
	[unroll]
	for (int y = -1; y <= 1; ++y) {
		[unroll]
		for (int x = -1; x <= 1; ++x) {

			int2 samplePixel = clamp(
				int2(pixel) + int2(x, y),
				int2(0, 0), int2(outputSize) - 1);
			float4 sampleColor = gSourceColor.Load(int3(samplePixel, 0));
			if (!IsValidReflection(sampleColor)) {
				continue;
			}

			uint2 sampleGeometry = MapPixelToTexture(
				uint2(samplePixel), outputSize, geometrySize);
			float3 samplePosition =
				gSourcePosition.Load(int3(sampleGeometry, 0)).xyz;
			float3 sampleNormal = DecodeGBufferNormal(
				gSourceNormal.Load(int3(sampleGeometry, 0)).xyz);
			float planeDistance = abs(dot(
				samplePosition - worldPosition, worldNormal));
			if (planeDistance > positionLimit * 2.0f ||
				dot(sampleNormal, worldNormal) < normalThreshold) {
				continue;
			}

			colorSum += sampleColor.rgb;
			colorSquaredSum += sampleColor.rgb * sampleColor.rgb;
			++validNeighborCount;
		}
	}
	if (validNeighborCount == 0u) {
		return;
	}

	float inverseCount = rcp(float(validNeighborCount));
	float3 mean = colorSum * inverseCount;
	float3 variance = max(
		colorSquaredSum * inverseCount - mean * mean, 0.0f.xxx);
	float3 deviation = sqrt(variance);
	float clampScale = max(historyClampSigma, 0.5f);
	float3 clampPadding = max(abs(mean) * 0.05f, 0.01f.xxx);
	historyColor = clamp(historyColor,
		mean - deviation * clampScale - clampPadding,
		mean + deviation * clampScale + clampPadding);
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
	uint2 geometryPixel = MapPixelToTexture(
		dispatchThreadID.xy, outputSize, geometrySize);
	float2 uv = (float2(dispatchThreadID.xy) + 0.5f) /
		float2(outputSize);
	float depth = gSourceDepth.Load(int3(geometryPixel, 0));
	float3 worldPosition =
		gSourcePosition.Load(int3(geometryPixel, 0)).xyz;
	float3 worldNormal = DecodeGBufferNormal(
		gSourceNormal.Load(int3(geometryPixel, 0)).xyz);
	float2 motion = gSourceMotion.Load(int3(geometryPixel, 0));
	float2 previousUV = uv - motion;

	float4 currentColor = gSourceColor.Load(int3(dispatchThreadID.xy, 0));
	float4 currentHitGeometry = gCurrentHitGeometry.Load(
		int3(dispatchThreadID.xy, 0));
	bool currentValid = IsValidReflection(currentColor);
	if (!currentValid) {
		// 現在画素が反射対象外なら過去の反射を持ち越さない
		gDestColor[dispatchThreadID.xy] = 0.0f.xxxx;
		gHistoryGeometryOutput[dispatchThreadID.xy] = float4(
			worldPosition, depth < 1.0f ? 1.0f : 0.0f);
		gHistoryNormalOutput[dispatchThreadID.xy] =
			EncodeOctahedralNormal(worldNormal);
		gHistoryHitGeometryOutput[dispatchThreadID.xy] =
			currentHitGeometry;
		return;
	}
	float positionLimit = max(positionThreshold,
		distance(worldPosition, cameraWorldPos) * 0.001f);
	float4 historyColor;
	bool historyValid = ResolveHistory(previousUV, outputSize,
		worldPosition, worldNormal, positionLimit,
		currentHitGeometry, historyColor);
	if (historyValid) {
		ClampHistoryToNeighborhood(dispatchThreadID.xy, outputSize,
			geometrySize, worldPosition, worldNormal,
			positionLimit, historyColor.rgb);
	}
	float motionAmount = length(motion * float2(geometrySize));
	float temporalWeight = historyValid ?
		saturate(historyWeight * exp(-motionAmount *
			max(motionRejectionScale, 0.0f))) : 0.0f;
	float4 filtered = currentColor;
	filtered.rgb = lerp(
		currentColor.rgb, historyColor.rgb, temporalWeight);
	gDestColor[dispatchThreadID.xy] = filtered;
	gHistoryGeometryOutput[dispatchThreadID.xy] = float4(
		worldPosition, depth < 1.0f ? 1.0f : 0.0f);
	gHistoryNormalOutput[dispatchThreadID.xy] =
		EncodeOctahedralNormal(worldNormal);
	gHistoryHitGeometryOutput[dispatchThreadID.xy] =
		currentHitGeometry;
}
