#ifndef NEM_PARTICLE_HLSLI
#define NEM_PARTICLE_HLSLI

//============================================================================
//	Particle hlsli
//============================================================================
cbuffer ViewConstants : register(b0) {

	float4x4 viewProjection;
	float3 cameraPosition;
	float _viewPad0;
};

struct ParticleGeometryData {

	float4x4 worldMatrix;
	float4 vertexColor;
	// 形状アニメーション用のパラメータ、形状ごとに解釈が変わる
	float4 shapeParams;
};

struct ParticleMaterialData {

	// 発光色と強さ、wが強さ
	float4 emissive;
	// xがアルファ棄却の閾値、yがScreen2D PlaneのV反転
	float4 materialParams;
	// フェーズマテリアルの寿命アニメーション色
	float4 materialColor;
	// カラーテクスチャのUV変換行列
	float4x4 uvMatrix;
};

StructuredBuffer<ParticleGeometryData> gParticleGeometry : register(t1);
StructuredBuffer<ParticleMaterialData> gParticleMaterials : register(t0, space1);

struct VSOutput {

	float4 position : SV_POSITION;
	float2 texcoord : TEXCOORD0;
	float4 vertexColor : COLOR0;
	nointerpolation uint particleIndex : PARTICLE_INDEX;
};

ParticleMaterialData GetParticleMaterial(VSOutput input) {

	if (input.particleIndex != 0xffffffffu) {
		return gParticleMaterials[input.particleIndex];
	}
	ParticleMaterialData material = (ParticleMaterialData)0;
	material.materialColor = 1.0f.xxxx;
	material.uvMatrix = float4x4(
		1.0f, 0.0f, 0.0f, 0.0f,
		0.0f, 1.0f, 0.0f, 0.0f,
		0.0f, 0.0f, 1.0f, 0.0f,
		0.0f, 0.0f, 0.0f, 1.0f);
	return material;
}

float2 TransformParticleUV(float2 uv, ParticleMaterialData material) {

	if (material.materialParams.y != 0.0f) {
		uv.y = 1.0f - uv.y;
	}
	return mul(float4(uv, 0.0f, 1.0f), material.uvMatrix).xy;
}

#endif // NEM_PARTICLE_HLSLI
