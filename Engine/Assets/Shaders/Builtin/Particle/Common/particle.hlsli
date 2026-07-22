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
	// 形状アニメーション用のパラメータと断面色
	float4 shapeParams0;
	float4 shapeParams1;
	float4 topColor;
	float4 centerColor;
	float4 bottomColor;
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

float SmoothParticleCylinderProfile(float t, float weight, bool pullEnd) {

	float smoothT = t * t * (3.0f - 2.0f * t);
	float power = 1.0f + saturate(weight) * 3.0f;
	return pullEnd ? 1.0f - pow(1.0f - smoothT, power) : pow(smoothT, power);
}

float EvaluateParticleCylinderRadius(float heightT, ParticleGeometryData instance) {

	if (heightT <= 0.5f) {

		float t = SmoothParticleCylinderProfile(heightT * 2.0f, instance.shapeParams1.y, false);
		return lerp(instance.shapeParams0.z, instance.shapeParams0.y, t);
	}

	float t = SmoothParticleCylinderProfile((heightT - 0.5f) * 2.0f, instance.shapeParams1.x, true);
	return lerp(instance.shapeParams0.y, instance.shapeParams0.x, t);
}

float4 ResolveParticleVertexColor(float3 localPosition, ParticleGeometryData instance) {

	if (instance.shapeParams1.w < 0.5f) {
		return instance.vertexColor;
	}
	float height = max(abs(instance.shapeParams0.w), 0.00001f);
	float heightT = saturate(localPosition.y / height + 0.5f);
	if (heightT <= 0.5f) {

		float t = SmoothParticleCylinderProfile(heightT * 2.0f, instance.shapeParams1.y, false);
		return instance.vertexColor * lerp(instance.bottomColor, instance.centerColor, t);
	}

	float t = SmoothParticleCylinderProfile((heightT - 0.5f) * 2.0f, instance.shapeParams1.x, true);
	return instance.vertexColor * lerp(instance.centerColor, instance.topColor, t);
}

ParticleMaterialData GetParticleMaterial(VSOutput input) {

	if (input.particleIndex != 0xffffffffu) {
		return gParticleMaterials[input.particleIndex];
	}
	ParticleMaterialData material = (ParticleMaterialData) 0;
	return material;
}

float2 TransformParticleUV(float2 uv, ParticleMaterialData material) {

	if (material.materialParams.y != 0.0f) {
		uv.y = 1.0f - uv.y;
	}
	return mul(float4(uv, 0.0f, 1.0f), material.uvMatrix).xy;
}
#endif // NEM_PARTICLE_HLSLI