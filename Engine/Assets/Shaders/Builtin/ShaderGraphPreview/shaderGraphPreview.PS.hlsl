//============================================================================
//	resources
//============================================================================
Texture2D<float4> gInput0 : register(t0);
Texture2D<float4> gInput1 : register(t1);
Texture2D<float4> gInput2 : register(t2);
Texture2D<float4> gInput3 : register(t3);

SamplerState gPreviewSampler : register(s0);

cbuffer PreviewConstants : register(b0) {

	uint operation;
	uint connectedMask;
	uint textureIndex;
	uint outputValueType;

	float4 literalValue;
	float4 inputDefault0;
	float4 inputDefault1;
	float4 inputDefault2;
	float4 inputDefault3;

	uint4 inputSwizzles;
	float4 timeValues;
};

//============================================================================
//	constants
//============================================================================
static const uint kInvalidTexture = 0xFFFFFFFF;

static const uint kValueFloat = 1;
static const uint kValueFloat2 = 2;
static const uint kValueFloat3 = 3;
static const uint kValueFloat4 = 4;
static const uint kValueColor = 5;
static const uint kValueTexture2D = 6;

static const uint kOperationValue = 0;
static const uint kOperationUV = 1;
static const uint kOperationWorldNormal = 2;
static const uint kOperationWorldPosition = 3;
static const uint kOperationAdd = 4;
static const uint kOperationSubtract = 5;
static const uint kOperationMultiply = 6;
static const uint kOperationDivide = 7;
static const uint kOperationPower = 8;
static const uint kOperationLerp = 9;
static const uint kOperationOneMinus = 10;
static const uint kOperationSaturate = 11;
static const uint kOperationSine = 12;
static const uint kOperationRemap = 13;
static const uint kOperationTilingAndOffset = 14;
static const uint kOperationPolarCoordinates = 15;
static const uint kOperationSplit = 16;
static const uint kOperationCombine = 17;
static const uint kOperationTextureSample = 18;
static const uint kOperationNormalUnpack = 19;
static const uint kOperationTextureValue = 20;
static const uint kOperationTime = 21;

static const uint kSwizzleIdentity = 0;
static const uint kSwizzleRGB = 1;
static const uint kSwizzleR = 2;
static const uint kSwizzleG = 3;
static const uint kSwizzleB = 4;
static const uint kSwizzleA = 5;
static const uint kSwizzleRG = 6;

//============================================================================
//	input
//============================================================================
struct VSOutput {

	float4 position : SV_Position;
	float2 uv : TEXCOORD0;
};

//============================================================================
//	functions
//============================================================================
float4 ApplySwizzle(float4 value, uint swizzle) {

	switch (swizzle) {
	case kSwizzleRGB:
		return float4(value.rgb, 1.0f);
	case kSwizzleR:
		return value.rrrr;
	case kSwizzleG:
		return value.gggg;
	case kSwizzleB:
		return value.bbbb;
	case kSwizzleA:
		return value.aaaa;
	case kSwizzleRG:
		return float4(value.rg, 0.0f, 1.0f);
	default:
		return value;
	}
}

float4 SampleInput(uint index, float2 uv) {

	switch (index) {
	case 0:
		return gInput0.SampleLevel(gPreviewSampler, uv, 0.0f);
	case 1:
		return gInput1.SampleLevel(gPreviewSampler, uv, 0.0f);
	case 2:
		return gInput2.SampleLevel(gPreviewSampler, uv, 0.0f);
	default:
		return gInput3.SampleLevel(gPreviewSampler, uv, 0.0f);
	}
}

float4 GetInputDefault(uint index) {

	switch (index) {
	case 0:
		return inputDefault0;
	case 1:
		return inputDefault1;
	case 2:
		return inputDefault2;
	default:
		return inputDefault3;
	}
}

float4 ReadInput(uint index, float2 uv) {

	if ((connectedMask & (1u << index)) == 0) {
		return GetInputDefault(index);
	}
	return ApplySwizzle(
		SampleInput(index, uv),
		inputSwizzles[index]);
}

