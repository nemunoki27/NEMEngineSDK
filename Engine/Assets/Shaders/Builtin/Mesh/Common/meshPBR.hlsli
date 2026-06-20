#ifndef NEM_MESH_PBR_HLSLI
#define NEM_MESH_PBR_HLSLI

//============================================================================
//	MeshのPBR共通定義
//	BRDFとライト評価とマテリアル解決を、GBuffer描画と前方半透明描画で共有する
//	defaultMesh.hlsli / meshLighting.hlsli / meshPBRMaterial.hlsli をincludeしてから読むこと
//	PI/kNoTexture/gSampler/ライト構造体/ComputeDistanceAttenuation/ComputeWorldNormalはmeshLighting.hlsli側に集約済み
//============================================================================

//============================================================================
//	PBR BRDF
//============================================================================
// GGX分布関数
float EvalD(float NdotH, float roughness) {

	float a = roughness * roughness;
	float a2 = a * a;
	float denom = NdotH * NdotH * (a2 - 1.0f) + 1.0f;
	return a2 / max(PI * denom * denom, 1e-7f);
}

// Smith幾何減衰 (GGX)
float EvalG1(float NdotX, float roughness) {

	float r = roughness + 1.0f;
	float k = (r * r) / 8.0f;
	return NdotX / max(NdotX * (1.0f - k) + k, 1e-7f);
}

float EvalG(float NdotV, float NdotL, float roughness) {

	return EvalG1(NdotV, roughness) * EvalG1(NdotL, roughness);
}

// Fresnel-Schlick近似
float3 FresnelSchlick(float cosTheta, float3 F0) {

	return F0 + (1.0f - F0) * pow(saturate(1.0f - cosTheta), 5.0f);
}

// ディズニーベース拡散反射
float3 DisneyDiffuse(float NdotL, float NdotV, float LdotH, float roughness, float3 albedo) {

	float energyBias = lerp(0.0f, 0.5f, roughness);
	float energyFactor = lerp(1.0f, 1.0f / 1.51f, roughness);
	float Fd90 = energyBias + 2.0f * LdotH * LdotH * roughness;
	float FL = 1.0f + (Fd90 - 1.0f) * pow(1.0f - NdotL, 5.0f);
	float FV = 1.0f + (Fd90 - 1.0f) * pow(1.0f - NdotV, 5.0f);
	return albedo * FL * FV * energyFactor / PI;
}

//============================================================================
//	テクスチャサンプル
//============================================================================
// bindless indexのテクスチャをサンプルする、未指定kNoTextureはfallbackValueを返す
float4 SamplePBRTexture(uint textureIndex, float2 uv, float4 fallbackValue) {

	if (textureIndex == kNoTexture) {
		return fallbackValue;
	}
	Texture2D<float4> tex = ResourceDescriptorHeap[NonUniformResourceIndex(textureIndex)];
	return tex.Sample(gSampler, uv);
}

//============================================================================
//	ライト評価
//============================================================================
// PBR平行光源
float3 EvaluatePBRDirectionalLight(DirectionalLight light, float3 N, float3 V,
	float3 albedo, float metallic, float roughness, float3 F0) {

	float3 L = normalize(-light.direction);
	float NdotL = saturate(dot(N, L));
	if (NdotL <= 0.0f) {
		return 0.0f.xxx;
	}

	float NdotV = saturate(dot(N, V));
	float3 H = normalize(V + L);
	float NdotH = saturate(dot(N, H));
	float HdotV = saturate(dot(H, V));
	float LdotH = saturate(dot(L, H));

	float3 F = FresnelSchlick(HdotV, F0);
	float D = EvalD(NdotH, roughness);
	float G = EvalG(NdotV, NdotL, roughness);

	float3 specular = D * G * F / max(4.0f * NdotV * NdotL, 1e-4f);
	float3 kD = (1.0f - F) * (1.0f - metallic);
	float3 diffuse = kD * DisneyDiffuse(NdotL, NdotV, LdotH, roughness, albedo);

	return (diffuse + specular) * NdotL * light.color.rgb * light.intensity;
}

// PBR点光源
float3 EvaluatePBRPointLight(PointLight light, float3 worldPos, float3 N, float3 V,
	float3 albedo, float metallic, float roughness, float3 F0) {

	float3 toLight = light.pos - worldPos;
	float dist = length(toLight);
	if (dist <= 1e-5f) {
		return 0.0f.xxx;
	}

	float3 L = toLight / dist;
	float NdotL = saturate(dot(N, L));
	if (NdotL <= 0.0f) {
		return 0.0f.xxx;
	}

	float attenuation = ComputeDistanceAttenuation(dist, light.radius, light.decay);
	if (attenuation <= 0.0f) {
		return 0.0f.xxx;
	}

	float NdotV = saturate(dot(N, V));
	float3 H = normalize(V + L);
	float NdotH = saturate(dot(N, H));
	float HdotV = saturate(dot(H, V));
	float LdotH = saturate(dot(L, H));

	float3 F = FresnelSchlick(HdotV, F0);
	float D = EvalD(NdotH, roughness);
	float G = EvalG(NdotV, NdotL, roughness);

	float3 specular = D * G * F / max(4.0f * NdotV * NdotL, 1e-4f);
	float3 kD = (1.0f - F) * (1.0f - metallic);
	float3 diffuse = kD * DisneyDiffuse(NdotL, NdotV, LdotH, roughness, albedo);

	return (diffuse + specular) * NdotL * light.color.rgb * light.intensity * attenuation;
}

