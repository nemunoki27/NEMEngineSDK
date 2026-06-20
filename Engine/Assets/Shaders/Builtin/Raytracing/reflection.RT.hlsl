//============================================================================
//	include
//============================================================================
#include "../Mesh/Common/meshShaderSharedTypes.hlsli"

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
	float gReflectionThicknessBase;

	float gReflectionThicknessScale;
	float gSkyIntensity;
	float gFresnelMin;
	float gPad0;
};

struct ReflectionPayload {

	float3 color;
	uint hit;
};
struct RaytracingInstanceShaderData {

	uint vertexDescriptorIndex;
	uint indexDescriptorIndex;
	uint vertexOffset;
	uint subMeshDataIndex;

	uint indexOffset;
	uint _pad0[3];
};
static const uint kNoTexture = 0xFFFFFFFF;

RaytracingAccelerationStructure gSceneTLAS : register(t0);
Texture2D<float4> gSourceColor : register(t1);
Texture2D<float> gSourceDepth : register(t2);
Texture2D<float4> gSourceNormal : register(t3);
Texture2D<float4> gSourcePosition : register(t4);

StructuredBuffer<RaytracingInstanceShaderData> gRaytracingSceneInstances : register(t5);
StructuredBuffer<SubMeshShaderData> gRaytracingSubMeshes : register(t6);

RWTexture2D<float4> gDestColor : register(u0);
SamplerState gLinearClamp : register(s0);

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

float SampleWorldFootprintCandidate(uint2 pixel, float3 centerPos, float3 centerNormal) {

	float3 samplePos = gSourcePosition.Load(int3(pixel, 0)).xyz;
	float3 sampleNormal = DecodeWorldNormal(gSourceNormal.Load(int3(pixel, 0)).xyz);

	if (dot(sampleNormal, centerNormal) < 0.95f) {
		return 0.0f;
	}

	return length(samplePos - centerPos);
}

float EstimatePrimaryWorldFootprint(uint2 pixel, uint2 dim, float3 centerPos, float3 centerNormal) {

	uint2 leftPixel = uint2((pixel.x > 0) ? pixel.x - 1 : pixel.x, pixel.y);
	uint2 rightPixel = uint2(min(pixel.x + 1, dim.x - 1), pixel.y);
	uint2 upPixel = uint2(pixel.x, (pixel.y > 0) ? pixel.y - 1 : pixel.y);
	uint2 downPixel = uint2(pixel.x, min(pixel.y + 1, dim.y - 1));

	float footprint = 0.0f;
	footprint = max(footprint, SampleWorldFootprintCandidate(leftPixel, centerPos, centerNormal));
	footprint = max(footprint, SampleWorldFootprintCandidate(rightPixel, centerPos, centerNormal));
	footprint = max(footprint, SampleWorldFootprintCandidate(upPixel, centerPos, centerNormal));
	footprint = max(footprint, SampleWorldFootprintCandidate(downPixel, centerPos, centerNormal));

	return clamp(footprint, 0.0001f, 0.05f);
}

float3 EvaluateSkyReflection(float3 direction) {

	float upT = saturate(direction.y * 0.5f + 0.5f);

	float3 horizonColor = float3(0.55f, 0.65f, 0.80f);
	float3 zenithColor = float3(0.10f, 0.22f, 0.45f);
	float3 sky = lerp(horizonColor, zenithColor, upT);

	float3 sunDir = SafeNormalize(float3(0.35f, 0.85f, 0.20f), float3(0.0f, 1.0f, 0.0f));
	float sunAmount = pow(saturate(dot(direction, sunDir)), 256.0f);
	sky += sunAmount * float3(1.0f, 0.95f, 0.80f) * 2.0f;

	return sky * gSkyIntensity;
}

float3 EstimateWorldNormalFromDepth(uint2 pixel, uint2 dim, float centerDepth) {

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

	float3 dx = (abs(rightDepth - centerDepth) < abs(leftDepth - centerDepth)) ? (pr - p) : (p - pl);
	float3 dy = (abs(downDepth - centerDepth) < abs(upDepth - centerDepth)) ? (pd - p) : (p - pu);

	float3 n = cross(dy, dx);
	n = SafeNormalize(n, float3(0.0f, 1.0f, 0.0f));

	float3 toCamera = SafeNormalize(gCameraPosition - p, float3(0.0f, 0.0f, 1.0f));
	if (dot(n, toCamera) < 0.0f) {
		n = -n;
	}
	return n;
}

float3 ComputeBarycentrics(float2 bary) {

	return float3(1.0f - bary.x - bary.y, bary.x, bary.y);
}

