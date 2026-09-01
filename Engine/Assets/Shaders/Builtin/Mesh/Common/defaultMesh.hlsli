#ifndef NEM_DEFAULT_MESH_HLSLI
#define NEM_DEFAULT_MESH_HLSLI

//============================================================================
//	Common VS/PS
//============================================================================
#include "meshShaderSharedTypes.hlsli"

//============================================================================
//	output
//============================================================================
struct VSOutput {

	float4 position : SV_Position;
	float3 normal : NORMAL0;
	float3 tangent : TANGENT0;
	float2 uv : TEXCOORD0;
	float3 worldPos : WORLDPOS0;
	float4 currentClipPosition : TEXCOORD6;
	float4 previousClipPosition : TEXCOORD7;
	uint instanceID : INSTANCEID0;
	uint subMeshIndex : SUBMESHINDEX0;
	// PS側のTBN構築で使う接線符号と向き符号
	float tangentSign : TANGENTSIGN0;
	float orientationSign : ORIENTATIONSIGN0;
};
struct DepthVSOutput {

	float4 position : SV_Position;
};

//============================================================================
//	resources
//============================================================================
cbuffer ViewConstants : register(b0) {
	
	float4x4 viewProjection;
	float4x4 previousViewProjection;
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
	uint frameSerial;
};
cbuffer SubMeshConstants : register(b1) {

	uint indexOffset;
	uint indexCount;
	uint subMeshIndex;
	uint _pad0;
};
cbuffer MeshDrawConstants : register(b0, space1) {

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
	uint subMeshGroupIndex;
	float maxDisplacement;
	uint4 lodIndexOffsets;
	uint4 lodIndexCounts;
	uint4 lodMeshletOffsets;
	uint4 lodMeshletCounts;
	float3 lodPixelThresholds;
	uint lodCount;
};
// 共有GPU構造体はmeshShaderSharedTypes.hlsliへ集約済み

struct MeshDispatchPayload {

	uint meshletIndices[32];
	uint instanceIndices[32];
};

StructuredBuffer<MeshPackedVertex> gPackedVertices : register(t0);
StructuredBuffer<uint> gIndices : register(t1);
StructuredBuffer<uint> gVertexSubMeshIndices : register(t9);
StructuredBuffer<MeshInstance> gMeshInstances : register(t2);
StructuredBuffer<MeshVertex> gSkinnedVertices : register(t4, space1);
StructuredBuffer<MeshPackedVertex> gSkinnedPackedVertices : register(t6, space1);
StructuredBuffer<MeshletDrawDesc> gMeshlets : register(t0, space1);
StructuredBuffer<uint> gMeshletVertexIndices : register(t1, space1);
StructuredBuffer<uint> gMeshletPrimitiveIndices : register(t2, space1);
StructuredBuffer<SubMeshShaderData> gSubMeshes : register(t3, space1);
StructuredBuffer<MeshletBounds> gMeshletBounds : register(t4, space1);
StructuredBuffer<uint> gPackedMeshletVertexIndices : register(t5, space1);
Texture2D<float> gOcclusionDepthPyramid : register(t7, space1);

#include "meshPBRMaterial.hlsli"

#define NEM_OCCLUSION_DEPTH_PYRAMID gOcclusionDepthPyramid
#include "../../Common/CullingHelpers.hlsli"

//============================================================================
//	functions
//============================================================================
SubMeshShaderData GetInstanceSubMesh(uint instanceID, uint localSubMeshIndex) {

	MeshInstance instance = gMeshInstances[instanceID];
	uint safeCount = max(instance.subMeshCount, 1u);
	uint clampedSubMeshIndex = min(localSubMeshIndex, safeCount - 1u);

	return gSubMeshes[instance.subMeshDataOffset + clampedSubMeshIndex];
}

bool IsSubMeshRenderGroupVisible(uint instanceID, uint localSubMeshIndex) {

	return subMeshGroupIndex == 0xFFFFFFFFu ||
		GetInstanceSubMesh(instanceID, localSubMeshIndex).renderGroupIndex ==
			subMeshGroupIndex;
}

float4x4 GetInstanceSubMeshWorldMatrix(uint instanceID, uint localSubMeshIndex) {

	MeshInstance instance = gMeshInstances[instanceID];
	SubMeshShaderData subMesh = GetInstanceSubMesh(instanceID, localSubMeshIndex);

	return mul(subMesh.localMatrix, instance.worldMatrix);
}

