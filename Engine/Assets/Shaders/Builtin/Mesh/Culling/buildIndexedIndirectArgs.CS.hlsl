//============================================================================
//	include
//============================================================================
#include "../Common/meshShaderSharedTypes.hlsli"

//============================================================================
//	resources
//============================================================================
cbuffer IndirectArgsConstants : register(b0) {

	uint indexCount;
	uint _pad0;
	uint _pad1;
	uint _pad2;
};
cbuffer ViewConstants : register(b1) {

	float4x4 viewProjection;
	float4x4 cullingViewProjection;
	float4x4 cullingView;
	float3 cullingCameraPos;
	float cullingNearClip;
	float3 cullingCameraForward;
	float _cullingPad0;
	float2 viewSize;
	float2 cullingViewSize;
	float2 cullingProjectionScale;
	float2 _viewPad0;
	float3 renderCameraPos;
	float _viewPad1;
};
cbuffer MeshDrawConstants : register(b2) {

	uint meshletCount;
	uint subMeshCount;
	uint instanceCount;
	uint cullingEnabled;
	uint packedMeshletVertexIndices;
	uint frustumCullingEnabled;
	uint contributionCullingEnabled;
	uint normalConeCullingEnabled;
	float3 meshBoundsCenter;
	float meshBoundsRadius;
	float contributionPixelThreshold;
	uint invertedHullOutlinePass;
	float outlineMaxModelExpansion;
	float outlineMaxAbsCameraZOffset;
	uint outlineHasScreenPixelWidth;
	uint occlusionCullingEnabled;
	uint _meshDrawReservedGroup;
	float maxDisplacement;
	uint4 lodIndexOffsets;
	uint4 lodIndexCounts;
	uint4 lodMeshletOffsets;
	uint4 lodMeshletCounts;
	float3 lodPixelThresholds;
	uint lodCount;
};
StructuredBuffer<MeshInstance> gMeshInstances : register(t0);
StructuredBuffer<SubMeshShaderData> gSubMeshes : register(t3, space1);
Texture2D<float> gOcclusionDepthPyramid : register(t1);
RWStructuredBuffer<MeshInstance> gVisibleMeshInstances : register(u0);
RWByteAddressBuffer gIndexedIndirectArgs : register(u1);

#define NEM_OCCLUSION_DEPTH_PYRAMID gOcclusionDepthPyramid
#include "../../Common/CullingHelpers.hlsli"

void EncapsulateSphere(inout float3 center, inout float radius, float3 addCenter, float addRadius) {

	float3 diff = addCenter - center;
	float dist = length(diff);
	if (dist + addRadius <= radius) {
		return;
	}
	if (dist + radius <= addRadius) {
		center = addCenter;
		radius = addRadius;
		return;
	}

	float newRadius = (radius + dist + addRadius) * 0.5f;
	if (dist > 0.00001f) {
		center += diff * ((newRadius - radius) / dist);
	}
	radius = newRadius;
}

// 背面法アウトラインでBoundsへ加えるモデル空間方向の膨張量
float ResolveOutlineCullLocalExpansion() {
	return invertedHullOutlinePass != 0u ? outlineMaxModelExpansion : 0.0f;
}
// Camera Z Offsetによるワールド方向の追加膨張量
float ResolveOutlineCullWorldExtra() {
	return invertedHullOutlinePass != 0u ? outlineMaxAbsCameraZOffset : 0.0f;
}

void CalcInstanceCullBounds(MeshInstance instance, out float3 center, out float radius) {

	const float outlineLocal = ResolveOutlineCullLocalExpansion();
	const float outlineWorldExtra = ResolveOutlineCullWorldExtra();

	center = mul(float4(meshBoundsCenter, 1.0f), instance.worldMatrix).xyz;
	radius = (meshBoundsRadius + outlineLocal) * GetMatrixMaxScale(instance.worldMatrix) + outlineWorldExtra;
	if (instance.subMeshCount == 0u) {
		return;
	}

	bool initialized = false;
	for (uint i = 0; i < instance.subMeshCount; ++i) {

		SubMeshShaderData subMesh = gSubMeshes[instance.subMeshDataOffset + i];

		// 実描画はsubMesh.localMatrixをworldMatrixの前に掛けるため、カリングBoundsも同じ空間で膨らませる
		float3 localCenter = mul(float4(meshBoundsCenter, 1.0f), subMesh.localMatrix).xyz;
		float localRadius = (meshBoundsRadius + outlineLocal) * GetMatrixMaxScale(subMesh.localMatrix);
		float3 worldCenter = mul(float4(localCenter, 1.0f), instance.worldMatrix).xyz;
		float worldRadius = localRadius * GetMatrixMaxScale(instance.worldMatrix) + outlineWorldExtra;

		if (!initialized) {
			center = worldCenter;
			radius = worldRadius;
			initialized = true;
			continue;
		}
		EncapsulateSphere(center, radius, worldCenter, worldRadius);
	}
}

