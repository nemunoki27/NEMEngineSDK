//============================================================================
//	include
//============================================================================
#include "../FullscreenCopy/fullscreenCopy.hlsli"
#include "../Mesh/Common/deferredGBuffer.hlsli"
#include "../Common/pbrMath.hlsli"

//============================================================================
//	GBuffer入力
//============================================================================
Texture2D<float4> gAlbedo : register(t0);
Texture2D<float4> gNormal : register(t1);
Texture2D<float4> gWorldPos : register(t2);
Texture2D<float4> gMaterial : register(t3);
Texture2D<float4> gEmissive : register(t4);
Texture2D<uint> gFlags : register(t5);

SamplerState gSampler : register(s0);

//============================================================================
//	ライト
//============================================================================
// 平行光源
struct DirectionalLight {

	float4 color;

	float3 direction;
	float intensity;

	float shadowStrength;
	float shadowAngularRadius;
	float2 _pad1;
};
// 点光源
struct PointLight {

	float4 color;

	float3 pos;
	float intensity;

	float radius;
	float decay;
	float shadowStrength;
	float shadowRadius;
};
// スポットライト
struct SpotLight {

	float4 color;

	float3 direction;
	float intensity;

	float3 pos;
	float distance;

	float decay;
	float cosAngle;
	float cosFalloffStart;
	float shadowStrength;

	float shadowRadius;
	float3 _pad0;
};
// 矩形面光源
struct RectLight {

	float4 color;

	float3 direction;
	float intensity;

	float3 pos;
	float attenuationRadius;

	float3 right;
	float sourceWidth;

	float3 up;
	float sourceHeight;

	float decay;
	float barnDoorAngle;
	float barnDoorLength;
	float shadowStrength;
};
// ライト数
cbuffer LightCounts : register(b0) {

	uint directionalCount;
	uint pointCount;
	uint spotCount;
	uint rectCount;

	uint localCount;
	uint3 _lightCountPad;
};
StructuredBuffer<DirectionalLight> gDirectionalLights : register(t6);
StructuredBuffer<PointLight> gPointLights : register(t7);
StructuredBuffer<SpotLight> gSpotLights : register(t8);
StructuredBuffer<RectLight> gRectLights : register(t12);

struct LightClusterHeader {

	uint offset;
	uint count;
};
cbuffer LightClusterConstants : register(b2) {

	uint clusterTileCountX;
	uint clusterTileCountY;
	uint clusterZSliceCount;
	uint clusterTileSize;

	float clusterNearClip;
	float clusterFarClip;
	float clusterSliceScale;
	float clusterSliceBias;

	uint clusterCount;
	uint clusterMaxLights;
	uint2 _clusterPad;
};
StructuredBuffer<LightClusterHeader> gLightClusterHeaders : register(t9);
StructuredBuffer<uint> gLightClusterIndices : register(t11);

//============================================================================
//	ライティングパス定数
//============================================================================

cbuffer DeferredLightingConstants : register(b1) {

	float3 cameraPos;
	float ambientIntensity;

	float4x4 inverseViewProjection;
	float4x4 viewMatrix;

	float4 skyboxColor;

	uint skyboxCubemapIndex;
	uint hasSkybox;
	uint2 viewportSize;

	float shadowNormalBias;
	float shadowMaxDistance;
	// Skyboxから畳み込んだ放射照度cubemap、無い場合はkNoCubemap
	uint irradianceCubemapIndex;
	// 拡散IBL環境光の強さ
	float iblIntensity;

	uint softShadowSampleCount;
	uint3 _lightingPad0;
};

// 無効キューブマップインデックス
static const uint kNoCubemap = 0xFFFFFFFF;

//============================================================================
//	平行光源影
//============================================================================

RaytracingAccelerationStructure gSceneTLAS : register(t10);

