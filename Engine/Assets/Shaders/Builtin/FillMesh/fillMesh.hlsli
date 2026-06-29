#ifndef NEM_FILL_MESH_HLSLI
#define NEM_FILL_MESH_HLSLI

//============================================================================
//	FillMesh 共有型
//============================================================================
struct FillMeshVertex {

	float4 position;
	float4 normal;
};

struct VSOutput {

	float4 position : SV_POSITION;
	float3 worldPos : TEXCOORD0;
	float3 normal : TEXCOORD1;
};

#endif // NEM_FILL_MESH_HLSLI