// PBRスポットライト
float3 EvaluatePBRSpotLight(SpotLight light, float3 worldPos, float3 N, float3 V,
	float3 albedo, float metallic, float roughness, float3 F0) {

	float3 toLight = light.pos - worldPos;
	float dist = length(toLight);
	if (dist <= 1e-5f) {
		return 0.0f.xxx;
	}

	float3 L = toLight / dist;
	float NdotL = saturate(dot(N, L));
	if (NdotL <= 0.0f) {
		return 0.0f.xxx;
	}

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

	float NdotV = saturate(dot(N, V));
	float3 H = normalize(V + L);
	float NdotH = saturate(dot(N, H));
	float HdotV = saturate(dot(H, V));
	float LdotH = saturate(dot(L, H));

	float3 F = FresnelSchlick(HdotV, F0);
	float D = EvalD(NdotH, roughness);
	float G = EvalG(NdotV, NdotL, roughness);

	float3 specular = D * G * F / max(4.0f * NdotV * NdotL, 1e-4f);
	float3 kD = (1.0f - F) * (1.0f - metallic);
	float3 diffuse = kD * DisneyDiffuse(NdotL, NdotV, LdotH, roughness, albedo);

	return (diffuse + specular) * NdotL * light.color.rgb * light.intensity * distanceAttenuation * coneAttenuation;
}

//============================================================================
//	マテリアル解決
//	baseColor/metallic/roughness/ao/法線/発光をテクスチャとパラメータから解決する
//	GBuffer書き込みと前方ライティングで同じ解決を共有する
//============================================================================
struct ResolvedPBRMaterial {

	float4 baseColor;
	float3 N;
	float metallic;
	float roughness;
	float ao;
	float3 emissive;
};

ResolvedPBRMaterial ResolvePBRMaterial(VSOutput input) {

	SubMeshShaderData subMesh = GetInstanceSubMesh(input.instanceID, input.subMeshIndex);
	MeshMaterialParameters params = GetInstanceMeshMaterialParameters(input.instanceID, input.subMeshIndex);

	// UV変換
	float2 uv = mul(float4(input.uv, 0.0f, 1.0f), subMesh.uvMatrix).xy;

	// ベースカラー = マテリアル色 × ベースカラーテクスチャ
	float4 baseColor = SamplePBRTexture(params.baseColorTexture, uv, 1.0f.xxxx);
	baseColor *= params.color;

	// メタリックとラフネスは係数にmetallicRoughnessテクスチャを掛ける、glTF流でB=metallic G=roughness
	float4 mrSample = SamplePBRTexture(params.metallicRoughnessTexture, uv, 1.0f.xxxx);
	float metallic = saturate(params.Metallic * mrSample.b);
	float roughness = saturate(params.Roughness * mrSample.g);
	roughness = max(roughness, 0.04f);

	// AOはocclusionテクスチャから取る、未指定なら白で1になる
	float ao = SamplePBRTexture(params.occlusionTexture, uv, 1.0f.xxxx).r;

	// ワールド法線
	float3 N = ComputeWorldNormal(input, params.normalTexture, uv);

	// 発光、色×強度にテクスチャを掛ける、強度0で発光オフ
	float3 emissive = params.emissiveColor.rgb * params.emissiveIntensity;
	emissive *= SamplePBRTexture(params.emissiveTexture, uv, 1.0f.xxxx).rgb;

	ResolvedPBRMaterial m;
	m.baseColor = baseColor;
	m.N = N;
	m.metallic = metallic;
	m.roughness = roughness;
	m.ao = ao;
	m.emissive = emissive;
	return m;
}

// 解決済みマテリアルに全ライトのPBRライティングを合算する、半透明の前方描画で使う
// 不透明はGBufferへ書きDeferredのLightingPassで評価するため、ここは通らない
float3 EvaluateForwardPBRLighting(VSOutput input, ResolvedPBRMaterial m) {

	float3 V = normalize(renderCameraPos - input.worldPos);
	float3 F0 = lerp(0.04f.xxx, m.baseColor.rgb, m.metallic);

	float3 Lo = 0.0f.xxx;
	[loop]
	for (uint i = 0; i < directionalCount; ++i) {

		Lo += EvaluatePBRDirectionalLight(gDirectionalLights[i], m.N, V,
			m.baseColor.rgb, m.metallic, m.roughness, F0);
	}

	// ライトカリング廃止に伴い、点光源/スポットは全ライトを直接ループする
	[loop]
	for (uint pi = 0; pi < pointCount; ++pi) {

		Lo += EvaluatePBRPointLight(gPointLights[pi], input.worldPos, m.N, V,
			m.baseColor.rgb, m.metallic, m.roughness, F0);
	}
	[loop]
	for (uint si = 0; si < spotCount; ++si) {

		Lo += EvaluatePBRSpotLight(gSpotLights[si], input.worldPos, m.N, V,
			m.baseColor.rgb, m.metallic, m.roughness, F0);
	}

	// 環境光 (AOで減衰)
	float3 ambient = 0.03f * m.baseColor.rgb * m.ao;

	return Lo + ambient + m.emissive;
}

#endif // NEM_MESH_PBR_HLSLI