// 影を落とすインスタンスのTLASマスク
static const uint kRaytracingMaskShadowCaster = 1u;
static const uint kMaximumSoftShadowSampleCount = 4u;
static const float2 kSoftShadowDisk[kMaximumSoftShadowSampleCount] = {
	float2(0.353553f, 0.000000f),
	float2(-0.451180f, 0.414030f),
	float2(0.068910f, -0.787560f),
	float2(0.569130f, 0.742260f)
};
static const float2 kRectLightSamples[kMaximumSoftShadowSampleCount] = {
	float2(-0.375f, -0.125f),
	float2(0.125f, -0.375f),
	float2(-0.125f, 0.375f),
	float2(0.375f, 0.125f)
};

uint HashShadowSeed(uint value) {

	value ^= 2747636419u;
	value *= 2654435769u;
	value ^= value >> 16u;
	value *= 2654435769u;
	value ^= value >> 16u;
	value *= 2654435769u;
	return value;
}

float ResolveShadowRotation(uint2 pixel, uint lightIndex) {

	uint seed = pixel.x * 1973u + pixel.y * 9277u +
		lightIndex * 26699u;
	return float(HashShadowSeed(seed)) *
		(6.28318530718f / 4294967295.0f);
}

float2 RotateShadowDisk(float2 samplePos, float sinRotation, float cosRotation) {

	return float2(
		samplePos.x * cosRotation - samplePos.y * sinRotation,
		samplePos.x * sinRotation + samplePos.y * cosRotation);
}

uint ResolveShadowSampleIndex(uint sampleIndex, uint sampleCount,
	uint2 pixel, uint lightIndex) {

	uint offset = HashShadowSeed(pixel.x * 1973u + pixel.y * 9277u +
		lightIndex * 26699u) & 3u;
	uint step = kMaximumSoftShadowSampleCount / sampleCount;
	return (offset + sampleIndex * step) & 3u;
}

void BuildShadowBasis(float3 direction, out float3 tangent, out float3 bitangent) {

	float3 up = abs(direction.y) < 0.999f ?
		float3(0.0f, 1.0f, 0.0f) : float3(1.0f, 0.0f, 0.0f);
	tangent = normalize(cross(up, direction));
	bitangent = cross(direction, tangent);
}

// 最初の遮蔽物で走査を終了する共通シャドウレイ
bool TraceShadowRay(float3 origin, float3 direction, float maxDistance) {

	RayDesc rayDesc;
	rayDesc.Origin = origin;
	rayDesc.Direction = direction;
	rayDesc.TMin = 0.001f;
	rayDesc.TMax = maxDistance;

	RayQuery <
		RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH |
		RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES > rayQuery;

	// CastShadow無効のインスタンスはマスクで除外される
	rayQuery.TraceRayInline(gSceneTLAS, 0, kRaytracingMaskShadowCaster, rayDesc);
	while (rayQuery.Proceed()) {
	}
	return rayQuery.CommittedStatus() == COMMITTED_TRIANGLE_HIT;
}

// 平行光源の見かけの角度内へ分散したレイから遮蔽率を返す
float TraceDirectionalShadow(float3 worldPos, float3 worldNormal,
	float3 lightDirection, float angularRadius, uint2 pixel, uint lightIndex) {

	float3 origin = worldPos + worldNormal * shadowNormalBias;
	float3 centerDirection = normalize(-lightDirection);
	if (angularRadius <= 0.0001f) {
		return TraceShadowRay(origin, centerDirection, shadowMaxDistance) ?
			1.0f : 0.0f;
	}

	float3 tangent;
	float3 bitangent;
	BuildShadowBasis(centerDirection, tangent, bitangent);

	float rotation = ResolveShadowRotation(pixel, lightIndex);
	float sinRotation;
	float cosRotation;
	sincos(rotation, sinRotation, cosRotation);

	float coneRadius = tan(radians(min(angularRadius, 5.0f)));
	uint sampleCount = clamp(softShadowSampleCount,
		1u, kMaximumSoftShadowSampleCount);
	if (sampleCount == 1u) {
		return TraceShadowRay(origin, centerDirection,
			shadowMaxDistance) ? 1.0f : 0.0f;
	}
	float occlusion = 0.0f;
	[loop]
	for (uint sampleIndex = 0u;
		sampleIndex < sampleCount; ++sampleIndex) {

		uint diskIndex = ResolveShadowSampleIndex(
			sampleIndex, sampleCount, pixel, lightIndex);
		float2 disk = RotateShadowDisk(
			kSoftShadowDisk[diskIndex], sinRotation, cosRotation);
		float3 direction = normalize(centerDirection +
			(tangent * disk.x + bitangent * disk.y) * coneRadius);
		occlusion += TraceShadowRay(
			origin, direction, shadowMaxDistance) ? 1.0f : 0.0f;
	}
	return occlusion / float(sampleCount);
}

