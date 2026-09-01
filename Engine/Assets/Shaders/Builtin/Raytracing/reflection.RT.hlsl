//============================================================================
//	include
//============================================================================
#include "../Mesh/Common/deferredGBuffer.hlsli"

// RTライブラリ内で固定SRVとライトバッファが衝突しないようレジスタを差し替える
#define NEM_LIGHT_COUNTS_REGISTER b1
#define NEM_DIRECTIONAL_LIGHTS_REGISTER t11
#define NEM_POINT_LIGHTS_REGISTER t12
#define NEM_SPOT_LIGHTS_REGISTER t13
#define NEM_RECT_LIGHTS_REGISTER t14
#define NEM_LIGHTING_SAMPLER_REGISTER s0
#include "../Mesh/Common/pbrShading.hlsli"
#undef NEM_LIGHT_COUNTS_REGISTER
#undef NEM_DIRECTIONAL_LIGHTS_REGISTER
#undef NEM_POINT_LIGHTS_REGISTER
#undef NEM_SPOT_LIGHTS_REGISTER
#undef NEM_RECT_LIGHTS_REGISTER
#undef NEM_LIGHTING_SAMPLER_REGISTER

//============================================================================
//	resources
//============================================================================
cbuffer RaytracingViewConstants : register(b0) {

	float4x4 gView;
	float4x4 gProjection;
	float4x4 gInverseView;
	float4x4 gInverseProjection;
	float4x4 gInverseViewProjection;

	float3 gCameraPosition;
	float gMaxReflectionDistance;

	float2 gRenderSize;
	float2 gInvRenderSize;

	float gShadowNormalBias;
	float gReflectionIntensity;
	float gNearClip;
	float gFarClip;

	float gReflectionNormalBias;
	float gReflectionViewBias;
	float gReflectionMinHitDistance;
	float gReflectionMaxRoughness;

	float gReflectionRoughnessFade;
	float gSkyIntensity;
	float gFresnelMin;
	float gPad0;

	float4 gSkyboxColor;
	uint gSkyboxCubemapIndex;
	uint gHasSkybox;
	float gIBLIntensity;
	uint gFrameIndex;
};

struct ReflectionPayload {

	float3 color;
	uint hit;

	float3 worldPosition;
	float hitDistance;

	float3 worldNormal;
	float _pad0;
};
struct RaytracingInstanceShaderData {

	uint vertexDescriptorIndex;
	uint indexDescriptorIndex;
	uint vertexOffset;
	uint geometryDataOffset;

	uint renderFlags;
	uint3 _pad;
};
struct RaytracingGeometryShaderData {

	uint subMeshDataIndex;
	uint indexOffset;
	uint pickRecordIndex;
	uint _pad0;
};
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

RaytracingAccelerationStructure gSceneTLAS : register(t0);
Texture2D<float4> gSourceColor : register(t1);
Texture2D<float> gSourceDepth : register(t2);
Texture2D<float4> gSourceNormal : register(t3);
Texture2D<float4> gSourcePosition : register(t4);

StructuredBuffer<RaytracingInstanceShaderData> gRaytracingSceneInstances :
	register(t5);
StructuredBuffer<SubMeshShaderData> gRaytracingSubMeshes : register(t6);
StructuredBuffer<RaytracingGeometryShaderData> gRaytracingGeometries :
	register(t7);
Texture2D<uint> gSourceFlags : register(t8);
Texture2D<float4> gSourceMaterial : register(t9);
Texture2D<float4> gSourceAlbedo : register(t10);
StructuredBuffer<LightClusterHeader> gLightClusterHeaders : register(t15);
StructuredBuffer<uint> gLightClusterIndices : register(t16);
SamplerState gEnvironmentSampler : register(s1);

// TLAS用途別マスク
static const uint kRaytracingMaskShadowCaster = 1u;
static const uint kRaytracingMaskReflectionCaster = 1u << 1;
static const float kMaxReflectionSampleLuminance = 3.0f;

RWTexture2D<float4> gDestColor : register(u0);
RWTexture2D<float> gReflectionHitDistance : register(u1);
RWTexture2D<float4> gReflectionHitGeometry : register(u2);

//============================================================================
//	functions
//============================================================================
float3 SafeNormalize(float3 v, float3 fallbackValue) {

	float lenSq = dot(v, v);
	if (lenSq <= 1e-8f) {
		return fallbackValue;
	}
	return v * rsqrt(lenSq);
}