float4 SampleTextureValue(float2 uv, float4 fallbackValue) {

	if (textureIndex == kInvalidTexture) {
		return fallbackValue;
	}
	Texture2D<float4> texture =
		ResourceDescriptorHeap[NonUniformResourceIndex(textureIndex)];
	return texture.SampleLevel(gPreviewSampler, uv, 0.0f);
}

float4 EvaluatePreview(float2 uv) {

	const float4 a = ReadInput(0, uv);
	const float4 b = ReadInput(1, uv);
	const float4 c = ReadInput(2, uv);
	const float4 d = ReadInput(3, uv);

	switch (operation) {
	case kOperationValue:
		return literalValue;
	case kOperationUV:
		return float4(uv, 0.0f, 1.0f);
	case kOperationWorldNormal: {
		const float2 xy = uv * 2.0f - 1.0f;
		const float z = sqrt(saturate(1.0f - dot(xy, xy)));
		return float4(normalize(float3(xy, z)), 1.0f);
	}
	case kOperationWorldPosition:
		return float4(uv * 2.0f - 1.0f, 0.0f, 1.0f);
	case kOperationAdd:
		return a + b;
	case kOperationSubtract:
		return a - b;
	case kOperationMultiply:
		return a * b;
	case kOperationDivide:
		return a / max(abs(b), 0.00001f);
	case kOperationPower:
		return pow(abs(a), b);
	case kOperationLerp:
		return lerp(a, b, c.x);
	case kOperationOneMinus:
		return 1.0f - a;
	case kOperationSaturate:
		return saturate(a);
	case kOperationSine:
		return sin(a);
	case kOperationRemap: {
		const float2 inputRange = b.xy;
		const float2 outputRange = c.xy;
		const float4 normalized =
			(a - inputRange.x) /
			max(abs(inputRange.y - inputRange.x), 0.00001f);
		return outputRange.x +
			normalized * (outputRange.y - outputRange.x);
	}
	case kOperationTilingAndOffset: {
		const float2 sourceUV =
			(connectedMask & 1u) != 0 ? a.xy : uv;
		return float4(
			sourceUV * b.xy + c.xy, 0.0f, 1.0f);
	}
	case kOperationPolarCoordinates: {
		const float2 sourceUV =
			(connectedMask & 1u) != 0 ? a.xy : uv;
		const float2 delta = sourceUV - b.xy;
		return float4(
			length(delta) * 2.0f * c.x,
			atan2(delta.x, delta.y) * 0.159154943f * d.x,
			0.0f, 1.0f);
	}
	case kOperationSplit:
		return a.rrrr;
	case kOperationCombine:
		return float4(a.x, b.x, c.x, d.x);
	case kOperationTextureSample: {
		const float2 sampleUV =
			(connectedMask & (1u << 1)) != 0 ?
				b.xy : uv;
		return SampleTextureValue(
			sampleUV, literalValue);
	}
	case kOperationNormalUnpack:
		return float4(
			normalize(a.xyz * 2.0f - 1.0f), 1.0f);
	case kOperationTextureValue:
		return SampleTextureValue(uv, literalValue);
	case kOperationTime:
		return timeValues.xxxx;
	default:
		return float4(1.0f, 0.0f, 1.0f, 1.0f);
	}
}

float4 BuildDisplayValue(float4 value) {

	switch (outputValueType) {
	case kValueFloat:
		return float4(value.xxx, 1.0f);
	case kValueFloat2:
		return float4(value.xy, 0.0f, 1.0f);
	case kValueFloat3:
		return float4(value.xyz, 1.0f);
	case kValueFloat4:
	case kValueColor:
	case kValueTexture2D:
		return value;
	default:
		return float4(value.rgb, 1.0f);
	}
}

//============================================================================
//	main
//============================================================================
float4 main(VSOutput input) : SV_TARGET0 {

	float4 output = BuildDisplayValue(
		EvaluatePreview(input.uv));
	if (operation == kOperationTime) {
		output = frac(output);
	}
	return output;
}