//============================================================================
//	点光源影
//============================================================================

// ローカルライトを円形面光源として遮蔽率を返す
float TraceLocalSoftShadow(float3 worldPos, float3 worldNormal,
	float3 toLight, float distToLight, float sourceRadius,
	uint2 pixel, uint lightIndex) {

	float3 origin = worldPos + worldNormal * shadowNormalBias;
	float3 centerDirection = toLight / distToLight;
	if (sourceRadius <= 0.0001f) {
		return TraceShadowRay(origin, centerDirection, distToLight) ?
			1.0f : 0.0f;
	}

	float3 tangent;
	float3 bitangent;
	BuildShadowBasis(centerDirection, tangent, bitangent);

	float rotation = ResolveShadowRotation(pixel, lightIndex);
	float sinRotation;
	float cosRotation;
	sincos(rotation, sinRotation, cosRotation);

	uint sampleCount = clamp(softShadowSampleCount,
		1u, kMaximumSoftShadowSampleCount);
	if (sampleCount == 1u) {
		return TraceShadowRay(origin, centerDirection,
			distToLight) ? 1.0f : 0.0f;
	}
	float occlusion = 0.0f;
	[loop]
	for (uint sampleIndex = 0u;
		sampleIndex < sampleCount; ++sampleIndex) {

		uint diskIndex = ResolveShadowSampleIndex(
			sampleIndex, sampleCount, pixel, lightIndex);
		float2 disk = RotateShadowDisk(
			kSoftShadowDisk[diskIndex], sinRotation, cosRotation);
		float3 sampleToLight = toLight +
			(tangent * disk.x + bitangent * disk.y) * sourceRadius;
		float sampleDistance = length(sampleToLight);
		occlusion += TraceShadowRay(origin,
			sampleToLight / sampleDistance, sampleDistance) ? 1.0f : 0.0f;
	}
	return occlusion / float(sampleCount);
}

float3 GetRectLightSamplePosition(RectLight light,
	float2 sampleUV) {

	return light.pos +
		light.right * (sampleUV.x * max(light.sourceWidth, 0.0f)) +
		light.up * (sampleUV.y * max(light.sourceHeight, 0.0f));
}