float4x4 GetInstanceSubMeshPreviousWorldMatrix(
	uint instanceID, uint localSubMeshIndex) {

	MeshInstance instance = gMeshInstances[instanceID];
	SubMeshShaderData subMesh = GetInstanceSubMesh(
		instanceID, localSubMeshIndex);
	float4x4 previousWorld = instance.motionFrameSerial == frameSerial ?
		instance.previousWorldMatrix : instance.worldMatrix;
	return mul(subMesh.localMatrix, previousWorld);
}

// 法線変換行列を合成する、CPUで構築済みなのでinverseは呼ばない
float4x4 GetInstanceSubMeshNormalMatrix(uint instanceID, uint localSubMeshIndex) {

	MeshInstance instance = gMeshInstances[instanceID];
	SubMeshShaderData subMesh = GetInstanceSubMesh(instanceID, localSubMeshIndex);

	return mul(subMesh.localNormalMatrix, instance.normalMatrix);
}

// 負スケールが奇数個で-1になる向き符号、従法線の向き補正に使う
float GetInstanceSubMeshOrientationSign(uint instanceID, uint localSubMeshIndex) {

	MeshInstance instance = gMeshInstances[instanceID];
	SubMeshShaderData subMesh = GetInstanceSubMesh(instanceID, localSubMeshIndex);

	return instance.orientationSign * subMesh.localOrientationSign;
}

// 法線をワールドへ変換する、向きはnormalMatrixを使う
float3 TransformMeshNormalToWorld(float3 localNormal, float4x4 normalMatrix) {

	return normalize(mul(localNormal, (float3x3) normalMatrix));
}

// 接線をワールドへ変換する、位置と同じworldMatrixの線形部を使う
float3 TransformMeshTangentToWorld(float3 localTangent, float4x4 worldMatrix) {

	return normalize(mul(localTangent, (float3x3) worldMatrix));
}

// 接線符号とTransformの向き符号から、向きを合わせた従法線を作る
float3 BuildMeshBitangent(float3 worldNormal, float3 worldTangent, float tangentSign, float orientationSign) {

	return cross(worldNormal, worldTangent) * (tangentSign * orientationSign);
}

// PS共通のTBN行列を構築する、tangentSignとorientationSignで従法線の向きを補正する
float3x3 BuildMeshTBN(VSOutput input) {

	float3 N = normalize(input.normal);
	// Gram-Schmidtで接線を再直交化
	float3 T = normalize(input.tangent - dot(input.tangent, N) * N);
	float3 B = BuildMeshBitangent(N, T, input.tangentSign, input.orientationSign);
	return float3x3(T, B, N);
}

uint3 UnpackPrimitiveIndex(uint packedIndex) {

	return uint3(
		packedIndex & 0x3FF,
		(packedIndex >> 10) & 0x3FF,
		(packedIndex >> 20) & 0x3FF);
}

float3 DecodeOctNormal(uint packedNormal) {

	int sx = (int)(packedNormal << 16) >> 16;
	int sy = (int)packedNormal >> 16;
	float2 f = float2(sx, sy) / 32767.0f;
	float3 n = float3(f.x, f.y, 1.0f - abs(f.x) - abs(f.y));
	if (n.z < 0.0f) {

		float2 old = n.xy;
		n.x = (1.0f - abs(old.y)) * (old.x >= 0.0f ? 1.0f : -1.0f);
		n.y = (1.0f - abs(old.x)) * (old.y >= 0.0f ? 1.0f : -1.0f);
	}
	return normalize(n);
}

MeshVertex DecodePackedVertex(MeshPackedVertex vertex) {

	MeshVertex outVertex;
	outVertex.normal = DecodeOctNormal(vertex.normalOct);
	outVertex.tangent = DecodeOctNormal(vertex.tangentOct);
	outVertex.tangentSign = vertex.tangentSign;
	outVertex.uv = vertex.uv;
	outVertex.position = vertex.position;
	return outVertex;
}

