#ifndef NEM_DEFERRED_GBUFFER_HLSLI
#define NEM_DEFERRED_GBUFFER_HLSLI

//============================================================================
//	Deferred GBufferの共通レイアウト
//	SceneMainのcolorアタッチメント並びと一致させる、メッシュPSの書き込み側で使う
//	color0 albedo / color1 normal / color2 worldPos / color3 material / color4 emissive / color5 flags
//============================================================================

// SceneFlagsMainへ書くマテリアルフラグ、0クリアの背景画素と区別する
static const uint kMaterialFlagSurface = 1u; // ライティング対象の不透明サーフェスが存在する

//============================================================================
//	GBuffer書き込み構造体
//============================================================================
struct GBufferOutput {

	float4 albedo : SV_TARGET0;   // rgb albedo
	float4 normal : SV_TARGET1;   // rgb worldNormal*0.5+0.5
	float4 worldPos : SV_TARGET2; // rgb worldPosition
	float4 material : SV_TARGET3; // r metallic, g roughness, b occlusion
	float4 emissive : SV_TARGET4; // rgb emissive、αは描画時αブレンドを通すため常に1
	uint flags : SV_TARGET5;      // materialFlags
};

// PS側で組み立てるサーフェス値、エンコード前の生の値を持つ
struct MeshSurface {

	float3 albedo;
	float3 normal;
	float3 worldPos;
	float metallic;
	float roughness;
	float occlusion;
	float3 emissive;
};

// MeshSurfaceをGBufferのレイアウトへ詰める、法線は0..1へ寄せて格納する
GBufferOutput EncodeGBuffer(MeshSurface surface) {

	GBufferOutput o;
	o.albedo = float4(surface.albedo, 1.0f);
	o.normal = float4(surface.normal * 0.5f + 0.5f, 1.0f);
	o.worldPos = float4(surface.worldPos, 1.0f);
	o.material = float4(surface.metallic, surface.roughness, surface.occlusion, 1.0f);
	o.emissive = float4(surface.emissive, 1.0f);
	o.flags = kMaterialFlagSurface;
	return o;
}

#endif // NEM_DEFERRED_GBUFFER_HLSLI