float CalcProjectedPixelRadius(float3 center, float radius) {

	float2 radiusXY = CalcProjectedPixelRadiusXY(
		cullingViewProjection, cullingView, cullingNearClip, cullingProjectionScale,
		cullingViewSize, contributionPixelThreshold, center, radius);
	return max(radiusXY.x, radiusXY.y);
}

bool HasContribution(float3 center, float radius) {

	if (contributionCullingEnabled == 0u) {
		return true;
	}
	return CalcProjectedPixelRadius(center, radius) >= contributionPixelThreshold;
}

bool IsSphereOccluded(float3 center, float radius) {

	if (occlusionCullingEnabled == 0u) {
		return false;
	}

	return IsSphereOccludedHiZ(
		cullingViewProjection, cullingView,
		cullingNearClip, cullingProjectionScale,
		cullingViewSize, cullingCameraForward,
		center, radius);
}

bool IsInstanceVisible(MeshInstance instance) {

	if (cullingEnabled == 0u) {
		return true;
	}

	float3 center;
	float radius;
	CalcInstanceCullBounds(instance, center, radius);
	if (frustumCullingEnabled != 0u &&
		!IsSphereInFrustum(cullingViewProjection, center, radius)) {
		return false;
	}
	if (!HasContribution(center, radius)) {
		return false;
	}
	if (IsSphereOccluded(center, radius)) {
		return false;
	}
	return true;
}

uint ResolveMeshLOD(MeshInstance instance) {

	if (lodCount <= 1u ||
		(instance.flags & MESH_INSTANCE_FLAG_SKINNED) != 0u) {
		return 0u;
	}

	float3 center;
	float radius;
	CalcInstanceCullBounds(instance, center, radius);
	float pixelRadius = CalcProjectedPixelRadius(center, radius);
	if (pixelRadius >= lodPixelThresholds.x) {
		return 0u;
	}
	if (pixelRadius >= lodPixelThresholds.y) {
		return 1u;
	}
	if (pixelRadius >= lodPixelThresholds.z) {
		return 2u;
	}
	return min(3u, lodCount - 1u);
}

//============================================================================
//	main
//============================================================================
[numthreads(256, 1, 1)]
void main(uint groupThreadID : SV_GroupThreadID) {

	if (groupThreadID == 0) {

		for (uint lodIndex = 0; lodIndex < 4u; ++lodIndex) {

			const uint argsOffset = lodIndex * 20u;
			gIndexedIndirectArgs.Store(argsOffset + 0u, lodIndexCounts[lodIndex]);
			gIndexedIndirectArgs.Store(argsOffset + 4u, 0u);
			gIndexedIndirectArgs.Store(argsOffset + 8u, lodIndexOffsets[lodIndex]);
			gIndexedIndirectArgs.Store(argsOffset + 12u, 0u);
			// SV_InstanceIDにはStartInstanceLocationが加算されないため常に0
			gIndexedIndirectArgs.Store(argsOffset + 16u, 0u);
		}
	}
	GroupMemoryBarrierWithGroupSync();

	for (uint i = groupThreadID; i < instanceCount; i += 256u) {

		MeshInstance instance = gMeshInstances[i];
		if (!IsInstanceVisible(instance)) {
			continue;
		}

		const uint lodIndex = ResolveMeshLOD(instance);
		uint visibleIndex = 0;
		gIndexedIndirectArgs.InterlockedAdd(
			lodIndex * 20u + 4u, 1u, visibleIndex);
		gVisibleMeshInstances[
			lodIndex * instanceCount + visibleIndex] = instance;
	}
}
