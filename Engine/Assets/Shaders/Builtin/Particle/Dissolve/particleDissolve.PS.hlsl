//============================================================================
//	include
//============================================================================
#include "../Common/particle.hlsli"

struct ParticleCustomParameters {

	float dissolve;
	float edgeWidth;
	float2 noiseScale;
	float4 edgeColor;
};

StructuredBuffer<ParticleCustomParameters> gParticleCustomParameters : register(t1, space1);
Texture2D<float4> baseColorTexture : register(t0, space2);
Texture2D<float4> noiseTexture : register(t1, space2);
SamplerState gSampler : register(s0);

//============================================================================
//	output
//============================================================================
struct PSOutput {

	float4 color : SV_TARGET0;
};

//============================================================================
//	main
//============================================================================
PSOutput main(VSOutput input) {

	// マテリアルパラメータ取得
	ParticleMaterialData material = GetParticleMaterial(input);
	const float2 uv = TransformParticleUV(input.texcoord, material);
	// カスタムパラメータ
	ParticleCustomParameters custom = (ParticleCustomParameters) 0;
	if (input.particleIndex != 0xffffffffu) {
		custom = gParticleCustomParameters[input.particleIndex];
	}

	// テクスチャ色取得
	float4 textureColor = baseColorTexture.Sample(gSampler, uv);
	// ノイズカラー取得
	float noise = noiseTexture.Sample(gSampler, uv * custom.noiseScale).r;
	// ディスカード値
	float dissolveValue = textureColor.a * noise - custom.dissolve;
	clip(dissolveValue);

	const float edge = 1.0f - saturate(dissolveValue / max(custom.edgeWidth, 0.0001f));
	float4 result = textureColor * input.vertexColor * material.materialColor;
	result.rgb += custom.edgeColor.rgb * custom.edgeColor.a * edge;
	result.rgb += material.emissive.rgb * material.emissive.w;

	PSOutput output;
	output.color = result;
	return output;
}
