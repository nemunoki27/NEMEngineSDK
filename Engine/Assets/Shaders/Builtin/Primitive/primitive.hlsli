#ifndef NEM_PRIMITIVE_HLSLI
#define NEM_PRIMITIVE_HLSLI

//============================================================================
//	Primitive 共有型
//	頂点はMeshVertexを共用し、描画とレイトレで同じバッファを読む
//============================================================================
cbuffer ViewConstants : register(b0) {

	float4x4 viewProjection;
	float4x4 previousViewProjection;
	float3 cameraPosition;
	uint frameSerial;
};
cbuffer MaterialParameters : register(b3) {

	float4 color;
	float4 emissiveColor;
	float metallic;
	float roughness;
	float emissiveIntensity;
	float displacementMidpoint;
	float displacementScale;
	float3 _materialPad0;
};
Texture2D<float4> baseColorTexture : register(t0, space2);
Texture2D<float4> metallicRoughnessTexture : register(t1, space2);
Texture2D<float4> occlusionTexture : register(t2, space2);
Texture2D<float4> emissiveTexture : register(t3, space2);
Texture2D<float4> normalTexture : register(t4, space2);
Texture2D<float4> metallicTexture : register(t5, space2);
Texture2D<float4> roughnessTexture : register(t6, space2);
Texture2D<float4> displacementTexture : register(t7, space2);

struct PrimitiveInstance {

	float4x4 worldMatrix;
	float4x4 previousWorldMatrix;
	float4x4 uvMatrix;
	float4 shapeParams0;
	float4 shapeParams1;
	float4 topColor;
	float4 centerColor;
	float4 bottomColor;
	uint flags;
	uint motionFrameSerial;
	uint entityIndex;
	uint entityGeneration;
};

float SmoothCylinderProfile(float t, float weight, bool pullEnd) {

	const float smoothT = t * t * (3.0f - 2.0f * t);
	const float power = 1.0f + saturate(weight) * 3.0f;
	return pullEnd ? 1.0f - pow(1.0f - smoothT, power) : pow(smoothT, power);
}

float4 ResolvePrimitiveVertexColor(float3 localPosition, PrimitiveInstance instance) {

	if (instance.shapeParams1.w < 0.5f) {
		return 1.0f.xxxx;
	}
	const float height = max(abs(instance.shapeParams0.w), 0.00001f);
	const float heightT = saturate(localPosition.y / height + 0.5f);
	if (heightT <= 0.5f) {

		const float t = SmoothCylinderProfile(heightT * 2.0f, instance.shapeParams1.y, false);
		return lerp(instance.bottomColor, instance.centerColor, t);
	}

	const float t = SmoothCylinderProfile((heightT - 0.5f) * 2.0f, instance.shapeParams1.x, true);
	return lerp(instance.centerColor, instance.topColor, t);
}

// VSとMSで共通使用する繰り返しバイリニアサンプル
float SamplePrimitiveDisplacement(float2 uv) {

	uint width;
	uint height;
	displacementTexture.GetDimensions(width, height);

	const int2 dimensions = int2(max(width, 1u), max(height, 1u));
	const float2 texelPosition = frac(uv) * float2(dimensions) - 0.5f;
	const int2 baseTexel = int2(floor(texelPosition));
	const float2 blend = frac(texelPosition);
	const int2 p00 = (baseTexel % dimensions + dimensions) % dimensions;
	const int2 p10 = ((baseTexel + int2(1, 0)) % dimensions + dimensions) % dimensions;
	const int2 p01 = ((baseTexel + int2(0, 1)) % dimensions + dimensions) % dimensions;
	const int2 p11 = ((baseTexel + int2(1, 1)) % dimensions + dimensions) % dimensions;

	const float top = lerp(
		displacementTexture.Load(int3(p00, 0)).r,
		displacementTexture.Load(int3(p10, 0)).r, blend.x);
	const float bottom = lerp(
		displacementTexture.Load(int3(p01, 0)).r,
		displacementTexture.Load(int3(p11, 0)).r, blend.x);
	return lerp(top, bottom, blend.y);
}

struct VSOutput {

	float4 position : SV_POSITION;
	float3 worldPos : TEXCOORD0;
	float3 normal : TEXCOORD1;
	float2 texcoord : TEXCOORD2;
	float3 tangent : TEXCOORD3;
	float tangentSign : TEXCOORD4;
	nointerpolation uint flags : TEXCOORD5;
	float4 vertexColor : COLOR0;
	float4 currentClipPosition : TEXCOORD6;
	float4 previousClipPosition : TEXCOORD7;
	nointerpolation uint entityIndex : TEXCOORD8;
	nointerpolation uint entityGeneration : TEXCOORD9;
};

VSOutput BuildPrimitiveVertexOutput(
	float3 localPosition,
	float3 localNormal,
	float3 localTangent,
	float tangentSign,
	float2 uv,
	float4 vertexColor,
	PrimitiveInstance instance) {

	VSOutput output;
	const float2 transformedUV = mul(
		float4(uv, 0.0f, 1.0f), instance.uvMatrix).xy;
	if (abs(displacementScale) > 0.000001f) {

		const float height = SamplePrimitiveDisplacement(transformedUV);
		localPosition += normalize(localNormal) *
			((height - displacementMidpoint) * displacementScale);
	}
	float4 worldPosition = mul(
		float4(localPosition, 1.0f),
		instance.worldMatrix);
	output.position = mul(worldPosition, viewProjection);
	output.currentClipPosition = output.position;
	float4x4 previousWorldMatrix =
		instance.motionFrameSerial == frameSerial ?
		instance.previousWorldMatrix : instance.worldMatrix;
	float4 previousWorldPosition = mul(
		float4(localPosition, 1.0f), previousWorldMatrix);
	output.previousClipPosition = mul(
		previousWorldPosition, previousViewProjection);
	output.worldPos = worldPosition.xyz;
	output.normal = normalize(mul(
		localNormal, (float3x3)instance.worldMatrix));
	output.tangent = normalize(mul(
		localTangent, (float3x3)instance.worldMatrix));
	output.tangentSign = tangentSign;
	output.texcoord = transformedUV;
	output.flags = instance.flags;
	output.vertexColor = vertexColor;
	output.entityIndex = instance.entityIndex;
	output.entityGeneration = instance.entityGeneration;
	return output;
}

#endif // NEM_PRIMITIVE_HLSLI
