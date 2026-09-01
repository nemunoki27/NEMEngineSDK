#ifndef NEM_REFLECTION_FILTER_COMMON_HLSLI
#define NEM_REFLECTION_FILTER_COMMON_HLSLI

static const uint kReflectionFilterReceiveReflection = 1u << 4;

float3 DecodeGBufferNormal(float3 encodedNormal) {

	return normalize(encodedNormal * 2.0f - 1.0f);
}

uint2 MapPixelToTexture(uint2 pixel, uint2 outputSize, uint2 textureSize) {

	float2 uv = (float2(pixel) + 0.5f) / float2(outputSize);
	return min(uint2(uv * float2(textureSize)), textureSize - 1u);
}

float2 EncodeOctahedralNormal(float3 normal) {

	normal /= abs(normal.x) + abs(normal.y) + abs(normal.z);
	float2 encoded = normal.xy;
	if (normal.z < 0.0f) {
		encoded = (1.0f - abs(encoded.yx)) *
			float2(encoded.x >= 0.0f ? 1.0f : -1.0f,
				encoded.y >= 0.0f ? 1.0f : -1.0f);
	}
	return encoded * 0.5f + 0.5f;
}

float3 DecodeOctahedralNormal(float2 encoded) {

	float2 value = encoded * 2.0f - 1.0f;
	float3 normal = float3(value, 1.0f - abs(value.x) - abs(value.y));
	if (normal.z < 0.0f) {
		normal.xy = (1.0f - abs(normal.yx)) *
			float2(normal.x >= 0.0f ? 1.0f : -1.0f,
				normal.y >= 0.0f ? 1.0f : -1.0f);
	}
	return normalize(normal);
}

#endif // NEM_REFLECTION_FILTER_COMMON_HLSLI