#if defined(NEM_ENABLE_MESH_DISPLACEMENT)
// 頂点シェーダーからSamplerを増やさず使用できる繰り返しバイリニアサンプル
float SampleMeshDisplacement(uint textureIndex, float2 uv) {

	Texture2D<float4> texture =
		ResourceDescriptorHeap[NonUniformResourceIndex(textureIndex)];
	uint width;
	uint height;
	texture.GetDimensions(width, height);

	const int2 dimensions = int2(max(width, 1u), max(height, 1u));
	const float2 texelPosition = frac(uv) * float2(dimensions) - 0.5f;
	const int2 baseTexel = int2(floor(texelPosition));
	const float2 blend = frac(texelPosition);

	const int2 p00 = (baseTexel % dimensions + dimensions) % dimensions;
	const int2 p10 =
		((baseTexel + int2(1, 0)) % dimensions + dimensions) % dimensions;
	const int2 p01 =
		((baseTexel + int2(0, 1)) % dimensions + dimensions) % dimensions;
	const int2 p11 =
		((baseTexel + int2(1, 1)) % dimensions + dimensions) % dimensions;
	const float top = lerp(
		texture.Load(int3(p00, 0)).r,
		texture.Load(int3(p10, 0)).r, blend.x);
	const float bottom = lerp(
		texture.Load(int3(p01, 0)).r,
		texture.Load(int3(p11, 0)).r, blend.x);
	return lerp(top, bottom, blend.y);
}

// DisplacementのRチャンネルをローカル法線方向の頂点変位へ変換
MeshVertex ApplyMeshDisplacement(
	MeshVertex vertex, uint instanceID, uint localSubMeshIndex) {

	const MeshMaterialParameters material =
		GetInstanceMeshMaterialParameters(instanceID, localSubMeshIndex);
	if (material.displacementTexture == 0xFFFFFFFFu ||
		abs(material.displacementScale) <= 0.000001f) {

		return vertex;
	}

	const SubMeshShaderData subMesh =
		GetInstanceSubMesh(instanceID, localSubMeshIndex);
	const float2 uv = mul(float4(vertex.uv, 0.0f, 1.0f),
		subMesh.uvMatrix).xy;
	const float height = SampleMeshDisplacement(
		material.displacementTexture, uv);
	const float offset = (height - material.displacementMidpoint) *
		material.displacementScale;
	vertex.position.xyz += normalize(vertex.normal) * offset;
	return vertex;
}
#endif

uint LoadMeshletVertexIndex(uint index) {

	if (packedMeshletVertexIndices == 0u) {
		return gMeshletVertexIndices[index];
	}

	uint packedPair = gPackedMeshletVertexIndices[index >> 1];
	if ((index & 1u) == 0u) {
		return packedPair & 0xFFFFu;
	}
	return (packedPair >> 16) & 0xFFFFu;
}

MeshVertex LoadMeshVertex(uint instanceID, uint vertexIndex) {

	MeshInstance instance = gMeshInstances[instanceID];
	MeshVertex vertex;
	if ((instance.flags & MESH_INSTANCE_FLAG_SKINNED) != 0u) {

		vertex = DecodePackedVertex(
			gSkinnedPackedVertices[instance.skinnedVertexOffset + vertexIndex]);
	} else {

		vertex = DecodePackedVertex(gPackedVertices[vertexIndex]);
	}
#if defined(NEM_ENABLE_MESH_DISPLACEMENT)
	return ApplyMeshDisplacement(
		vertex, instanceID, gVertexSubMeshIndices[vertexIndex]);
#else
	return vertex;
#endif
}

float CalcProjectedPixelRadius(float3 center, float radius) {

	float2 radiusXY = CalcProjectedPixelRadiusXY(
		cullingViewProjection, cullingView, cullingNearClip, cullingProjectionScale,
		cullingViewSize, contributionPixelThreshold, center, radius);
	return max(radiusXY.x, radiusXY.y);
}

