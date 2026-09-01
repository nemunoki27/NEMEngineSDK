#include "reflectionFilterCommon.hlsli"

cbuffer PostProcessParameters : register(b1) {

	float reflectionMaxRoughness;
	float reflectionRoughnessFade;
	float2 _pad0;
};

Texture2D<float4> gSourceColor : register(t0);
Texture2D<float4> gReflectionColor : register(t1);
Texture2D<float> gSourceDepth : register(t2);
Texture2D<float4> gSourceNormal : register(t3);
Texture2D<float4> gSourcePosition : register(t4);
Texture2D<float4> gSourceMaterial : register(t5);
Texture2D<uint> gSourceFlags : register(t6);
RWTexture2D<float4> gDestColor : register(u0);

bool IsValidReflection(float4 color) {

	return color.a > 1e-4f && all(color == color) &&
		all(abs(color) < 65504.0f.xxxx);
}

[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadID : SV_DispatchThreadID) {

	uint2 outputSize;
	gDestColor.GetDimensions(outputSize.x, outputSize.y);
	if (any(dispatchThreadID.xy >= outputSize)) {
		return;
	}

	uint2 reflectionSize;
	gReflectionColor.GetDimensions(reflectionSize.x, reflectionSize.y);
	float2 reflectionPosition =
		(float2(dispatchThreadID.xy) + 0.5f) /
		float2(outputSize) * float2(reflectionSize) - 0.5f;
	int2 basePixel = int2(floor(reflectionPosition));
	float2 fractionValue = frac(reflectionPosition);
	float centerDepth = gSourceDepth.Load(int3(dispatchThreadID.xy, 0));
	float4 sourceColor = gSourceColor.Load(int3(dispatchThreadID.xy, 0));
	if (centerDepth >= 1.0f) {
		gDestColor[dispatchThreadID.xy] = sourceColor;
		return;
	}
	uint surfaceFlags = gSourceFlags.Load(int3(dispatchThreadID.xy, 0));
	float roughness = clamp(gSourceMaterial.Load(
		int3(dispatchThreadID.xy, 0)).g, 0.04f, 1.0f);
	float roughnessFadeStart = max(
		reflectionMaxRoughness - reflectionRoughnessFade, 0.0f);
	float roughnessVisibility = 1.0f - smoothstep(
		roughnessFadeStart, reflectionMaxRoughness, roughness);
	if ((surfaceFlags & kReflectionFilterReceiveReflection) == 0u ||
		roughnessVisibility <= 0.0f) {

		gDestColor[dispatchThreadID.xy] = sourceColor;
		return;
	}
	float3 centerNormal = DecodeGBufferNormal(
		gSourceNormal.Load(int3(dispatchThreadID.xy, 0)).xyz);
	float3 centerPosition =
		gSourcePosition.Load(int3(dispatchThreadID.xy, 0)).xyz;

	float4 reflection = 0.0f.xxxx;
	float totalWeight = 0.0f;
	[unroll]
	for (int y = 0; y < 2; ++y) {
		[unroll]
		for (int x = 0; x < 2; ++x) {

			int2 samplePixel = clamp(basePixel + int2(x, y),
				int2(0, 0), int2(reflectionSize) - 1);
			uint2 geometryPixel = MapPixelToTexture(
				uint2(samplePixel), reflectionSize, outputSize);
			float sampleDepth = gSourceDepth.Load(int3(geometryPixel, 0));
			float3 sampleNormal = DecodeGBufferNormal(
				gSourceNormal.Load(int3(geometryPixel, 0)).xyz);
			float3 samplePosition =
				gSourcePosition.Load(int3(geometryPixel, 0)).xyz;
			float4 sampleReflection = gReflectionColor.Load(
				int3(samplePixel, 0));
			if (!IsValidReflection(sampleReflection)) {
				continue;
			}
			// 半解像度側の被覆率を現在画素のラフネス被覆率へ補正する
			float sampleVisibility = max(sampleReflection.a, 0.05f);
			sampleReflection.rgb *= roughnessVisibility / sampleVisibility;
			sampleReflection.a = roughnessVisibility;
			float2 bilinearAxis = 1.0f - abs(
				fractionValue - float2(x, y));
			float weight = bilinearAxis.x * bilinearAxis.y;
			weight *= exp(-abs(sampleDepth - centerDepth) * 160.0f);
			weight *= pow(saturate(dot(centerNormal, sampleNormal)), 24.0f);
			float planeDistance = abs(dot(
				samplePosition - centerPosition, centerNormal));
			weight *= exp(-planeDistance * 20.0f);
			reflection += sampleReflection * weight;
			totalWeight += weight;
		}
	}
	reflection = totalWeight > 1e-5f ?
		reflection / totalWeight : 0.0f.xxxx;
	gDestColor[dispatchThreadID.xy] = float4(
		sourceColor.rgb + reflection.rgb, sourceColor.a);
}