float3 ClampReflectionSample(float3 radiance) {

	if (!all(radiance == radiance) || any(abs(radiance) >= 65504.0f.xxx)) {
		return 0.0f.xxx;
	}
	radiance = max(radiance, 0.0f.xxx);
	float luminance = dot(radiance,
		float3(0.2126f, 0.7152f, 0.0722f));
	return radiance * min(1.0f,
		kMaxReflectionSampleLuminance / max(luminance, 1e-4f));
}

float3 ReconstructWorldPosition(float2 uv, float depthValue) {

	float4 clip = float4(uv * 2.0f - 1.0f, depthValue, 1.0f);
	clip.y *= -1.0f;

	float4 world = mul(clip, gInverseViewProjection);
	world.xyz /= max(abs(world.w), 1e-6f);

	return world.xyz;
}

float3 LoadPrimaryWorldPosition(uint2 pixel) {
	return gSourcePosition.Load(int3(pixel, 0)).xyz;
}

float3 DecodeWorldNormal(float3 encodedNormal) {

	float3 n = encodedNormal * 2.0f - 1.0f;
	return SafeNormalize(n, float3(0.0f, 1.0f, 0.0f));
}

float SampleWorldFootprintCandidate(
	uint2 pixel, float3 centerPos, float3 centerNormal) {

	float3 samplePos = gSourcePosition.Load(int3(pixel, 0)).xyz;
	float3 sampleNormal = DecodeWorldNormal(
		gSourceNormal.Load(int3(pixel, 0)).xyz);

	if (dot(sampleNormal, centerNormal) < 0.95f) {
		return 0.0f;
	}

	return length(samplePos - centerPos);
}

float EstimatePrimaryWorldFootprint(
	uint2 pixel, uint2 dim, float3 centerPos, float3 centerNormal) {

	uint2 leftPixel = uint2((pixel.x > 0) ? pixel.x - 1 : pixel.x, pixel.y);
	uint2 rightPixel = uint2(min(pixel.x + 1, dim.x - 1), pixel.y);
	uint2 upPixel = uint2(pixel.x, (pixel.y > 0) ? pixel.y - 1 : pixel.y);
	uint2 downPixel = uint2(pixel.x, min(pixel.y + 1, dim.y - 1));

	float footprint = 0.0f;
	footprint = max(footprint,
		SampleWorldFootprintCandidate(leftPixel, centerPos, centerNormal));
	footprint = max(footprint,
		SampleWorldFootprintCandidate(rightPixel, centerPos, centerNormal));
	footprint = max(footprint,
		SampleWorldFootprintCandidate(upPixel, centerPos, centerNormal));
	footprint = max(footprint,
		SampleWorldFootprintCandidate(downPixel, centerPos, centerNormal));

	return clamp(footprint, 0.0001f, 0.05f);
}

float3 EvaluateSkyReflection(float3 direction) {

	float upT = saturate(direction.y * 0.5f + 0.5f);

	float3 horizonColor = float3(0.55f, 0.65f, 0.80f);
	float3 zenithColor = float3(0.10f, 0.22f, 0.45f);
	float3 sky = lerp(horizonColor, zenithColor, upT);

	float3 sunDir = SafeNormalize(
		float3(0.35f, 0.85f, 0.20f), float3(0.0f, 1.0f, 0.0f));
	float sunAmount = pow(saturate(dot(direction, sunDir)), 256.0f);
	sky += sunAmount * float3(1.0f, 0.95f, 0.80f) * 2.0f;

	return sky * gSkyIntensity;
}

float3 EvaluateReflectionEnvironment(float3 direction) {

	if (gHasSkybox != 0u && gSkyboxCubemapIndex != kNoTexture) {

		TextureCube<float4> skybox = ResourceDescriptorHeap[
			NonUniformResourceIndex(gSkyboxCubemapIndex)];
		return skybox.SampleLevel(gEnvironmentSampler, direction, 0.0f).rgb *
			gSkyboxColor.rgb * gSkyIntensity;
	}
	return EvaluateSkyReflection(direction);
}

