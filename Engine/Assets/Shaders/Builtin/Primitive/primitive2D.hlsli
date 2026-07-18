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
	float4x4 uvMatrix;
	uint flags;
	uint3 _pad;
};
static const uint PRIMITIVE_INSTANCE_FLAG_FLIP_SCREEN_V = 1u << 5;

struct VSOutput {

	float4 position : SV_POSITION;
	float2 texcoord : TEXCOORD0;
	float2 localTexcoord : TEXCOORD1;
};

#endif // NEM_PRIMITIVE2D_HLSLI
