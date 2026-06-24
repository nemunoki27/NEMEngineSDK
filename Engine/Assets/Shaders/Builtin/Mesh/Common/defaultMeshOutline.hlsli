//============================================================================
//	背面法アウトライン 共通定義
//============================================================================
#include "defaultMesh.hlsli"

//============================================================================
//	定数
//============================================================================
static const uint OUTLINE_EXPANSION_NORMAL_DIRECTION = 0u;
static const uint OUTLINE_EXPANSION_POSITION_SCALING = 1u;
static const uint OUTLINE_WIDTH_MODEL_UNITS = 0u;
static const uint OUTLINE_WIDTH_SCREEN_PIXELS = 1u;
static const uint MESH_OUTLINE_FLAG_USE_BAKED_NORMAL = 1u << 0;
static const uint MESH_OUTLINE_FLAG_USE_OUTLINE_SAMPLER = 1u << 1;

//============================================================================
//	resources
//============================================================================
SamplerState gOutlineSampler : register(s0);

struct MeshOutlineGPUData {

	float4 color;

	float width;
	float cameraZOffset;
	uint expansionMode;
	uint widthMode;

	uint bakedNormalTextureIndex;
	uint outlineSamplerTextureIndex;
	uint flags;
	uint _pad0;
};
// 既存割り当てと衝突しない番号を使う
StructuredBuffer<MeshOutlineGPUData> gMeshOutlines : register(t7, space1);

struct OutlineVertexOutput {

	float4 position : SV_Position;
	nointerpolation float4 color : COLOR0;
};

//============================================================================
//	functions
//============================================================================
// 部位別アウトライン幅の乗数を取得する、VS/MSではSampleLevelを使う
float SampleOutlineWidthMultiplier(MeshOutlineGPUData outline, float2 uv) {

	if ((outline.flags & MESH_OUTLINE_FLAG_USE_OUTLINE_SAMPLER) == 0u ||
		outline.outlineSamplerTextureIndex == 0xFFFFFFFFu) {
		return 1.0f;
	}

	Texture2D<float4> tex = ResourceDescriptorHeap[
		NonUniformResourceIndex(outline.outlineSamplerTextureIndex)];
	return saturate(tex.SampleLevel(gOutlineSampler, uv, 0.0f).r);
}

// Baked Normalがあればそれを、なければ頂点法線を返す
float3 ResolveOutlineLocalNormal(MeshOutlineGPUData outline, MeshVertex vertex) {

	if ((outline.flags & MESH_OUTLINE_FLAG_USE_BAKED_NORMAL) == 0u ||
		outline.bakedNormalTextureIndex == 0xFFFFFFFFu) {
		return normalize(vertex.normal);
	}

	Texture2D<float4> tex = ResourceDescriptorHeap[
		NonUniformResourceIndex(outline.bakedNormalTextureIndex)];
	float3 encoded = tex.SampleLevel(gOutlineSampler, vertex.uv, 0.0f).xyz;
	float3 normal = encoded * 2.0f - 1.0f;
	return normalize(normal);
}

// カメラから頂点へ向かう方向へ押し込むCamera Z Offset
float3 ApplyOutlineCameraZOffset(float3 worldPos, float cameraZOffset) {

	float3 fromCamera = worldPos - renderCameraPos;
	float len = length(fromCamera);
	if (len <= 0.00001f || abs(cameraZOffset) <= 0.00001f) {
		return worldPos;
	}
	return worldPos + fromCamera / len * cameraZOffset;
}

// clip上でXY offsetを加えて画面上の線幅を一定にする
float4 ApplyScreenPixelOutlineOffset(float3 worldPos, float3 worldDirection, float widthPixels) {

	float4 clip = mul(float4(worldPos, 1.0f), viewProjection);
	float4 dirClip = mul(
        float4(worldPos + worldDirection, 1.0f),
        viewProjection
    );

	if (abs(clip.w) <= 0.00001f ||
        abs(dirClip.w) <= 0.00001f) {
		return clip;
	}

	float2 ndc = clip.xy / clip.w;
	float2 dirNdc = dirClip.xy / dirClip.w;
	float2 projectedDirNdc = dirNdc - ndc;

	float2 safeViewSize = max(viewSize, float2(1.0f, 1.0f));

    // NDC方向を画面ピクセル方向へ変換する
	float2 projectedDirPixels =
        projectedDirNdc * safeViewSize * 0.5f;

	float projectedLenPixels = length(projectedDirPixels);
	if (projectedLenPixels <= 0.00001f) {
		return clip;
	}

    // ピクセル空間で正規化する
	float2 pixelOffset =
        normalize(projectedDirPixels) * widthPixels;

    // NDCへ戻す
	float2 ndcOffset =
        pixelOffset * (2.0f / safeViewSize);

	clip.xy += ndcOffset * clip.w;
	return clip;
}

// VS/MS共通の膨張頂点生成
OutlineVertexOutput BuildOutlineVertex(uint instanceID, uint localSubMeshIndex,
	MeshVertex vertex, float4x4 worldMatrix, float4x4 normalMatrix) {

	MeshInstance instance = gMeshInstances[instanceID];
	MeshOutlineGPUData outline = gMeshOutlines[instance.outlineDataIndex];
	SubMeshShaderData subMesh = GetInstanceSubMesh(instanceID, localSubMeshIndex);

	float widthMultiplier = SampleOutlineWidthMultiplier(outline, vertex.uv);
	float3 localNormal = ResolveOutlineLocalNormal(outline, vertex);

	float4 localPos = vertex.position;
	float3 localDirection = localNormal;

	// Position Scalingはピボットからの放射方向へ押し出す
	if (outline.expansionMode == OUTLINE_EXPANSION_POSITION_SCALING) {
		float3 fromPivot = localPos.xyz - subMesh.sourcePivot;
		if (length(fromPivot) > 0.00001f) {
			localDirection = normalize(fromPivot);
		}
	}

	// ModelUnitsはモデル空間で頂点を膨張させる
	if (outline.widthMode == OUTLINE_WIDTH_MODEL_UNITS) {
		localPos.xyz += localDirection * outline.width * widthMultiplier;
	}

	float3 worldPos = mul(localPos, worldMatrix).xyz;
	worldPos = ApplyOutlineCameraZOffset(worldPos, outline.cameraZOffset);

	OutlineVertexOutput output;
	if (outline.widthMode == OUTLINE_WIDTH_SCREEN_PIXELS) {

		// 法線方向はnormalMatrix、位置方向はworldMatrixの線形部で変換する
		float3 worldDirection;
		if (outline.expansionMode == OUTLINE_EXPANSION_NORMAL_DIRECTION) {
			worldDirection = TransformMeshNormalToWorld(localDirection, normalMatrix);
		} else {
			worldDirection = TransformMeshTangentToWorld(localDirection, worldMatrix);
		}
		output.position = ApplyScreenPixelOutlineOffset(
			worldPos, worldDirection, outline.width * widthMultiplier);
	} else {

		output.position = mul(float4(worldPos, 1.0f), viewProjection);
	}
	output.color = outline.color;
	return output;
}
