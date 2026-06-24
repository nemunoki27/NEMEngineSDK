#ifndef NEM_DEFERRED_GBUFFER_HLSLI
#define NEM_DEFERRED_GBUFFER_HLSLI

//============================================================================
//	Deferred GBuffer hlsli
//============================================================================

// ライティング対象の不透明マテリアルフラグ
static const uint kMaterialFlagSurface = 1u;

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
};

struct MeshSurface {

	float3 albedo;
	float3 normal;
	float3 worldPos;
	float metallic;
	float roughness;
	float occlusion;
	float3 emissive;
};

// メッシュサーフェイスをGBufferに設定して返す
GBufferOutput EncodeGBuffer(MeshSurface surface) {

	GBufferOutput output;
	output.albedo = float4(surface.albedo, 1.0f);
	output.normal = float4(surface.normal * 0.5f + 0.5f, 1.0f);
	output.worldPos = float4(surface.worldPos, 1.0f);
	output.material = float4(surface.metallic, surface.roughness, surface.occlusion, 1.0f);
	output.emissive = float4(surface.emissive, 1.0f);
	output.flags = kMaterialFlagSurface;
	return output;
}
#endif // NEM_DEFERRED_GBUFFER_HLSLI