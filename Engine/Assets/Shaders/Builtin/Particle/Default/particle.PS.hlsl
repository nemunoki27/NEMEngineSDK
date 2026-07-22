//============================================================================
//	include
//============================================================================
#include "../Common/particle.hlsli"

Texture2D<float4> baseColorTexture : register(t0, space2);
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

	ParticleMaterialData material = GetParticleMaterial(input);

	// UV
	float2 uv = TransformParticleUV(input.texcoord, material);
	// 色計算
	float4 baseColor = baseColorTexture.Sample(gSampler, uv) * input.vertexColor * material.materialColor;
	// アルファ棄却
	clip(baseColor.a - material.materialParams.x);
	// 発光加算
	baseColor.rgb += material.emissive.rgb * material.emissive.w;

	PSOutput output;
	output.color = baseColor;
	return output;
}