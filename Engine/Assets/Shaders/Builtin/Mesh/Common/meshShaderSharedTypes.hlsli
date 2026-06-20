#ifndef NEM_MESH_SHADER_SHARED_TYPES_HLSLI
#define NEM_MESH_SHADER_SHARED_TYPES_HLSLI

//============================================================================
//	Mesh描画で共有するGPU構造体定義
//	CPU側 (MeshResourceTypes.h / MeshShaderSharedTypes.h / MeshBatchResources.h)
// とfield順・paddingを完全一致させること
// 複数シェーダへ同じstructをコピーせず、必ずこのヘッダをincludeする
//============================================================================
struct MeshVertex {

	float3 normal;
	float3 tangent;
	// 接線の利き手(bitangentの向き)。法線マップのTBNで従法線の符号に使う
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
	float metallic;
	float roughness;

	// 位置・Bounds・Culling用のローカル行列
	float4x4 localMatrix;
	// 法線方向用のローカル法線行列 transpose(inverse(localMatrix))
	float4x4 localNormalMatrix;

	float4 importedBaseColor;
	float4 color;
	float4 emissiveColor;
	float4x4 uvMatrix;

	float3 sourcePivot;
	// localMatrixの線形部の行列式の符号。負スケール(mirror)時に-1
	float localOrientationSign;
};

struct MeshInstance {

	// 位置・Bounds・Culling用のワールド行列
	float4x4 worldMatrix;
	// 法線方向用のワールド法線行列 transpose(inverse(worldMatrix))
	float4x4 normalMatrix;

	uint subMeshDataOffset;
	uint subMeshCount;
	uint flags;
	uint skinnedVertexOffset;

	uint outlineDataIndex;
	// worldMatrixの線形部の行列式の符号。負スケール(mirror)時に-1
	float orientationSign;
	uint2 _outlinePad;

	// per-instanceの乗算色tint
	float4 color;
};

static const uint MESH_INSTANCE_FLAG_SKINNED = 1u;

#endif // NEM_MESH_SHADER_SHARED_TYPES_HLSLI