float3 EstimateWorldNormalFromDepth(
	uint2 pixel, uint2 dim, float centerDepth) {

	uint2 leftPixel = uint2((pixel.x > 0) ? pixel.x - 1 : pixel.x, pixel.y);
	uint2 rightPixel = uint2(min(pixel.x + 1, dim.x - 1), pixel.y);
	uint2 upPixel = uint2(pixel.x, (pixel.y > 0) ? pixel.y - 1 : pixel.y);
	uint2 downPixel = uint2(pixel.x, min(pixel.y + 1, dim.y - 1));

	float2 uvCenter = (float2(pixel) + 0.5f) / float2(dim);
	float2 uvLeft = (float2(leftPixel) + 0.5f) / float2(dim);
	float2 uvRight = (float2(rightPixel) + 0.5f) / float2(dim);
	float2 uvUp = (float2(upPixel) + 0.5f) / float2(dim);
	float2 uvDown = (float2(downPixel) + 0.5f) / float2(dim);

	float leftDepth = gSourceDepth.Load(int3(leftPixel, 0));
	float rightDepth = gSourceDepth.Load(int3(rightPixel, 0));
	float upDepth = gSourceDepth.Load(int3(upPixel, 0));
	float downDepth = gSourceDepth.Load(int3(downPixel, 0));

	float3 p = ReconstructWorldPosition(uvCenter, centerDepth);
	float3 pl = ReconstructWorldPosition(uvLeft, leftDepth);
	float3 pr = ReconstructWorldPosition(uvRight, rightDepth);
	float3 pu = ReconstructWorldPosition(uvUp, upDepth);
	float3 pd = ReconstructWorldPosition(uvDown, downDepth);

	float3 dx = (abs(rightDepth - centerDepth) <
		abs(leftDepth - centerDepth)) ? (pr - p) : (p - pl);
	float3 dy = (abs(downDepth - centerDepth) <
		abs(upDepth - centerDepth)) ? (pd - p) : (p - pu);

	float3 n = SafeNormalize(cross(dy, dx), float3(0.0f, 1.0f, 0.0f));
	float3 toCamera = SafeNormalize(
		gCameraPosition - p, float3(0.0f, 0.0f, 1.0f));
	if (dot(n, toCamera) < 0.0f) {
		n = -n;
	}
	return n;
}

float3 ComputeBarycentrics(float2 bary) {

	return float3(1.0f - bary.x - bary.y, bary.x, bary.y);
}

float4 SampleHitTexture(uint textureIndex, float2 uv,
	float mipLevel, float4 fallbackValue) {

	if (textureIndex == kNoTexture) {
		return fallbackValue;
	}
	Texture2D<float4> texture =
		ResourceDescriptorHeap[NonUniformResourceIndex(textureIndex)];
	return texture.SampleLevel(gSampler, uv, mipLevel);
}

void ResolveRaytracingHitGeometry(
	in BuiltInTriangleIntersectionAttributes attr,
	out RaytracingInstanceShaderData instanceData,
	out SubMeshShaderData subMesh,
	out float2 uv,
	out float3 worldPosition,
	out float3x3 tangentToWorld) {

	instanceData = gRaytracingSceneInstances[InstanceID()];
	RaytracingGeometryShaderData geometryData =
		gRaytracingGeometries[
			instanceData.geometryDataOffset + GeometryIndex()];
	subMesh = gRaytracingSubMeshes[geometryData.subMeshDataIndex];

	StructuredBuffer<uint> indices =
		ResourceDescriptorHeap[
			NonUniformResourceIndex(instanceData.indexDescriptorIndex)];
	StructuredBuffer<MeshVertex> vertices =
		ResourceDescriptorHeap[
			NonUniformResourceIndex(instanceData.vertexDescriptorIndex)];

	uint baseIndex = geometryData.indexOffset + PrimitiveIndex() * 3u;
	MeshVertex v0 = vertices[
		instanceData.vertexOffset + indices[baseIndex + 0u]];
	MeshVertex v1 = vertices[
		instanceData.vertexOffset + indices[baseIndex + 1u]];
	MeshVertex v2 = vertices[
		instanceData.vertexOffset + indices[baseIndex + 2u]];

	float3 bary = ComputeBarycentrics(attr.barycentrics);
	uv = v0.uv * bary.x + v1.uv * bary.y + v2.uv * bary.z;
	uv = mul(float4(uv, 0.0f, 1.0f), subMesh.uvMatrix).xy;

	float3 objectNormal = SafeNormalize(
		v0.normal * bary.x + v1.normal * bary.y + v2.normal * bary.z,
		float3(0.0f, 1.0f, 0.0f));
	float3 objectTangent = SafeNormalize(
		v0.tangent * bary.x + v1.tangent * bary.y + v2.tangent * bary.z,
		float3(1.0f, 0.0f, 0.0f));
	float tangentSign =
		v0.tangentSign * bary.x +
		v1.tangentSign * bary.y +
		v2.tangentSign * bary.z < 0.0f ? -1.0f : 1.0f;

	float3 localNormal = SafeNormalize(
		mul(float4(objectNormal, 0.0f), subMesh.localNormalMatrix).xyz,
		objectNormal);
	float3 localTangent = SafeNormalize(
		mul(float4(objectTangent, 0.0f), subMesh.localMatrix).xyz,
		objectTangent);
	float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
	float3x3 worldToObject = (float3x3)WorldToObject3x4();
	float3 worldNormal = SafeNormalize(
		mul(localNormal, worldToObject), localNormal);
	float3 worldTangent = SafeNormalize(
		mul(objectToWorld, localTangent), localTangent);
	worldTangent = SafeNormalize(
		worldTangent - worldNormal * dot(worldNormal, worldTangent),
		float3(1.0f, 0.0f, 0.0f));

	float worldOrientationSign = determinant(objectToWorld) < 0.0f ? -1.0f : 1.0f;
	float bitangentSign = tangentSign *
		subMesh.localOrientationSign * worldOrientationSign;
	float3 worldBitangent =
		SafeNormalize(cross(worldNormal, worldTangent),
			float3(0.0f, 0.0f, 1.0f)) * bitangentSign;

	// 両面形状の裏面ヒットでも法線を入射側へ向ける
	if (dot(worldNormal, WorldRayDirection()) > 0.0f) {
		worldNormal = -worldNormal;
		worldBitangent = -worldBitangent;
	}
	tangentToWorld = float3x3(
		worldTangent, worldBitangent, worldNormal);
	worldPosition = WorldRayOrigin() +
		WorldRayDirection() * RayTCurrent();
}