float3 EvaluateHitMaterialBaseColor(in BuiltInTriangleIntersectionAttributes attr) {

	RaytracingInstanceShaderData instanceData = gRaytracingSceneInstances[InstanceID()];
	SubMeshShaderData subMesh = gRaytracingSubMeshes[instanceData.subMeshDataIndex];

	StructuredBuffer<uint> indices = ResourceDescriptorHeap[NonUniformResourceIndex(instanceData.indexDescriptorIndex)];
	StructuredBuffer<MeshVertex> vertices = ResourceDescriptorHeap[NonUniformResourceIndex(instanceData.vertexDescriptorIndex)];

	uint primitiveIndex = PrimitiveIndex();

	uint baseIndex = instanceData.indexOffset + primitiveIndex * 3;

	uint i0 = indices[baseIndex + 0];
	uint i1 = indices[baseIndex + 1];
	uint i2 = indices[baseIndex + 2];

	MeshVertex v0 = vertices[instanceData.vertexOffset + i0];
	MeshVertex v1 = vertices[instanceData.vertexOffset + i1];
	MeshVertex v2 = vertices[instanceData.vertexOffset + i2];

	float3 bary = ComputeBarycentrics(attr.barycentrics);
	float2 uv = v0.uv * bary.x + v1.uv * bary.y + v2.uv * bary.z;

	float2 transformedUV = mul(float4(uv, 0.0f, 1.0f), subMesh.uvMatrix).xy;

	float3 baseColor;
	if (subMesh.baseColorTextureIndex == kNoTexture) {
		baseColor = subMesh.importedBaseColor.rgb * subMesh.color.rgb;
	} else {
		Texture2D<float4> baseColorTexture = ResourceDescriptorHeap[NonUniformResourceIndex(subMesh.baseColorTextureIndex)];
		float4 texel = baseColorTexture.SampleLevel(gLinearClamp, transformedUV, 0.0f);
		baseColor = texel.rgb * subMesh.importedBaseColor.rgb * subMesh.color.rgb;
	}

	return baseColor;
}

//============================================================================
//	miss
//============================================================================
[shader("miss")]
void ReflectionMiss(inout ReflectionPayload payload) {

	payload.hit = 0;
	payload.color = 0.0f.xxx;
}

//============================================================================
//	closesthit
//============================================================================
[shader("closesthit")]
void ReflectionClosestHit(inout ReflectionPayload payload, in BuiltInTriangleIntersectionAttributes attr) {

	payload.hit = 1;
	payload.color = EvaluateHitMaterialBaseColor(attr);
}

//============================================================================
//	raygeneration
//============================================================================
[shader("raygeneration")]
void ReflectionRayGen() {

	uint2 pixel = DispatchRaysIndex().xy;
	uint2 dim = DispatchRaysDimensions().xy;

	float2 uv = (float2(pixel) + 0.5f) / float2(dim);
	float depthValue = gSourceDepth.Load(int3(pixel, 0));

	// 背景画素はLightingPassがskyboxを書いているのでそのまま残す
	if (depthValue >= 1.0f) {
		return;
	}

	float3 worldPos = LoadPrimaryWorldPosition(pixel);

	float3 worldNormal = DecodeWorldNormal(gSourceNormal.Load(int3(pixel, 0)).xyz);
	if (dot(worldNormal, worldNormal) <= 1e-6f) {
		worldNormal = EstimateWorldNormalFromDepth(pixel, dim, depthValue);
	}

	float3 cameraToSurface = SafeNormalize(worldPos - gCameraPosition, float3(0.0f, 0.0f, 1.0f));
	float3 surfaceToCamera = -cameraToSurface;
	float3 reflectionDir = SafeNormalize(reflect(cameraToSurface, worldNormal), worldNormal);

	float worldFootprint = EstimatePrimaryWorldFootprint(pixel, dim, worldPos, worldNormal);

	float NdotV = saturate(dot(worldNormal, surfaceToCamera));
	float grazing = 1.0f - NdotV;

	float adaptiveNormalBias = max(gReflectionNormalBias, worldFootprint * 0.50f);
	float adaptiveViewBias = max(gReflectionViewBias, worldFootprint * lerp(0.25f, 1.50f, grazing));
	float adaptiveMinHitDistance = max(gReflectionMinHitDistance, worldFootprint * lerp(1.00f, 2.00f, grazing));

	RayDesc ray;
	ray.Origin = worldPos + worldNormal * adaptiveNormalBias + reflectionDir * adaptiveViewBias;
	ray.Direction = reflectionDir;
	ray.TMin = adaptiveMinHitDistance;
	ray.TMax = gMaxReflectionDistance;

	ReflectionPayload payload;
	payload.hit = 0;
	payload.color = 0.0f.xxx;

	TraceRay(gSceneTLAS, RAY_FLAG_SKIP_PROCEDURAL_PRIMITIVES | RAY_FLAG_CULL_NON_OPAQUE,
		0xFF, 0, 1, 0, ray, payload);

	float3 reflectionColor = (payload.hit != 0) ? payload.color : EvaluateSkyReflection(reflectionDir);

	float fresnel = pow(1.0f - NdotV, 5.0f);
	float reflectionWeight = saturate(gReflectionIntensity * lerp(gFresnelMin, 1.0f, fresnel));

	// ベース色はLightingPassが書いた照明済みSceneColorFinalをUAVから読み、その上に反射を加算する
	float3 litColor = gDestColor[pixel].rgb;
	float3 finalColor = litColor + reflectionColor * reflectionWeight;
	gDestColor[pixel] = float4(finalColor, 1.0f);
}
