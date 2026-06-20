//============================================================================
//	include
//============================================================================
#include "defaultText.hlsli"

//============================================================================
//	input
//============================================================================
struct VSInput {
	
	float2 position : POSITION;
	float2 texcoord : TEXCOORD0;
};

//============================================================================
//	resources
//============================================================================
cbuffer ViewConstants : register(b0) {

	float4x4 viewProjection;
};

struct VSInstance {

	float2 rectMin;
	float2 rectMax;
	float2 uvMin;
	float2 uvMax;
	
	float4x4 worldMatrix;
};
StructuredBuffer<VSInstance> gVSInstances : register(t0);

//============================================================================
//	main
//============================================================================
VSOutput main(VSInput input, uint instanceID : SV_InstanceID) {

	VSInstance instance = gVSInstances[instanceID];

	// ワールドビュー行列を取得
	float4x4 wvp = mul(instance.worldMatrix, viewProjection);

	VSOutput output;
	
	// ローカル座標を計算
	float2 localPos = lerp(instance.rectMin, instance.rectMax, input.position);
	output.position = mul(float4(localPos, 0.0f, 1.0f), wvp);
	output.texcoord = lerp(instance.uvMin, instance.uvMax, input.texcoord);
	output.instanceID = instanceID;
	
	return output;
}