// 矩形面上の複数点へレイを飛ばして面積に応じた遮蔽率を返す
float TraceRectShadow(float3 worldPos, float3 worldNormal,
	RectLight light, uint2 pixel, uint lightIndex) {

	float3 origin = worldPos + worldNormal * shadowNormalBias;
	if (light.sourceWidth <= 0.0001f &&
		light.sourceHeight <= 0.0001f) {

		float3 toLight = light.pos - origin;
		float distanceToLight = length(toLight);
		if (distanceToLight <= 1e-5f) {
			return 0.0f;
		}
		return TraceShadowRay(origin,
			toLight / distanceToLight,
			distanceToLight) ? 1.0f : 0.0f;
	}

	uint seed = HashShadowSeed(
		pixel.x * 1973u + pixel.y * 9277u +
		lightIndex * 26699u);
	float2 sampleSign = float2(
		(seed & 1u) != 0u ? -1.0f : 1.0f,
		(seed & 2u) != 0u ? -1.0f : 1.0f);

	uint sampleCount = clamp(softShadowSampleCount,
		1u, kMaximumSoftShadowSampleCount);
	if (sampleCount == 1u) {
		float3 toLight = light.pos - origin;
		float distanceToLight = length(toLight);
		return distanceToLight > 1e-5f &&
			TraceShadowRay(origin, toLight / distanceToLight,
				distanceToLight) ? 1.0f : 0.0f;
	}
	float occlusion = 0.0f;
	[loop]
	for (uint sampleIndex = 0u;
		sampleIndex < sampleCount; ++sampleIndex) {

		uint rectSampleIndex = ResolveShadowSampleIndex(
			sampleIndex, sampleCount, pixel, lightIndex);
		float2 sampleUV =
			kRectLightSamples[rectSampleIndex] * sampleSign;
		float3 samplePos =
			GetRectLightSamplePosition(light, sampleUV);
		float3 toLight = samplePos - origin;
		float distanceToLight = length(toLight);
		if (distanceToLight <= 1e-5f) {
			continue;
		}
		occlusion += TraceShadowRay(origin,
			toLight / distanceToLight,
			distanceToLight) ? 1.0f : 0.0f;
	}
	return occlusion / float(sampleCount);
}

//============================================================================
//	PBR lighting
//============================================================================
float ComputeDistanceAttenuation(float dist, float range, float decay) {

	if (range <= 0.0001f || dist >= range) {
		return 0.0f;
	}

	float x = saturate(dist / range);
	float smooth = 1.0f - x * x;
	smooth *= smooth;

	float d = max(decay, 0.0f);
	float distanceFalloff = 1.0f / max(pow(max(dist, 1.0f), d), 1.0f);

	return smooth * distanceFalloff;
}

// バーンドアで矩形外側へ広がる光の範囲と境界の鋭さを制御する
float ComputeRectBarnAttenuation(RectLight light, float3 worldPos) {

	float3 fromLight = worldPos - light.pos;
	float forward = dot(fromLight, light.direction);
	if (forward <= 0.0f) {
		return 0.0f;
	}
	if (light.barnDoorLength <= 0.0001f) {
		return 1.0f;
	}

	float spread = tan(radians(clamp(
		light.barnDoorAngle, 0.0f, 89.0f))) * forward;
	float widthLimit = max(light.sourceWidth, 0.0f) * 0.5f + spread;
	float heightLimit = max(light.sourceHeight, 0.0f) * 0.5f + spread;
	float lateralX = abs(dot(fromLight, light.right));
	float lateralY = abs(dot(fromLight, light.up));
	float edgeSoftness = max(
		forward / (1.0f + light.barnDoorLength * 4.0f), 0.001f);

	float widthAttenuation =
		1.0f - smoothstep(widthLimit, widthLimit + edgeSoftness, lateralX);
	float heightAttenuation =
		1.0f - smoothstep(heightLimit, heightLimit + edgeSoftness, lateralY);
	return widthAttenuation * heightAttenuation;
}

float3 EvaluatePBRLight(float3 N, float3 V, float3 L, float3 radiance,
	float3 albedo, float metallic, float roughness, float3 F0) {

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

	return (diffuse + specular) * NdotL * radiance;
}
float3 Square(float3 value) {
	return value * value;
}

float3 EvaluatePointLightIndex(uint lightIndex,
	float3 worldPos, float3 N, float3 V,
	float3 albedo, float metallic, float roughness, float3 F0,
	uint flags, bool useShadow, uint2 pixel) {

	PointLight light = gPointLights[lightIndex];
	float3 toLight = light.pos - worldPos;
	float dist = length(toLight);
	if (dist <= 1e-5f) {
		return 0.0f.xxx;
	}
	float attenuation =
		ComputeDistanceAttenuation(dist, light.radius, light.decay);
	if (attenuation <= 0.0f) {
		return 0.0f.xxx;
	}
	float3 L = toLight / dist;
	float shadow = 1.0f;
	if (useShadow && light.shadowStrength > 0.0f &&
		(flags & kMaterialFlagReceiveShadow) != 0u) {
		float occlusion = TraceLocalSoftShadow(worldPos, N, toLight, dist,
			light.shadowRadius, pixel, lightIndex);
		shadow = 1.0f - occlusion * light.shadowStrength;
	}
	float3 radiance =
		light.color.rgb * light.intensity * attenuation * shadow;
	return EvaluatePBRLight(
		N, V, L, radiance, albedo, metallic, roughness, F0);
}

