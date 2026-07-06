#ifndef NEM_PRIMITIVE_HLSLI
#define NEM_PRIMITIVE_HLSLI

//============================================================================
//	Primitive 共有型
//	頂点はMeshVertexを共用し、描画とレイトレで同じバッファを読む
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

struct VSOutput {

	float4 position : SV_POSITION;
	float3 worldPos : TEXCOORD0;
	float3 normal : TEXCOORD1;
	float2 texcoord : TEXCOORD2;
	float3 tangent : TEXCOORD3;
	float tangentSign : TEXCOORD4;
	nointerpolation uint flags : TEXCOORD5;
};

#endif // NEM_PRIMITIVE_HLSLI
