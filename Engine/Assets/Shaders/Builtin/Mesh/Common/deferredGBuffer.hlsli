#ifndef NEM_DEFERRED_GBUFFER_HLSLI
#define NEM_DEFERRED_GBUFFER_HLSLI

//============================================================================
//	include
//============================================================================
#include "meshShaderSharedTypes.hlsli"

//============================================================================
//	Deferred GBuffer hlsli
//============================================================================

// ライティング対象の不透明マテリアルフラグ
static const uint kMaterialFlagSurface = 1u;
// ライティングや影の適用フラグ、MeshRenderFlagsからinstance経由で写される
static const uint kMaterialFlagLighting = 1u << 1;
static const uint kMaterialFlagReceiveShadow = 1u << 2;
static const uint kMaterialFlagReceiveIBL = 1u << 3;
static const uint kMaterialFlagReceiveReflection = 1u << 4;
// 上位24bitはRendererの描画対象マスクとして保持する
static const uint kRenderingLayerMaskShift = 8u;
static const uint kRenderingLayerMaskBits = 0x00FFFFFFu;
// フラグを持たない描画で使う全適用のデフォルト値
static const uint kMaterialFlagLightingDefault =
	kMaterialFlagLighting | kMaterialFlagReceiveShadow | kMaterialFlagReceiveIBL | kMaterialFlagReceiveReflection;

//============================================================================
//	GBuffer書き込み構造体
//============================================================================
struct GBufferOutput {

	float4 albedo : SV_TARGET0; // RGB アルベド
	float4 normal : SV_TARGET1; // RGB ワールド法線
	float4 worldPos : SV_TARGET2; // RGB ワールド座標
	float4 material : SV_TARGET3; // R メタリック, G ラフネス, B 遮蔽、オクリュージョン
	float4 emissive : SV_TARGET4; // RGB 発光色
	uint flags : SV_TARGET5; // マテリアルフラグ
	float2 motion : SV_TARGET6; // 現在UVから前フレームUVへの移動量
};

struct MeshSurface {

	float3 albedo;
	float3 normal;
	float3 worldPos;
	float metallic;
	float roughness;
	float occlusion;
	float3 emissive;
	float2 motion;
	// kMaterialFlag*のライティング適用フラグ
	uint flags;
};

// MeshInstanceのflagsからGBufferへ書くマテリアルフラグを作る
uint BuildMaterialFlags(uint instanceFlags) {

	uint flags = 0u;
	if (instanceFlags & MESH_INSTANCE_FLAG_LIGHTING) {
		flags |= kMaterialFlagLighting;
	}
	if (instanceFlags & MESH_INSTANCE_FLAG_RECEIVE_SHADOW) {
		flags |= kMaterialFlagReceiveShadow;
	}
	if (instanceFlags & MESH_INSTANCE_FLAG_RECEIVE_IBL) {
		flags |= kMaterialFlagReceiveIBL;
	}
	if (instanceFlags & MESH_INSTANCE_FLAG_RECEIVE_REFLECTION) {
		flags |= kMaterialFlagReceiveReflection;
	}
	flags |= instanceFlags &
		(kRenderingLayerMaskBits <<
			kRenderingLayerMaskShift);
	return flags;
}

uint PackRenderingLayerMask(
	uint renderingLayerMask) {

	return (renderingLayerMask &
		kRenderingLayerMaskBits) <<
		kRenderingLayerMaskShift;
}

// メッシュサーフェイスをGBufferに設定して返す
GBufferOutput EncodeGBuffer(MeshSurface surface) {

	GBufferOutput output;
	output.albedo = float4(surface.albedo, 1.0f);
	output.normal = float4(surface.normal * 0.5f + 0.5f, 1.0f);
	output.worldPos = float4(surface.worldPos, 1.0f);
	output.material = float4(surface.metallic, surface.roughness, surface.occlusion, 1.0f);
	output.emissive = float4(surface.emissive, 1.0f);
	output.flags = kMaterialFlagSurface | surface.flags;
	output.motion = surface.motion;
	return output;
}

float2 ComputeGBufferMotion(float4 currentClip, float4 previousClip) {

	if (currentClip.w <= 0.0f || previousClip.w <= 0.0f) {
		return 0.0f.xx;
	}
	float2 currentNDC = currentClip.xy / currentClip.w;
	float2 previousNDC = previousClip.xy / previousClip.w;
	float2 currentUV = currentNDC * float2(0.5f, -0.5f) + 0.5f;
	float2 previousUV = previousNDC * float2(0.5f, -0.5f) + 0.5f;
	return currentUV - previousUV;
}
#endif // NEM_DEFERRED_GBUFFER_HLSLI
