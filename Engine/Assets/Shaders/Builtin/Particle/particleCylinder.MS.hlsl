//============================================================================
//	include
//============================================================================
#include "particle.hlsli"

//============================================================================
//	resources
//============================================================================
cbuffer ParticleShapeConstants : register(b1) {

	uint divide;
	uint3 _pad;
};
StructuredBuffer<ParticleInstance> gInstances : register(t1);

#define PARTICLE_GROUP_TRIANGLES 64

//============================================================================
//	main
//============================================================================
[numthreads(PARTICLE_GROUP_TRIANGLES, 1, 1)]
[outputtopology("triangle")]
void main(uint groupThreadID : SV_GroupThreadID, uint3 groupID : SV_GroupID,
	out vertices VSOutput verts[PARTICLE_GROUP_TRIANGLES * 3],
	out indices uint3 tris[PARTICLE_GROUP_TRIANGLES]) {

	const uint totalTriangles = divide * 2u;
	const uint triangleBase = groupID.x * PARTICLE_GROUP_TRIANGLES;
	// SetMeshOutputCountsは全パスで1回だけ呼ぶ、範囲外グループは0件にする
	const uint triangleCount = (triangleBase < totalTriangles) ?
		min((uint)PARTICLE_GROUP_TRIANGLES, totalTriangles - triangleBase) : 0u;
	SetMeshOutputCounts(triangleCount * 3u, triangleCount);

	if (groupThreadID >= triangleCount) {
		return;
	}

	ParticleInstance instance = gInstances[groupID.y];
	// 粒子ごとの形状パラメータ、x=上面半径 y=下面半径 z=高さ w=展開角
	const float topRadius = instance.shapeParams.x;
	const float bottomRadius = instance.shapeParams.y;
	const float halfHeight = instance.shapeParams.z * 0.5f;
	const float angleStep = instance.shapeParams.w / (float)divide;

	const uint triangleIndex = triangleBase + groupThreadID;
	const uint segment = triangleIndex / 2u;
	const uint half = triangleIndex % 2u;

	// セグメントの下面上面4頂点から側面の三角形2枚を張る
	uint cornerSegments[3];
	uint cornerTops[3];
	if (half == 0u) {
		cornerSegments[0] = segment; cornerTops[0] = 0u;
		cornerSegments[1] = segment + 1u; cornerTops[1] = 0u;
		cornerSegments[2] = segment; cornerTops[2] = 1u;
	} else {
		cornerSegments[0] = segment; cornerTops[0] = 1u;
		cornerSegments[1] = segment + 1u; cornerTops[1] = 0u;
		cornerSegments[2] = segment + 1u; cornerTops[2] = 1u;
	}

	for (uint k = 0; k < 3u; ++k) {

		const float angle = angleStep * (float)cornerSegments[k];
		const float radius = cornerTops[k] != 0u ? topRadius : bottomRadius;
		const float y = cornerTops[k] != 0u ? halfHeight : -halfHeight;
		const float3 localPos = float3(cos(angle) * radius, y, sin(angle) * radius);
		const float2 uv = float2((float)cornerSegments[k] / (float)divide, cornerTops[k] != 0u ? 0.0f : 1.0f);

		VSOutput output;
		float4 worldPos = mul(float4(localPos, 1.0f), instance.worldMatrix);
		output.position = mul(worldPos, viewProjection);
		output.texcoord = uv * instance.uvScaleOffset.xy + instance.uvScaleOffset.zw;
		output.color = instance.color;
		output.emissive = instance.emissive;
		output.materialParams = instance.materialParams;
		verts[groupThreadID * 3u + k] = output;
	}
	tris[groupThreadID] = uint3(groupThreadID * 3u, groupThreadID * 3u + 1u, groupThreadID * 3u + 2u);
}
