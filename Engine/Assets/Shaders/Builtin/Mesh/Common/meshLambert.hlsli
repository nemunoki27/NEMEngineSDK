#ifndef NEM_MESH_LAMBERT_HLSLI
#define NEM_MESH_LAMBERT_HLSLI

//============================================================================
//	ハーフランバート系の共有ライティング
//============================================================================

// N・Lを0..1へ寄せて2乗する、影側も緩く照らすトゥーン寄りの拡散
float HalfLambert(float3 N, float3 L) {

	float ndl = dot(N, L);
	float h = saturate(ndl * 0.5f + 0.5f);
	return h * h;
}

// シャドウ無しの平行光源、点/スポットと係数を揃えるため共通化する
float3 EvaluateLambertDirectional(DirectionalLight light, float3 N) {

	float3 L = normalize(-light.direction);
	float lambert = HalfLambert(N, L);
	return lambert * light.color.rgb * light.intensity;
}

float3 EvaluateLambertPoint(PointLight light, float3 worldPos, float3 N) {

	float3 toLight = light.pos - worldPos;
	float dist = length(toLight);
	if (dist <= 1e-5f) {
		return 0.0f.xxx;
	}

	float3 L = toLight / dist;
	float attenuation = ComputeDistanceAttenuation(dist, light.radius, light.decay);
	if (attenuation <= 0.0f) {
		return 0.0f.xxx;
	}

	float lambert = HalfLambert(N, L);
	return lambert * light.color.rgb * light.intensity * attenuation;
}

float3 EvaluateLambertSpot(SpotLight light, float3 worldPos, float3 N) {

	float3 toLight = light.pos - worldPos;
	float dist = length(toLight);
	if (dist <= 1e-5f) {
		return 0.0f.xxx;
	}

	float3 L = toLight / dist;
	float distanceAttenuation = ComputeDistanceAttenuation(dist, light.distance, light.decay);
	if (distanceAttenuation <= 0.0f) {
		return 0.0f.xxx;
	}

	float3 lightDir = normalize(light.direction);
	float cosTheta = dot(-L, lightDir);
	float coneRange = max(light.cosFalloffStart - light.cosAngle, 1e-4f);
	float coneAttenuation = saturate((cosTheta - light.cosAngle) / coneRange);
	coneAttenuation *= coneAttenuation;
	if (coneAttenuation <= 0.0f) {
		return 0.0f.xxx;
	}

	float lambert = HalfLambert(N, L);
	return lambert * light.color.rgb * light.intensity * distanceAttenuation * coneAttenuation;
}

// 点光源とスポットライトを全ライト集計する、平行光源はPS側で足す
float3 AccumulateLocalLambertLighting(float3 worldPos, float3 N) {

	float3 lit = 0.0f.xxx;

	[loop]
	for (uint i = 0; i < pointCount; ++i) {
		lit += EvaluateLambertPoint(gPointLights[i], worldPos, N);
	}
	[loop]
	for (uint i = 0; i < spotCount; ++i) {
		lit += EvaluateLambertSpot(gSpotLights[i], worldPos, N);
	}
	return lit;
}

// サブメッシュ単位マテリアルパラメータ、メンバ名と並びと16整列はCPU pack前提で変えない
struct MeshMaterialParameters {

	float4 color;
	float4 emissiveColor;

	uint baseColorTexture;
	uint normalTexture;
	uint emissiveTexture;
	float emissiveIntensity;
};
StructuredBuffer<MeshMaterialParameters> gMeshMaterialParameters : register(t0, space3);

// gSubMeshesと同じインスタンス×サブメッシュのindexで対応するパラメータを取り出す
MeshMaterialParameters GetInstanceMeshMaterialParameters(uint instanceID, uint localSubMeshIndex) {

	MeshInstance instance = gMeshInstances[instanceID];
	uint safeCount = max(instance.subMeshCount, 1u);
	uint clampedSubMeshIndex = min(localSubMeshIndex, safeCount - 1u);

	return gMeshMaterialParameters[instance.subMeshDataOffset + clampedSubMeshIndex];
}

// ベースカラー = マテリアル色 × ベースカラーテクスチャ
float4 ResolveLambertBaseColor(MeshMaterialParameters params, float2 uv) {

	float4 baseColor = 1.0f.xxxx;
	if (params.baseColorTexture != kNoTexture) {

		Texture2D<float4> baseColorTex = ResourceDescriptorHeap[NonUniformResourceIndex(params.baseColorTexture)];
		baseColor = baseColorTex.Sample(gSampler, uv);
	}
	baseColor *= params.color;
	return baseColor;
}

// 環境光+発光を加えて最終色を作る、litは平行光源と局所光源の合計
float4 ComposeLambertColor(MeshMaterialParameters params, float2 uv, float4 baseColor, float3 lit) {

	float3 ambient = 0.03f * baseColor.rgb;
	float3 emissive = params.emissiveColor.rgb * params.emissiveIntensity;
	if (params.emissiveTexture != kNoTexture) {

		Texture2D<float4> emissiveTex = ResourceDescriptorHeap[NonUniformResourceIndex(params.emissiveTexture)];
		emissive *= emissiveTex.Sample(gSampler, uv).rgb;
	}

	float3 finalColor = baseColor.rgb * lit + ambient + emissive;
	return float4(finalColor, baseColor.a);
}

#endif // NEM_MESH_LAMBERT_HLSLI