float3 EvaluateSpotLightIndex(uint lightIndex,
	float3 worldPos, float3 N, float3 V,
	float3 albedo, float metallic, float roughness, float3 F0,
	uint flags, bool useShadow, uint2 pixel) {

	SpotLight light = gSpotLights[lightIndex];
	float3 toLight = light.pos - worldPos;
	float dist = length(toLight);
	if (dist <= 1e-5f) {
		return 0.0f.xxx;
	}
	float distanceAttenuation =
		ComputeDistanceAttenuation(dist, light.distance, light.decay);
	if (distanceAttenuation <= 0.0f) {
		return 0.0f.xxx;
	}
	float3 L = toLight / dist;
	float3 lightDir = normalize(light.direction);
	float cosTheta = dot(-L, lightDir);
	float coneRange =
		max(light.cosFalloffStart - light.cosAngle, 1e-4f);
	float coneAttenuation =
		saturate((cosTheta - light.cosAngle) / coneRange);
	coneAttenuation *= coneAttenuation;
	if (coneAttenuation <= 0.0f) {
		return 0.0f.xxx;
	}
	float shadow = 1.0f;
	if (useShadow && light.shadowStrength > 0.0f &&
		(flags & kMaterialFlagReceiveShadow) != 0u) {
		float occlusion = TraceLocalSoftShadow(worldPos, N, toLight, dist,
			light.shadowRadius, pixel, pointCount + lightIndex);
		shadow = 1.0f - occlusion * light.shadowStrength;
	}
	float3 radiance = light.color.rgb * light.intensity *
		distanceAttenuation * coneAttenuation * shadow;
	return EvaluatePBRLight(
		N, V, L, radiance, albedo, metallic, roughness, F0);
}

float3 EvaluateRectLightIndex(uint lightIndex,
	float3 worldPos, float3 N, float3 V,
	float3 albedo, float metallic, float roughness, float3 F0,
	uint flags, bool useShadow, uint2 pixel) {

	RectLight light = gRectLights[lightIndex];
	float centerDistance = length(light.pos - worldPos);
	float attenuation = ComputeDistanceAttenuation(
		centerDistance, light.attenuationRadius, light.decay);
	float barnAttenuation =
		ComputeRectBarnAttenuation(light, worldPos);
	if (attenuation <= 0.0f || barnAttenuation <= 0.0f) {
		return 0.0f.xxx;
	}

	float shadow = 1.0f;
	if (useShadow && light.shadowStrength > 0.0f &&
		(flags & kMaterialFlagReceiveShadow) != 0u) {

		float occlusion = TraceRectShadow(
			worldPos, N, light, pixel,
			pointCount + spotCount + lightIndex);
		shadow = 1.0f - occlusion * light.shadowStrength;
	}

	float3 result = 0.0f.xxx;
	[unroll]
	for (uint sampleIndex = 0u;
		sampleIndex < kMaximumSoftShadowSampleCount; ++sampleIndex) {

		float3 samplePos = GetRectLightSamplePosition(
			light, kRectLightSamples[sampleIndex]);
		float3 toLight = samplePos - worldPos;
		float sampleDistance = length(toLight);
		if (sampleDistance <= 1e-5f) {
			continue;
		}

		float3 L = toLight / sampleDistance;
		float sourceFacing =
			saturate(dot(-L, light.direction));
		float3 radiance = light.color.rgb * light.intensity *
			attenuation * barnAttenuation * sourceFacing * shadow;
		result += EvaluatePBRLight(
			N, V, L, radiance, albedo, metallic, roughness, F0);
	}
	return result / float(kMaximumSoftShadowSampleCount);
}

