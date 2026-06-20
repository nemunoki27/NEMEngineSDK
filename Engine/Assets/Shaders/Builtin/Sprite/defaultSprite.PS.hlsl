//============================================================================
//	include
//============================================================================
#include "defaultSprite.hlsli"

//============================================================================
//	output
//============================================================================
struct PSOutput {

	float4 color : SV_TARGET0;
};

//============================================================================
//	resources
//============================================================================
Texture2D<float4> gTexture : register(t1);
SamplerState gSampler : register(s0);

struct PSInstance {
	
	float4 color;
	float4x4 uvMatrix;
};
StructuredBuffer<PSInstance> gPSInstances : register(t2);

//============================================================================
//	main
//============================================================================
PSOutput main(VSOutput input) {
	
	PSInstance instance = gPSInstances[input.instanceID];
	
	// UV座標を変換してテクスチャから色をサンプリング
	float4 transformUV = mul(float4(input.texcoord, 0.0f, 1.0f), instance.uvMatrix);
	float4 textureColor = gTexture.Sample(gSampler, transformUV.xy);
	
	PSOutput output;
	
	// 色を設定
	output.color.rgb = textureColor.rgb * instance.color.rgb;
	output.color.a = textureColor.a * instance.color.a;
	
	return output;
}