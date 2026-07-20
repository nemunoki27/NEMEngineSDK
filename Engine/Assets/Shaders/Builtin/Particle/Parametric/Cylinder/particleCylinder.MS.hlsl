//============================================================================
//	include
//============================================================================
#include "../../Common/particle.hlsli"

//============================================================================
//	resources
//============================================================================
cbuffer ParticleShapeConstants : register(b1) {

	uint divide;
	uint uvMode;
	uint cap;
	uint heightDivide;
};

#define PARTICLE_GROUP_TRIANGLES 64

//============================================================================
//	main
//============================================================================
[numthreads(PARTICLE_GROUP_TRIANGLES, 1, 1)]
[outputtopology("triangle")]
void main(uint groupThreadID : SV_GroupThreadID, uint3 groupID : SV_GroupID,
	out vertices VSOutput verts[PARTICLE_GROUP_TRIANGLES * 3],
	out indices uint3 tris[PARTICLE_GROUP_TRIANGLES]) {

	const bool hasTop = cap == 1u || cap == 3u;
	const bool hasBottom = cap == 2u || cap == 3u;
	const uint sideTriangles = divide * heightDivide * 2u;
	const uint topTriangles = hasTop ? divide : 0u;
	const uint bottomTriangles = hasBottom ? divide : 0u;
	const uint totalTriangles = sideTriangles + topTriangles + bottomTriangles;
	const uint triangleBase = groupID.x * PARTICLE_GROUP_TRIANGLES;
	// SetMeshOutputCountsは全パスで1回だけ呼ぶ、範囲外グループは0件にする
	const uint triangleCount = (triangleBase < totalTriangles) ?
		min((uint)PARTICLE_GROUP_TRIANGLES, totalTriangles - triangleBase) : 0u;
	SetMeshOutputCounts(triangleCount * 3u, triangleCount);

	if (groupThreadID >= triangleCount) {
		return;
	}

	ParticleGeometryData instance = gParticleGeometry[groupID.y];
	// params0は上面、中心、下面半径と高さ、params1はWeightと展開角
	const float topRadius = instance.shapeParams0.x;
	const float bottomRadius = instance.shapeParams0.z;
	const float halfHeight = instance.shapeParams0.w * 0.5f;
	const float angleStep = instance.shapeParams1.z / (float)divide;

	const uint triangleIndex = triangleBase + groupThreadID;
	float3 localPositions[3];
	float2 uvs[3];
	if (triangleIndex < sideTriangles) {

		const uint cell = triangleIndex / 2u;
		const uint segment = cell % divide;
		const uint heightSegment = cell / divide;
		const uint half = triangleIndex % 2u;

		// 円周と高さの1セルを三角形2枚へ展開する
		uint cornerSegments[3];
		uint cornerHeights[3];
		if (half == 0u) {
			cornerSegments[0] = segment; cornerHeights[0] = heightSegment;
			cornerSegments[1] = segment + 1u; cornerHeights[1] = heightSegment;
			cornerSegments[2] = segment; cornerHeights[2] = heightSegment + 1u;
		} else {
			cornerSegments[0] = segment; cornerHeights[0] = heightSegment + 1u;
			cornerSegments[1] = segment + 1u; cornerHeights[1] = heightSegment;
			cornerSegments[2] = segment + 1u; cornerHeights[2] = heightSegment + 1u;
		}

		for (uint k = 0; k < 3u; ++k) {

			const float angle = angleStep * (float)cornerSegments[k];
			const float heightT = (float)cornerHeights[k] / (float)heightDivide;
			const float radius = EvaluateParticleCylinderRadius(heightT, instance);
			const float y = lerp(-halfHeight, halfHeight, heightT);
			localPositions[k] = float3(cos(angle) * radius, y, sin(angle) * radius);
			if (uvMode == 1u) {

				const float uvRadius = heightT * 0.5f;
				uvs[k] = float2(
					cos(angle) * uvRadius + 0.5f,
					-sin(angle) * uvRadius + 0.5f);
			} else {

				uvs[k] = float2(
					(float)cornerSegments[k] / (float)divide,
					1.0f - heightT);
			}
		}
	} else {

		const bool isTop = hasTop && triangleIndex < sideTriangles + topTriangles;
		const uint capTriangle = triangleIndex - sideTriangles - (isTop ? 0u : topTriangles);
		const float y = isTop ? halfHeight : -halfHeight;
		const float radius = isTop ? topRadius : bottomRadius;
		const float angle0 = angleStep * (float)capTriangle;
		const float angle1 = angleStep * (float)(capTriangle + 1u);

		// 上面と底面は中心から扇状に三角形を張る
		localPositions[0] = float3(0.0f, y, 0.0f);
		localPositions[1] = isTop ?
			float3(cos(angle0) * radius, y, sin(angle0) * radius) :
			float3(cos(angle1) * radius, y, sin(angle1) * radius);
		localPositions[2] = isTop ?
			float3(cos(angle1) * radius, y, sin(angle1) * radius) :
			float3(cos(angle0) * radius, y, sin(angle0) * radius);
		uvs[0] = float2(0.5f, 0.5f);
		uvs[1] = isTop ?
			float2(cos(angle0) * 0.5f + 0.5f, sin(angle0) * 0.5f + 0.5f) :
			float2(cos(angle1) * 0.5f + 0.5f, sin(angle1) * 0.5f + 0.5f);
		uvs[2] = isTop ?
			float2(cos(angle1) * 0.5f + 0.5f, sin(angle1) * 0.5f + 0.5f) :
			float2(cos(angle0) * 0.5f + 0.5f, sin(angle0) * 0.5f + 0.5f);
	}

	for (uint k = 0; k < 3u; ++k) {

		VSOutput output;
		float4 worldPos = mul(float4(localPositions[k], 1.0f), instance.worldMatrix);
		output.position = mul(worldPos, viewProjection);
		output.texcoord = uvs[k];
		output.vertexColor = ResolveParticleVertexColor(localPositions[k], instance);
		output.particleIndex = groupID.y;
		verts[groupThreadID * 3u + k] = output;
	}
	tris[groupThreadID] = uint3(groupThreadID * 3u, groupThreadID * 3u + 1u, groupThreadID * 3u + 2u);
}
