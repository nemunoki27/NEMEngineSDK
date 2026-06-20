//============================================================================
//	include
//============================================================================
// SubMeshShaderData / MeshInstance は共通ヘッダから取る(重複宣言しない)
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
	uint _meshDrawReserved0;
	uint contributionCullingEnabled;
	uint normalConeCullingEnabled;
	float3 meshBoundsCenter;
	float meshBoundsRadius;
	float contributionPixelThreshold;
	uint invertedHullOutlinePass;
	float outlineMaxModelExpansion;
	float outlineMaxAbsCameraZOffset;
	uint outlineHasScreenPixelWidth;
	uint3 _meshDrawReserved1;
};
StructuredBuffer<MeshInstance> gMeshInstances : register(t0);
StructuredBuffer<SubMeshShaderData> gSubMeshes : register(t3, space1);
RWStructuredBuffer<MeshInstance> gVisibleMeshInstances : register(u0);
RWByteAddressBuffer gIndexedIndirectArgs : register(u1);

float4 GetFrustumPlane(uint index) {

	float4 col0 = float4(cullingViewProjection[0][0], cullingViewProjection[1][0], cullingViewProjection[2][0], cullingViewProjection[3][0]);
	float4 col1 = float4(cullingViewProjection[0][1], cullingViewProjection[1][1], cullingViewProjection[2][1], cullingViewProjection[3][1]);
	float4 col2 = float4(cullingViewProjection[0][2], cullingViewProjection[1][2], cullingViewProjection[2][2], cullingViewProjection[3][2]);
	float4 col3 = float4(cullingViewProjection[0][3], cullingViewProjection[1][3], cullingViewProjection[2][3], cullingViewProjection[3][3]);

	if (index == 0) { return col3 + col0; }
	if (index == 1) { return col3 - col0; }
	if (index == 2) { return col3 + col1; }
	if (index == 3) { return col3 - col1; }
	if (index == 4) { return col2; }
	return col3 - col2;
}

float4 NormalizePlane(float4 plane) {

	float len = length(plane.xyz);
	if (len <= 0.00001f) {
		return plane;
	}
	return plane / len;
}

float GetMatrixMaxScale(float4x4 inputMat) {

	float sx = length(inputMat[0].xyz);
	float sy = length(inputMat[1].xyz);
	float sz = length(inputMat[2].xyz);
	return max(sx, max(sy, sz));
}

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

bool IsSphereInFrustum(float3 center, float radius) {

	[unroll]
	for (uint i = 0; i < 6; ++i) {

		float4 plane = NormalizePlane(GetFrustumPlane(i));
		if (dot(plane.xyz, center) + plane.w < -radius) {
			return false;
		}
	}
	return true;
}

float2 CalcProjectedPixelRadiusXY(float3 center, float radius) {

	float4 clip = mul(float4(center, 1.0f), cullingViewProjection);
	if (clip.w <= 0.00001f) {
		return float2(contributionPixelThreshold, contributionPixelThreshold);
	}

	float3 viewCenter = mul(float4(center, 1.0f), cullingView).xyz;
	float nearZ = viewCenter.z - radius;
	if (nearZ <= max(cullingNearClip, 0.00001f)) {
		return float2(1000000.0f, 1000000.0f);
	}

	float2 projectedRadius = abs(radius * cullingProjectionScale / nearZ);
	return projectedRadius * cullingViewSize * 0.5f;
}

float CalcProjectedPixelRadius(float3 center, float radius) {

	float2 radiusXY = CalcProjectedPixelRadiusXY(center, radius);
	return max(radiusXY.x, radiusXY.y);
}

bool HasContribution(float3 center, float radius) {

	if (contributionCullingEnabled == 0u) {
		return true;
	}
	return CalcProjectedPixelRadius(center, radius) >= contributionPixelThreshold;
}

bool IsInstanceVisible(MeshInstance instance) {

	if (cullingEnabled == 0u) {
		return true;
	}

	float3 center;
	float radius;
	CalcInstanceCullBounds(instance, center, radius);
	if (!IsSphereInFrustum(center, radius)) {
		return false;
	}
	if (!HasContribution(center, radius)) {
		return false;
	}
	return true;
}

//============================================================================
//	main
//============================================================================
[numthreads(256, 1, 1)]
void main(uint groupThreadID : SV_GroupThreadID) {

	if (groupThreadID == 0) {

		gIndexedIndirectArgs.Store(0, indexCount);
		gIndexedIndirectArgs.Store(4, 0);
		gIndexedIndirectArgs.Store(8, 0);
		gIndexedIndirectArgs.Store(12, 0);
		gIndexedIndirectArgs.Store(16, 0);
	}
	GroupMemoryBarrierWithGroupSync();

	for (uint i = groupThreadID; i < instanceCount; i += 256u) {

		MeshInstance instance = gMeshInstances[i];
		if (!IsInstanceVisible(instance)) {
			continue;
		}

		uint visibleIndex = 0;
		gIndexedIndirectArgs.InterlockedAdd(4, 1, visibleIndex);
		gVisibleMeshInstances[visibleIndex] = instance;
	}
}