bool ResolveLightCluster(int2 pixel, float3 worldPos,
	out LightClusterHeader header) {

	header.offset = 0;
	header.count = 0;
	if (clusterCount == 0u || clusterTileCountX == 0u ||
		clusterTileCountY == 0u || clusterZSliceCount == 0u) {
		return false;
	}

	uint2 tile = min(
		uint2(max(pixel, int2(0, 0))) / max(clusterTileSize, 1u),
		uint2(clusterTileCountX - 1u, clusterTileCountY - 1u));
	float viewDepth = mul(float4(worldPos, 1.0f), viewMatrix).z;
	uint zSlice = (uint)clamp(
		floor(log2(max(viewDepth, clusterNearClip)) *
			clusterSliceScale + clusterSliceBias),
		0.0f, float(clusterZSliceCount - 1u));
	uint clusterIndex =
		(zSlice * clusterTileCountY + tile.y) *
		clusterTileCountX + tile.x;
	if (clusterCount <= clusterIndex) {
		return false;
	}
	header = gLightClusterHeaders[clusterIndex];
	return true;
}

//============================================================================
//	背景、スカイボックス
//============================================================================

float3 SampleBackground(float2 texcoord) {

	// スカイボックスが無効なら処理しない、色をそのまま返す
	if (hasSkybox == 0u || skyboxCubemapIndex == kNoCubemap) {
		return skyboxColor.rgb;
	}

	// 入力テクスチャ座標からNDCを作ってinverseViewProjectionでワールド方向を復元
	float2 ndc = float2(texcoord.x * 2.0f - 1.0f, 1.0f - texcoord.y * 2.0f);
	float4 worldFar = mul(float4(ndc, 1.0f, 1.0f), inverseViewProjection);
	float3 direction = normalize(worldFar.xyz / worldFar.w - cameraPos);

	// キューブマップテクスチャ取得
	TextureCube<float4> cubemap = ResourceDescriptorHeap[NonUniformResourceIndex(skyboxCubemapIndex)];
	return cubemap.SampleLevel(gSampler, direction, 0.0f).rgb * skyboxColor.rgb;
}