uint ResolveMeshLOD(MeshInstance instance) {

	if (lodCount <= 1u ||
		(instance.flags & MESH_INSTANCE_FLAG_SKINNED) != 0u) {
		return 0u;
	}

	float3 center = mul(float4(meshBoundsCenter, 1.0f), instance.worldMatrix).xyz;
	float radius = meshBoundsRadius * GetMatrixMaxScale(instance.worldMatrix);
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

bool HasContribution(float3 center, float radius) {

	if (contributionCullingEnabled == 0u) {
		return true;
	}
	return CalcProjectedPixelRadius(center, radius) >= contributionPixelThreshold;
}

bool IsNormalConeVisible(MeshletBounds bounds, float3 center, float3x3 normalMatrix) {

	if (normalConeCullingEnabled == 0u || bounds.coneCutoff < 0.5f) {
		return true;
	}

	// coneAxisは法線方向なので、非一様スケールでもnormalMatrixで変換する
	float3 axis = normalize(mul(bounds.coneAxis, normalMatrix));
	float3 viewDir = normalize(cullingCameraPos - center);
	float coneAngleSin = sqrt(saturate(1.0f - bounds.coneCutoff * bounds.coneCutoff));
	return dot(axis, viewDir) > -coneAngleSin;
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

bool IsMeshletVisible(uint meshletIndex, uint instanceIndex) {

	MeshletDrawDesc meshlet = gMeshlets[meshletIndex];
	if (!IsSubMeshRenderGroupVisible(
		instanceIndex, meshlet.subMeshIndex)) {
		return false;
	}
	if (cullingEnabled == 0u) {
		return true;
	}

	float4x4 worldMatrix = GetInstanceSubMeshWorldMatrix(instanceIndex, meshlet.subMeshIndex);
	float4x4 normalMatrix = GetInstanceSubMeshNormalMatrix(instanceIndex, meshlet.subMeshIndex);
	MeshletBounds bounds = gMeshletBounds[meshletIndex];
	float3 center = mul(float4(bounds.center, 1.0f), worldMatrix).xyz;
	// 背面法アウトラインは元形状より外へ膨張するため、Boundsを安全側へ広げる
	float localRadius = bounds.radius + maxDisplacement;
	if (invertedHullOutlinePass != 0u) {
		localRadius += outlineMaxModelExpansion;
	}
	float radius = localRadius * GetMatrixMaxScale(worldMatrix);
	if (invertedHullOutlinePass != 0u) {
		radius += outlineMaxAbsCameraZOffset;
	}
	if (frustumCullingEnabled != 0u &&
		!IsSphereInFrustum(cullingViewProjection, center, radius)) {
		return false;
	}
	if (!HasContribution(center, radius)) {
		return false;
	}
	if (!IsNormalConeVisible(bounds, center, (float3x3)normalMatrix)) {
		return false;
	}
	if (IsSphereOccluded(center, radius)) {
		return false;
	}
	return true;
}

// VS経路のVSOutputを構築する、各PS系で共通の頂点処理
VSOutput BuildMeshSurfaceVertex(uint vertexID, uint instanceID) {

	MeshVertex vertex = LoadMeshVertex(instanceID, vertexID);

	// 頂点が属するサブメッシュのローカル行列を親行列に掛ける
	uint localSubMeshIndex = gVertexSubMeshIndices[vertexID];
	float4x4 worldMatrix = GetInstanceSubMeshWorldMatrix(instanceID, localSubMeshIndex);
	float4x4 normalMatrix = GetInstanceSubMeshNormalMatrix(instanceID, localSubMeshIndex);
	float4 worldPos = mul(vertex.position, worldMatrix);
	float4x4 previousWorldMatrix = GetInstanceSubMeshPreviousWorldMatrix(
		instanceID, localSubMeshIndex);
	float4 previousWorldPos = mul(vertex.position, previousWorldMatrix);

	VSOutput output;

	output.position = mul(worldPos, viewProjection);
	output.currentClipPosition = output.position;
	output.previousClipPosition =
		(gMeshInstances[instanceID].flags & MESH_INSTANCE_FLAG_SKINNED) != 0u ?
		output.position : mul(previousWorldPos, previousViewProjection);
	output.worldPos = worldPos.xyz;
	// 法線はnormalMatrix、接線は位置と同じworldMatrixで変換する
	output.normal = TransformMeshNormalToWorld(vertex.normal, normalMatrix);
	output.tangent = TransformMeshTangentToWorld(vertex.tangent, worldMatrix);
	output.uv = vertex.uv;
	output.instanceID = instanceID;
	output.subMeshIndex = localSubMeshIndex;
	output.tangentSign = vertex.tangentSign;
	output.orientationSign = GetInstanceSubMeshOrientationSign(instanceID, localSubMeshIndex);
	if (!IsSubMeshRenderGroupVisible(instanceID, localSubMeshIndex)) {
		// VS経路ではグループ外の頂点をfar面の外へ送りラスタライズしない
		output.position.z = output.position.w * 2.0f;
		output.currentClipPosition = output.position;
		output.previousClipPosition = output.position;
	}

	return output;
}

#endif // NEM_DEFAULT_MESH_HLSLI