ResolvedPBRMaterial ResolveRaytracingHitMaterial(
	in BuiltInTriangleIntersectionAttributes attr,
	out RaytracingInstanceShaderData instanceData,
	out float3 worldPosition) {

	SubMeshShaderData subMesh;
	float2 uv;
	float3x3 tangentToWorld;
	ResolveRaytracingHitGeometry(attr, instanceData, subMesh,
		uv, worldPosition, tangentToWorld);
	// レイ距離に応じたMipを使い遠距離ヒットの高周波ノイズを抑える
	float textureMip = max(log2(1.0f + RayTCurrent() * 0.02f), 0.0f);

	float4 baseColor = subMesh.importedBaseColor * subMesh.color;
	baseColor *= SampleHitTexture(
		subMesh.baseColorTextureIndex, uv, textureMip, 1.0f.xxxx);

	// glTFのmetallic-roughness規約に合わせてBとGを参照する
	float4 metallicRoughness = SampleHitTexture(
		subMesh.metallicRoughnessTextureIndex, uv, textureMip, 1.0f.xxxx);
	float metallicSample = SampleHitTexture(
		subMesh.metallicTextureIndex, uv, textureMip, 1.0f.xxxx).r;
	float roughnessSample = SampleHitTexture(
		subMesh.roughnessTextureIndex, uv, textureMip, 1.0f.xxxx).r;
	float metallic = saturate(
		subMesh.metallic * metallicRoughness.b * metallicSample);
	float roughness = max(
		saturate(subMesh.roughness * metallicRoughness.g * roughnessSample),
		0.04f);
	float ao = SampleHitTexture(
		subMesh.occlusionTextureIndex, uv, textureMip, 1.0f.xxxx).r;

	float3 normal = tangentToWorld[2];
	if (subMesh.normalTextureIndex != kNoTexture) {

		float3 tangentNormal = SampleHitTexture(
			subMesh.normalTextureIndex, uv, textureMip, 1.0f.xxxx).xyz * 2.0f - 1.0f;
		normal = SafeNormalize(
			mul(tangentNormal, tangentToWorld), normal);
	}

	float3 emissive = subMesh.emissiveColor.rgb *
		subMesh.emissiveColor.a;
	emissive *= SampleHitTexture(
		subMesh.emissiveTextureIndex, uv, textureMip, 1.0f.xxxx).rgb;

	ResolvedPBRMaterial material;
	material.baseColor = baseColor;
	material.N = normal;
	material.metallic = metallic;
	material.roughness = roughness;
	material.ao = ao;
	material.emissive = emissive;
	return material;
}

