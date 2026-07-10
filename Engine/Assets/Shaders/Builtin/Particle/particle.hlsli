#ifndef NEM_PARTICLE_HLSLI
#define NEM_PARTICLE_HLSLI

//============================================================================
//	Particle 共有型
//	頂点はMeshVertexを共用し、粒子ごとのワールド行列と色で描画する
//============================================================================
cbuffer ViewConstants : register(b0) {

	float4x4 viewProjection;
	float3 cameraPosition;
	float _viewPad0;
};

struct ParticleInstance {

	float4x4 worldMatrix;
	float4 color;
	// xyがUVスケール、zwがUVオフセット
	float4 uvScaleOffset;
	// 形状アニメーション用のパラメータ、形状ごとに解釈が変わる
	float4 shapeParams;
	// 発光色と強さ、wが強さ
	float4 emissive;
	// xがアルファ棄却の閾値、yzwは予約
	float4 materialParams;
};

struct VSOutput {

	float4 position : SV_POSITION;
	float2 texcoord : TEXCOORD0;
	float4 color : TEXCOORD1;
	float4 emissive : TEXCOORD2;
	float4 materialParams : TEXCOORD3;
};

#endif // NEM_PARTICLE_HLSLI
