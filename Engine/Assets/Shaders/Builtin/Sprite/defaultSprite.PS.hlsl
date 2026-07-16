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
Texture2D<float4> baseColorTexture : register(t0, space2);
SamplerState gSampler : register(s0);

cbuffer MaterialParameters : register(b3) {

	float4 color;
};

struct PSInstance {

	float4x4 uvMatrix;
};
StructuredBuffer<PSInstance> gPSInstances : register(t2);

//============================================================================
//	main
//============================================================================
PSOutput main(VSOutput input) {

	PSInstance instance = gPSInstances[input.instanceID];

	float4 transformUV = mul(float4(input.texcoord, 0.0f, 1.0f), instance.uvMatrix);
	float4 textureColor = baseColorTexture.Sample(gSampler, transformUV.xy);

	PSOutput output;
	output.color = textureColor * color;

	return output;
}
