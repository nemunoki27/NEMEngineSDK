//============================================================================
//	include
//============================================================================
#include "../Common/defaultMesh.hlsli"
#include "../Common/meshLighting.hlsli"
#include "../Common/meshLambert.hlsli"
#include "../Common/deferredGBuffer.hlsli"

//============================================================================
//	output
//============================================================================
struct TransparentPSOutput {

	float4 color : SV_TARGET0;
};

//============================================================================
//	main
//============================================================================
GBufferOutput main(VSOutput input) {

	SubMeshShaderData subMesh = GetInstanceSubMesh(input.instanceID, input.subMeshIndex);
	MeshMaterialParameters params = GetInstanceMeshMaterialParameters(input.instanceID, input.subMeshIndex);

	float2 uv = mul(float4(input.uv, 0.0f, 1.0f), subMesh.uvMatrix).xy;
	float4 baseColor = ResolveLambertBaseColor(params, uv);
	float3 N = ComputeWorldNormal(input, params.normalTexture, uv);

	// 発光はベースカラーと別にGBufferへ持たせ、ライティングの初期色に使う、色×強度で制御する
	float3 emissive = params.emissiveColor.rgb * params.emissiveIntensity;
	if (params.emissiveTexture != kNoTexture) {

		Texture2D<float4> emissiveTex = ResourceDescriptorHeap[NonUniformResourceIndex(params.emissiveTexture)];
		emissive *= emissiveTex.Sample(gSampler, uv).rgb;
	}

	MeshSurface surface;
	surface.albedo = baseColor.rgb;
	surface.normal = N;
	surface.worldPos = input.worldPos;
	surface.metallic = 0.0f;
	surface.roughness = 1.0f;
	surface.occlusion = 1.0f;
	surface.emissive = emissive;

	return EncodeGBuffer(surface);
}

//============================================================================
//	mainTransparent
//============================================================================
TransparentPSOutput mainTransparent(VSOutput input) {

	SubMeshShaderData subMesh = GetInstanceSubMesh(input.instanceID, input.subMeshIndex);
	MeshMaterialParameters params = GetInstanceMeshMaterialParameters(input.instanceID, input.subMeshIndex);

	float2 uv = mul(float4(input.uv, 0.0f, 1.0f), subMesh.uvMatrix).xy;
	float4 baseColor = ResolveLambertBaseColor(params, uv);
	float3 N = ComputeWorldNormal(input, params.normalTexture, uv);

	// 平行光源は影無し、そのあと点とスポット
	float3 lit = 0.0f.xxx;
	[loop]
	for (uint i = 0; i < directionalCount; ++i) {
		lit += EvaluateLambertDirectional(gDirectionalLights[i], N);
	}
	lit += AccumulateLocalLambertLighting(input.worldPos, N);

	TransparentPSOutput output;
	output.color = ComposeLambertColor(params, uv, baseColor, lit);
	return output;
}