bool ProjectWorldToPixel(
	float3 worldPosition, out int2 pixel, out float viewDepth) {

	float4 viewPosition = mul(float4(worldPosition, 1.0f), gView);
	float4 clipPosition = mul(viewPosition, gProjection);
	viewDepth = viewPosition.z;
	pixel = int2(0, 0);
	if (clipPosition.w <= 1e-5f) {
		return false;
	}

	float3 ndc = clipPosition.xyz / clipPosition.w;
	if (ndc.x < -1.0f || 1.0f < ndc.x ||
		ndc.y < -1.0f || 1.0f < ndc.y ||
		ndc.z < 0.0f || 1.0f < ndc.z) {

		return false;
	}

	float2 screenUV = float2(
		ndc.x * 0.5f + 0.5f,
		-ndc.y * 0.5f + 0.5f);
	pixel = int2(min(
		uint2(screenUV * gRenderSize),
		uint2(gRenderSize) - 1u));
	return true;
}

bool ResolveRaytracingLightCluster(
	float3 worldPosition, out LightClusterHeader header) {

	header.offset = 0u;
	header.count = 0u;
	if (clusterCount == 0u || clusterTileCountX == 0u ||
		clusterTileCountY == 0u || clusterZSliceCount == 0u) {

		return false;
	}

	int2 pixel;
	float viewDepth;
	if (!ProjectWorldToPixel(worldPosition, pixel, viewDepth)) {
		return false;
	}
	uint2 tile = min(
		uint2(max(pixel, int2(0, 0))) / max(clusterTileSize, 1u),
		uint2(clusterTileCountX - 1u, clusterTileCountY - 1u));
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

float ResolveRaytracingShadow(float3 worldPosition, float3 worldNormal,
	float3 direction, float maxDistance, float shadowStrength,
	uint renderFlags) {

	if (shadowStrength <= 0.0f ||
		(renderFlags & MESH_INSTANCE_FLAG_RECEIVE_SHADOW) == 0u ||
		maxDistance <= 0.002f) {

		return 1.0f;
	}

	RayDesc ray;
	ray.Origin = worldPosition + worldNormal *
		max(gShadowNormalBias, 0.0001f);
	ray.Direction = SafeNormalize(direction, worldNormal);
	ray.TMin = 0.001f;
	ray.TMax = max(maxDistance - 0.001f, ray.TMin);

	RayQuery <
		RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH |
		RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES > rayQuery;
	rayQuery.TraceRayInline(
		gSceneTLAS, 0, kRaytracingMaskShadowCaster, ray);
	while (rayQuery.Proceed()) {
	}
	return rayQuery.CommittedStatus() == COMMITTED_TRIANGLE_HIT ?
		1.0f - saturate(shadowStrength) : 1.0f;
}

float3 EvaluateRaytracingDirectionalLight(DirectionalLight light,
	float3 worldPosition, ResolvedPBRMaterial material,
	float3 V, float3 F0, uint renderFlags) {

	float3 L = SafeNormalize(-light.direction, material.N);
	if (dot(material.N, L) <= 0.0f) {
		return 0.0f.xxx;
	}
	float shadow = ResolveRaytracingShadow(
		worldPosition, material.N, L,
		max(gFarClip, gMaxReflectionDistance),
		light.shadowStrength, renderFlags);
	return shadow * EvaluatePBRDirectionalLight(
		light, material.N, V, material.baseColor.rgb,
		material.metallic, material.roughness, F0);
}

float3 EvaluateRaytracingPointLight(PointLight light,
	float3 worldPosition, ResolvedPBRMaterial material,
	float3 V, float3 F0, uint renderFlags) {

	float3 toLight = light.pos - worldPosition;
	float distanceToLight = length(toLight);
	if (distanceToLight <= 1e-5f ||
		dot(material.N, toLight) <= 0.0f) {

		return 0.0f.xxx;
	}
	float shadow = ResolveRaytracingShadow(
		worldPosition, material.N, toLight / distanceToLight,
		distanceToLight, light.shadowStrength, renderFlags);
	return shadow * EvaluatePBRPointLight(
		light, worldPosition, material.N, V, material.baseColor.rgb,
		material.metallic, material.roughness, F0);
}

float3 EvaluateRaytracingSpotLight(SpotLight light,
	float3 worldPosition, ResolvedPBRMaterial material,
	float3 V, float3 F0, uint renderFlags) {

	float3 toLight = light.pos - worldPosition;
	float distanceToLight = length(toLight);
	if (distanceToLight <= 1e-5f ||
		dot(material.N, toLight) <= 0.0f) {

		return 0.0f.xxx;
	}
	float shadow = ResolveRaytracingShadow(
		worldPosition, material.N, toLight / distanceToLight,
		distanceToLight, light.shadowStrength, renderFlags);
	return shadow * EvaluatePBRSpotLight(
		light, worldPosition, material.N, V, material.baseColor.rgb,
		material.metallic, material.roughness, F0);
}

float3 EvaluateRaytracingRectLight(RectLight light,
	float3 worldPosition, ResolvedPBRMaterial material,
	float3 V, float3 F0, uint renderFlags) {

	float centerDistance = length(light.pos - worldPosition);
	float attenuation = ComputeDistanceAttenuation(
		centerDistance, light.attenuationRadius, light.decay);
	float barnAttenuation = ComputeRectBarnAttenuation(light, worldPosition);
	if (attenuation <= 0.0f || barnAttenuation <= 0.0f) {
		return 0.0f.xxx;
	}
	float3 toCenter = light.pos - worldPosition;
	float shadow = ResolveRaytracingShadow(
		worldPosition, material.N,
		toCenter / max(centerDistance, 1e-5f), centerDistance,
		light.shadowStrength, renderFlags);

	float3 result = 0.0f.xxx;
	[unroll]
	for (uint sampleIndex = 0u;
		sampleIndex < kRectLightSampleCount; ++sampleIndex) {

		float3 samplePosition = GetRectLightSamplePosition(light, sampleIndex);
		float3 toLight = samplePosition - worldPosition;
		float sampleDistance = length(toLight);
		if (sampleDistance <= 1e-5f) {
			continue;
		}

		float3 L = toLight / sampleDistance;
		float sourceFacing = saturate(dot(-L, light.direction));
		float3 radiance = light.color.rgb * light.intensity *
			attenuation * barnAttenuation * sourceFacing * shadow;
		result += EvaluatePBRRadiance(
			material.N, V, L, radiance, material.baseColor.rgb,
			material.metallic, material.roughness, F0);
	}
	return result / float(kRectLightSampleCount);
}

float3 EvaluateRaytracingSurfaceLighting(
	float3 worldPosition,
	ResolvedPBRMaterial material,
	uint renderFlags) {

	if ((renderFlags & MESH_INSTANCE_FLAG_LIGHTING) == 0u) {
		return material.baseColor.rgb + material.emissive;
	}

	// 反射ヒットのBRDFは主カメラではなく、入射レイ方向を視線として評価する
	float3 V = SafeNormalize(-WorldRayDirection(), material.N);
	float3 F0 = lerp(
		gFresnelMin.xxx, material.baseColor.rgb, material.metallic);
	// 二次ヒット地点から影を判定し、主カメラの画面範囲に依存しない照明にする
	float3 lighting = 0.0f.xxx;
	[loop]
	for (uint index = 0u; index < directionalCount; ++index) {

		lighting += EvaluateRaytracingDirectionalLight(
			gDirectionalLights[index], worldPosition,
			material, V, F0, renderFlags);
	}

	// 画面内はDeferred Lightingと同じクラスター索引でローカルライトを絞る
	LightClusterHeader clusterHeader;
	if (ResolveRaytracingLightCluster(worldPosition, clusterHeader)) {

		[loop]
		for (uint clusterLight = 0u;
			clusterLight < clusterHeader.count; ++clusterLight) {

			uint localIndex =
				gLightClusterIndices[clusterHeader.offset + clusterLight];
			if (localIndex < pointCount) {

				lighting += EvaluateRaytracingPointLight(
					gPointLights[localIndex], worldPosition,
					material, V, F0, renderFlags);
			} else {

				uint spotIndex = localIndex - pointCount;
				if (spotIndex < spotCount) {

					lighting += EvaluateRaytracingSpotLight(
						gSpotLights[spotIndex], worldPosition,
						material, V, F0, renderFlags);
				}
			}
		}
	} else {

		// 画面外のヒットではクラスターを引けないため全ローカルライトを評価する
		[loop]
		for (uint index = 0u; index < pointCount; ++index) {

			lighting += EvaluateRaytracingPointLight(
				gPointLights[index], worldPosition,
				material, V, F0, renderFlags);
		}
		[loop]
		for (uint index = 0u; index < spotCount; ++index) {

			lighting += EvaluateRaytracingSpotLight(
				gSpotLights[index], worldPosition,
				material, V, F0, renderFlags);
		}
	}
	[loop]
	for (uint index = 0u; index < rectCount; ++index) {

		lighting += EvaluateRaytracingRectLight(
			gRectLights[index], worldPosition,
			material, V, F0, renderFlags);
	}

	float3 ambient = 0.0f.xxx;
	if ((renderFlags & MESH_INSTANCE_FLAG_RECEIVE_IBL) != 0u) {

		if (gHasSkybox != 0u && gSkyboxCubemapIndex != kNoTexture) {

			TextureCube<float4> skybox = ResourceDescriptorHeap[
				NonUniformResourceIndex(gSkyboxCubemapIndex)];
			float3 irradiance = skybox.SampleLevel(
				gEnvironmentSampler, material.N, 5.0f).rgb;
			ambient = irradiance * gSkyboxColor.rgb * gIBLIntensity *
				material.baseColor.rgb * material.ao;
		} else {

			ambient = 0.03f * material.baseColor.rgb * material.ao;
		}
	}
	return lighting + ambient + material.emissive;
}

//============================================================================
//	miss
//============================================================================
[shader("miss")]
void ReflectionMiss(inout ReflectionPayload payload) {

	payload.hit = 0u;
	payload.color = 0.0f.xxx;
	payload.worldPosition = 0.0f.xxx;
	payload.hitDistance = 0.0f;
	payload.worldNormal = 0.0f.xxx;
	payload._pad0 = 0.0f;
}

//============================================================================
//	closesthit
//============================================================================
#ifndef NEM_REFLECTION_CUSTOM_HIT
[shader("closesthit")]
void ReflectionClosestHit(
	inout ReflectionPayload payload,
	in BuiltInTriangleIntersectionAttributes attr) {

	RaytracingInstanceShaderData instanceData;
	float3 worldPosition;
	ResolvedPBRMaterial material = ResolveRaytracingHitMaterial(
		attr, instanceData, worldPosition);

	payload.hit = 1u;
	payload.color = EvaluateRaytracingSurfaceLighting(
		worldPosition, material, instanceData.renderFlags);
	payload.worldPosition = worldPosition;
	payload.hitDistance = RayTCurrent();
	payload.worldNormal = material.N;
	payload._pad0 = 0.0f;
}
#endif

//============================================================================
//	raygeneration
//============================================================================
[shader("raygeneration")]
void ReflectionRayGen() {

	uint2 pixel = DispatchRaysIndex().xy;
	uint2 dim = DispatchRaysDimensions().xy;
	uint2 sourceDim;
	gSourceDepth.GetDimensions(sourceDim.x, sourceDim.y);
	float2 sourceUV = (float2(pixel) + 0.5f) / float2(dim);
	uint2 sourcePixel = min(
		uint2(sourceUV * float2(sourceDim)), sourceDim - 1u);

	// Trace結果は後続フィルタでScene Colorへ合成する
	gDestColor[pixel] = 0.0f.xxxx;
	gReflectionHitDistance[pixel] = 0.0f;
	gReflectionHitGeometry[pixel] = 0.0f.xxxx;

	float depthValue = gSourceDepth.Load(int3(sourcePixel, 0));

	// 背景画素はLightingPassがskyboxを書いているのでそのまま残す
	if (depthValue >= 1.0f) {
		return;
	}
	// 反射を受けないサーフェイスはそのまま残す
	uint surfaceFlags = gSourceFlags.Load(int3(sourcePixel, 0));
	if ((surfaceFlags & kMaterialFlagReceiveReflection) == 0u) {
		return;
	}

	float3 albedo = gSourceAlbedo.Load(int3(sourcePixel, 0)).rgb;
	float4 material = gSourceMaterial.Load(int3(sourcePixel, 0));
	float metallic = saturate(material.r);
	float roughness = clamp(material.g, 0.04f, 1.0f);
	float roughnessFadeStart = max(
		gReflectionMaxRoughness - gReflectionRoughnessFade, 0.0f);
	float roughnessVisibility = 1.0f - smoothstep(
		roughnessFadeStart, gReflectionMaxRoughness, roughness);
	if (roughnessVisibility <= 0.0f) {
		return;
	}

	float3 worldPos = LoadPrimaryWorldPosition(sourcePixel);
	float3 worldNormal = DecodeWorldNormal(
		gSourceNormal.Load(int3(sourcePixel, 0)).xyz);
	if (dot(worldNormal, worldNormal) <= 1e-6f) {
		worldNormal = EstimateWorldNormalFromDepth(
			sourcePixel, sourceDim, depthValue);
	}

	float3 V = SafeNormalize(
		gCameraPosition - worldPos, float3(0.0f, 0.0f, 1.0f));

	float worldFootprint = EstimatePrimaryWorldFootprint(
		sourcePixel, sourceDim, worldPos, worldNormal);
	float NdotV = max(saturate(dot(worldNormal, V)), 1e-4f);
	float grazing = 1.0f - NdotV;

	float adaptiveNormalBias = max(
		gReflectionNormalBias, worldFootprint * 0.50f);
	float adaptiveViewBias = max(
		gReflectionViewBias,
		worldFootprint * lerp(0.25f, 1.50f, grazing));
	float adaptiveMinHitDistance = max(
		gReflectionMinHitDistance,
		worldFootprint * lerp(1.00f, 2.00f, grazing));

	float3 F0 = lerp(gFresnelMin.xxx, albedo, metallic);
	const uint sampleCount = 1u;
	uint acceptedSampleCount = 0u;
	float3 reflectedRadiance = 0.0f.xxx;
	float accumulatedHitDistance = 0.0f;
	float3 accumulatedHitPosition = 0.0f.xxx;
	uint hitSampleCount = 0u;
	[loop]
	for (uint sampleIndex = 0u;
		sampleIndex < sampleCount &&
		acceptedSampleCount < sampleCount;
		++sampleIndex) {

		// 低サンプル数では粗さ乱数が高輝度ちらつきになるため法線反射を安定入力にする
		float3 H = worldNormal;
		float VdotH = saturate(dot(V, H));
		float NdotH = saturate(dot(worldNormal, H));
		if (VdotH <= 0.0f || NdotH <= 0.0f) {
			continue;
		}

		float3 reflectionDirection = SafeNormalize(reflect(-V, H), worldNormal);
		float NdotL = saturate(dot(worldNormal, reflectionDirection));
		if (NdotL <= 0.0f) {
			continue;
		}

		RayDesc ray;
		ray.Origin = worldPos + worldNormal * adaptiveNormalBias +
			reflectionDirection * adaptiveViewBias;
		ray.Direction = reflectionDirection;
		ray.TMin = adaptiveMinHitDistance;
		ray.TMax = gMaxReflectionDistance;

		ReflectionPayload payload;
		payload.hit = 0u;
		payload.color = 0.0f.xxx;
		payload.worldPosition = 0.0f.xxx;
		payload.hitDistance = 0.0f;
		payload.worldNormal = 0.0f.xxx;
		payload._pad0 = 0.0f;

		// CastReflection無効のインスタンスはマスクで除外される
		// SBTは全ジオメトリで1つのHitGroupを共有するためGeometryIndexを加算しない
		TraceRay(gSceneTLAS,
			RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES |
			RAY_FLAG_CULL_NON_OPAQUE |
			RAY_FLAG_CULL_BACK_FACING_TRIANGLES,
			kRaytracingMaskReflectionCaster, 0, 0, 0, ray, payload);

		float3 incomingRadiance = 0.0f.xxx;
		if (payload.hit != 0u) {
			incomingRadiance = payload.color;
			accumulatedHitPosition += payload.worldPosition;
			++hitSampleCount;
		} else {
			incomingRadiance =
				EvaluateReflectionEnvironment(reflectionDirection);
		}
		accumulatedHitDistance += payload.hit != 0u ?
			payload.hitDistance : gMaxReflectionDistance;
		float3 sampleWeight = FresnelSchlick(VdotH, F0);
		reflectedRadiance += ClampReflectionSample(
			incomingRadiance * sampleWeight);
		++acceptedSampleCount;
	}
	if (acceptedSampleCount == 0u) {
		return;
	}
	reflectedRadiance /= float(acceptedSampleCount);
	reflectedRadiance *= gReflectionIntensity * roughnessVisibility;

	gDestColor[pixel] = float4(reflectedRadiance, roughnessVisibility);
	gReflectionHitDistance[pixel] =
		accumulatedHitDistance / float(acceptedSampleCount);
	gReflectionHitGeometry[pixel] = hitSampleCount != 0u ?
		float4(accumulatedHitPosition / float(hitSampleCount), 1.0f) :
		0.0f.xxxx;
}