//============================================================================
//	全ピクセルのマテリアル計算
//============================================================================
float4 ResolvePixel(VSOutput input, bool useShadow) {

	int3 pixel = int3(input.position.xy, 0);

	// サーフェスが無いピクセルは背景
	uint flags = gFlags.Load(pixel);
	if ((flags & kMaterialFlagSurface) == 0u) {
		return float4(SampleBackground(input.texcoord), 1.0f);
	}
	// GBufferデータ取得
	float3 albedo = gAlbedo.Load(pixel).rgb;
	float3 N = normalize(gNormal.Load(pixel).xyz * 2.0f - 1.0f);
	float3 worldPos = gWorldPos.Load(pixel).xyz;
	float4 material = gMaterial.Load(pixel);
	float metallic = material.r;
	float roughness = max(material.g, 0.04f);
	float ao = material.b;
	float3 emissive = gEmissive.Load(pixel).rgb;

	// ライティングしないサーフェイスはアルベドと発光をそのまま出す
	if ((flags & kMaterialFlagLighting) == 0u) {
		return float4(albedo + emissive, 1.0f);
	}

	float3 V = normalize(cameraPos - worldPos);
	float3 F0 = lerp(0.04f.xxx, albedo, metallic);

	float3 Lo = 0.0f.xxx;

	// 平行光源
	[loop]
	for (uint di = 0; di < directionalCount; ++di) {

		DirectionalLight light = gDirectionalLights[di];
		float3 L = normalize(-light.direction);
		// 影計算を行うか、影を受けないサーフェイスもスキップして1.0fのまま使う
		float shadow = 1.0f;
		if (useShadow && light.shadowStrength > 0.0f &&
			(flags & kMaterialFlagReceiveShadow) != 0u) {

			float occlusion = TraceDirectionalShadow(worldPos, N,
				light.direction, light.shadowAngularRadius, pixel.xy, di);
			shadow = 1.0f - occlusion * light.shadowStrength;
		}
		float3 radiance = light.color.rgb * light.intensity * shadow;
		Lo += EvaluatePBRLight(N, V, L, radiance, albedo, metallic, roughness, F0);
	}
	// ローカルライトは現在ピクセルが属するクラスターの索引だけを走査する
	LightClusterHeader clusterHeader;
	if (ResolveLightCluster(pixel.xy, worldPos, clusterHeader)) {
		[loop]
		for (uint clusterLight = 0;
			clusterLight < clusterHeader.count; ++clusterLight) {

			uint localIndex =
				gLightClusterIndices[clusterHeader.offset + clusterLight];
			if (localIndex < pointCount) {
				Lo += EvaluatePointLightIndex(localIndex,
					worldPos, N, V, albedo, metallic,
					roughness, F0, flags, useShadow, pixel.xy);
			} else {
				uint spotIndex = localIndex - pointCount;
				if (spotIndex < spotCount) {
					Lo += EvaluateSpotLightIndex(spotIndex,
						worldPos, N, V, albedo, metallic,
						roughness, F0, flags, useShadow, pixel.xy);
				} else {
					uint rectIndex = spotIndex - spotCount;
					if (rectIndex < rectCount) {
						Lo += EvaluateRectLightIndex(rectIndex,
							worldPos, N, V, albedo, metallic,
							roughness, F0, flags, useShadow, pixel.xy);
					}
				}
			}
		}
	} else {
		// 透視カメラを持たないビューでは従来通り全ローカルライトを評価する
		[loop]
		for (uint pi = 0; pi < pointCount; ++pi) {
			Lo += EvaluatePointLightIndex(pi,
				worldPos, N, V, albedo, metallic,
				roughness, F0, flags, useShadow, pixel.xy);
		}
		[loop]
		for (uint si = 0; si < spotCount; ++si) {
			Lo += EvaluateSpotLightIndex(si,
				worldPos, N, V, albedo, metallic,
				roughness, F0, flags, useShadow, pixel.xy);
		}
		[loop]
		for (uint ri = 0; ri < rectCount; ++ri) {
			Lo += EvaluateRectLightIndex(ri,
				worldPos, N, V, albedo, metallic,
				roughness, F0, flags, useShadow, pixel.xy);
		}
	}

	// 環境光はAOで減衰、環境光を受けないサーフェイスは加算しない
	float3 ambient = 0.0f.xxx;
	if ((flags & kMaterialFlagReceiveIBL) != 0u) {
		if (hasSkybox != 0u && irradianceCubemapIndex != kNoCubemap) {

			// Skyboxから畳み込んだ放射照度で拡散環境光を作る
			TextureCube<float4> irradianceMap = ResourceDescriptorHeap[NonUniformResourceIndex(irradianceCubemapIndex)];
			float3 irradiance = irradianceMap.SampleLevel(gSampler, N, 0.0f).rgb;
			ambient = irradiance * skyboxColor.rgb * iblIntensity * albedo * ao;
		} else {

			// Skyboxが無い場合は従来のフラット環境光
			ambient = ambientIntensity * albedo * ao;
		}
	}
	// 発光はそのまま加算する
	float3 color = Lo + ambient + emissive;

	return float4(color, 1.0f);
}

//============================================================================
//	main、影無し
//============================================================================
float4 main(VSOutput input) : SV_TARGET0 {

	return ResolvePixel(input, false);
}
//============================================================================
//	mainShadowed、影あり
//============================================================================
float4 mainShadowed(VSOutput input) : SV_TARGET0 {

	return ResolvePixel(input, true);
}
