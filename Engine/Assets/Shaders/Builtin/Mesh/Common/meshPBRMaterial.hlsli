#ifndef NEM_MESH_PBR_MATERIAL_HLSLI
#define NEM_MESH_PBR_MATERIAL_HLSLI

// PBRのサブメッシュ単位マテリアルパラメータ、メンバ名と並びと16整列はCPU pack前提で変えない
struct MeshMaterialParameters {

	float4 color;
	float4 emissiveColor;

	uint baseColorTexture;
	uint normalTexture;
	uint emissiveTexture;
	uint metallicRoughnessTexture;

	uint occlusionTexture;
	float Metallic;
	float Roughness;
	float emissiveIntensity;
};
StructuredBuffer<MeshMaterialParameters> gMeshMaterialParameters : register(t0, space3);

// gSubMeshesと同じインスタンス×サブメッシュのindexで対応するパラメータを取り出す
MeshMaterialParameters GetInstanceMeshMaterialParameters(uint instanceID, uint localSubMeshIndex) {

	MeshInstance instance = gMeshInstances[instanceID];
	uint safeCount = max(instance.subMeshCount, 1u);
	uint clampedSubMeshIndex = min(localSubMeshIndex, safeCount - 1u);

	return gMeshMaterialParameters[instance.subMeshDataOffset + clampedSubMeshIndex];
}

#endif // NEM_MESH_PBR_MATERIAL_HLSLI
