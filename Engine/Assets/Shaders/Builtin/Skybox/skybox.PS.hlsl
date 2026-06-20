//============================================================================
//	input
//============================================================================
struct VSOutput {

	float4 position : SV_POSITION;
	float2 ndc : TEXCOORD0;
};

//============================================================================
//	resources
//============================================================================
cbuffer SkyboxConstants : register(b0) {

	float4x4 inverseViewProjection;
	float3 cameraPosition;
	uint cubemapIndex;
	float4 color;
};
SamplerState gSampler : register(s0);

//============================================================================
//	main
//============================================================================
float4 main(VSOutput input) : SV_TARGET0 {

	// 最遠面のNDCをワールドへ逆投影し視線方向を求める
	float4 farPoint = mul(float4(input.ndc, 1.0f, 1.0f), inverseViewProjection);
	float3 worldFar = farPoint.xyz / farPoint.w;
	float3 viewDir = normalize(worldFar - cameraPosition);

	// cubemapはbindlessで方向ベクトルからサンプルする
	TextureCube<float4> cube = ResourceDescriptorHeap[NonUniformResourceIndex(cubemapIndex)];
	float4 sampled = cube.SampleLevel(gSampler, viewDir, 0.0f);
	return sampled * color;
}
