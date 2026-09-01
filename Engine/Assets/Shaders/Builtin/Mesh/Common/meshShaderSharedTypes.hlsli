#ifndef NEM_MESH_SHADER_SHARED_TYPES_HLSLI
#define NEM_MESH_SHADER_SHARED_TYPES_HLSLI

//============================================================================
//	Mesh描画で共有するGPU構造体、CPU側とfield順とpaddingを一致させる
//============================================================================
struct MeshVertex {

	float3 normal;
	float3 tangent;
	// 法線マップのTBNで従法線の符号に使う
	float tangentSign;
	float2 uv;
	float4 position;
};

struct MeshPackedVertex {

	uint normalOct;
	uint tangentOct;
	float tangentSign;
	float2 uv;
	float4 position;
};

struct MeshletDrawDesc {

	uint vertexOffset;
	uint vertexCount;
	uint primitiveOffset;
	uint primitiveCount;

	uint subMeshIndex;
};

struct MeshletBounds {

	float3 center;
	float radius;
	float3 coneAxis;
	float coneCutoff;
};

struct SubMeshShaderData {

	uint baseColorTextureIndex;
	uint normalTextureIndex;
	uint metallicRoughnessTextureIndex;
	uint emissiveTextureIndex;

	uint occlusionTextureIndex;
	uint specularTextureIndex;
	uint metallicTextureIndex;
	uint roughnessTextureIndex;

	float metallic;
	float roughness;
	float2 _materialPad;

	// 位置やBoundsやCulling用のローカル行列
	float4x4 localMatrix;
	// 法線方向用のローカル法線行列
	float4x4 localNormalMatrix;

	float4 importedBaseColor;
	float4 color;
	float4 emissiveColor;
	float4x4 uvMatrix;

	float3 sourcePivot;
	// 負スケール時に-1になるlocalMatrix線形部の行列式の符号
	float localOrientationSign;

	// 同じMaterialと表面方式をまとめた描画グループ
	uint renderGroupIndex;
	uint3 _renderGroupPad;
};

struct MeshInstance {

	// 位置やBoundsやCulling用のワールド行列
	float4x4 worldMatrix;
	// Transform更新フレームだけ参照する更新前ワールド行列
	float4x4 previousWorldMatrix;
	// 法線方向用のワールド法線行列
	float4x4 normalMatrix;

	uint subMeshDataOffset;
	uint subMeshCount;
	uint flags;
	uint skinnedVertexOffset;

	uint outlineDataIndex;
	// 負スケール時に-1になるworldMatrix線形部の行列式の符号
	float orientationSign;
	uint entityIndex;
	uint entityGeneration;

	// インスタンスごとの乗算色
	float4 color;
	uint motionFrameSerial;
	uint3 _motionPad;
};

static const uint MESH_INSTANCE_FLAG_SKINNED = 1u;
// MeshRenderFlagsから写されるライティング適用フラグ
static const uint MESH_INSTANCE_FLAG_LIGHTING = 1u << 1;
static const uint MESH_INSTANCE_FLAG_RECEIVE_SHADOW = 1u << 2;
static const uint MESH_INSTANCE_FLAG_RECEIVE_IBL = 1u << 3;
static const uint MESH_INSTANCE_FLAG_RECEIVE_REFLECTION = 1u << 4;

#endif // NEM_MESH_SHADER_SHARED_TYPES_HLSLI
