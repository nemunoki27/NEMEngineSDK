//============================================================================
//	include
//============================================================================
#include "lineGeometry.hlsli"
#include "lineTube.hlsli"

//============================================================================
//	resources
//============================================================================
cbuffer ViewConstants : register(b0) {

	float4x4 viewMatrix;
	float4x4 projectionMatrix;

	float2 viewportSize;
	float nearClip;
	float feather;
};

//============================================================================
//	local
//============================================================================
#define TUBE_SIDES 6
static const float kTwoPi = 6.28318530718f;

float4 WorldToClip(float3 worldPos) {

	float3 viewPos = mul(float4(worldPos, 1.0f), viewMatrix).xyz;
	return mul(float4(viewPos, 1.0f), projectionMatrix);
}

//============================================================================
//	main
//============================================================================
[maxvertexcount(26)]
void main(line VSOutput input[2], inout TriangleStream<TubeGSOutput> triStream) {

	float3 p0 = input[0].position;
	float3 p1 = input[1].position;
	float r0 = max(input[0].thickness, 0.001f) * 0.5f;
	float r1 = max(input[1].thickness, 0.001f) * 0.5f;
	float4 color0 = input[0].color;
	float4 color1 = input[1].color;

	float3 dir = p1 - p0;
	if (dot(dir, dir) < 1e-12f) {
		return;
	}
	dir = normalize(dir);

	// 線方向に垂直な基底を安定して作る、ほぼ上向きならフォールバックする
	float3 up = (abs(dir.y) < 0.99f) ? float3(0.0f, 1.0f, 0.0f) : float3(1.0f, 0.0f, 0.0f);
	float3 right = normalize(cross(up, dir));
	up = cross(dir, right);

	// リング方向を先に作る
	float3 ring[TUBE_SIDES + 1];
	[unroll]
	for (int k = 0; k <= TUBE_SIDES; ++k) {
		float angle = kTwoPi * (float)k / (float)TUBE_SIDES;
		ring[k] = cos(angle) * right + sin(angle) * up;
	}

	// チューブ側面の三角ストリップ
	[unroll]
	for (int i = 0; i <= TUBE_SIDES; ++i) {

		TubeGSOutput v0;
		v0.position = WorldToClip(p0 + ring[i] * r0);
		v0.color = color0;
		v0.worldNormal = ring[i];
		triStream.Append(v0);

		TubeGSOutput v1;
		v1.position = WorldToClip(p1 + ring[i] * r1);
		v1.color = color1;
		v1.worldNormal = ring[i];
		triStream.Append(v1);
	}
	triStream.RestartStrip();

	// 端のキャップ、凸6角形をジグザグストリップで三角形分割して塞ぐ
	int order[TUBE_SIDES] = { 0, 1, 5, 2, 4, 3 };

	[unroll]
	for (int c0 = 0; c0 < TUBE_SIDES; ++c0) {

		TubeGSOutput v;
		v.position = WorldToClip(p0 + ring[order[c0]] * r0);
		v.color = color0;
		v.worldNormal = -dir;
		triStream.Append(v);
	}
	triStream.RestartStrip();

	[unroll]
	for (int c1 = 0; c1 < TUBE_SIDES; ++c1) {

		TubeGSOutput v;
		v.position = WorldToClip(p1 + ring[order[c1]] * r1);
		v.color = color1;
		v.worldNormal = dir;
		triStream.Append(v);
	}
	triStream.RestartStrip();
}
