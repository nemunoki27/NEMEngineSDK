//============================================================================
//	include
//============================================================================
#include "primitive.hlsli"
#include "../Mesh/Common/meshShaderSharedTypes.hlsli"

//============================================================================
//	resources
//============================================================================
cbuffer PrimitiveMeshConstants : register(b1) {

	uint indexCount;
	uint3 _pad;
};
StructuredBuffer<MeshVertex> gVertices : register(t0);
StructuredBuffer<PrimitiveInstance> gInstances : register(t1);
StructuredBuffer<uint> gIndices : register(t2);

//============================================================================
//	main
//	1スレッド1三角形、頂点は共有せず展開する汎用のvertex-fetch
//============================================================================
#define PRIMITIVE_GROUP_TRIANGLES 64

[numthreads(PRIMITIVE_GROUP_TRIANGLES, 1, 1)]
[outputtopology("triangle")]
void main(uint groupThreadID : SV_GroupThreadID, uint3 groupID : SV_GroupID,
	out vertices VSOutput verts[PRIMITIVE_GROUP_TRIANGLES * 3],
	out indices uint3 tris[PRIMITIVE_GROUP_TRIANGLES]) {

	const uint totalTriangles = indexCount / 3u;
	const uint triangleBase = groupID.x * PRIMITIVE_GROUP_TRIANGLES;
	// SetMeshOutputCountsは全パスで1回だけ呼ぶ、範囲外グループは0件にする
	const uint triangleCount = (triangleBase < totalTriangles) ?
		min((uint)PRIMITIVE_GROUP_TRIANGLES, totalTriangles - triangleBase) : 0u;
	SetMeshOutputCounts(triangleCount * 3u, triangleCount);

	if (groupThreadID >= triangleCount) {
		return;
	}

	PrimitiveInstance instance = gInstances[groupID.y];
	const uint localTriangle = groupThreadID;
	const uint indexBase = (triangleBase + localTriangle) * 3u;

	for (uint k = 0; k < 3u; ++k) {

		MeshVertex v = gVertices[gIndices[indexBase + k]];
		VSOutput output;
		float4 worldPos = mul(float4(v.position.xyz, 1.0f), instance.worldMatrix);
		output.position = mul(worldPos, viewProjection);
		output.worldPos = worldPos.xyz;
		output.normal = normalize(mul(v.normal, (float3x3)instance.worldMatrix));
		output.tangent = normalize(mul(v.tangent, (float3x3)instance.worldMatrix));
		output.tangentSign = v.tangentSign;
		output.texcoord = mul(float4(v.uv, 0.0f, 1.0f), instance.uvMatrix).xy;
		output.flags = instance.flags;
		output.vertexColor = ResolvePrimitiveVertexColor(v.position.xyz, instance);
		verts[localTriangle * 3u + k] = output;
	}
	tris[localTriangle] = uint3(localTriangle * 3u, localTriangle * 3u + 1u, localTriangle * 3u + 2u);
}
