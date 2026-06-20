//============================================================================
//	include
//============================================================================
#include "defaultSprite.hlsli"

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

	float2 size;
	float2 pivot;
	
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
	
	// ピボットとサイズを考慮してローカル座標を計算
	float2 localPos = (input.position - instance.pivot) * instance.size;
	output.position = mul(float4(localPos, 0.0f, 1.0f), wvp);
	// 入力をそのまま返す
	output.texcoord = input.texcoord;
	output.instanceID = instanceID;

	return output;
}