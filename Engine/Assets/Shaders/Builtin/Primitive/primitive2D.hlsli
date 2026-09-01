#ifndef NEM_PRIMITIVE2D_HLSLI
#define NEM_PRIMITIVE2D_HLSLI

//============================================================================
//	Primitive2D 共有型
//	頂点とインスタンスは3D描画と共用し、正射投影で前方描画する
//============================================================================
cbuffer ViewConstants : register(b0) {

	float4x4 viewProjection;
	float3 cameraPosition;
	float _viewPad0;
};

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
	uint2 _pad;
};
static const uint PRIMITIVE_INSTANCE_FLAG_FLIP_SCREEN_V = 1u << 5;

struct VSOutput {

	float4 position : SV_POSITION;
	float2 texcoord : TEXCOORD0;
	float2 localTexcoord : TEXCOORD1;
};

float2 ResolvePrimitive2DTexcoord(
	float2 uv,
	PrimitiveInstance instance) {

	if ((instance.flags &
		PRIMITIVE_INSTANCE_FLAG_FLIP_SCREEN_V) != 0u) {

		uv.y = 1.0f - uv.y;
	}
	return uv;
}

VSOutput BuildPrimitive2DVertexOutput(
	float3 localPosition,
	float2 uv,
	PrimitiveInstance instance) {

	VSOutput output;
	float4 worldPosition = mul(
		float4(localPosition, 1.0f),
		instance.worldMatrix);
	output.position = mul(worldPosition, viewProjection);
	output.localTexcoord = ResolvePrimitive2DTexcoord(
		uv, instance);
	output.texcoord = mul(
		float4(output.localTexcoord, 0.0f, 1.0f),
		instance.uvMatrix).xy;
	return output;
}

#endif // NEM_PRIMITIVE2D_HLSLI
