//============================================================================
//	include
//============================================================================
#include "lineGeometry.hlsli"

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
//	local structures
//============================================================================
struct LinePoint {

	float3 worldPos;
	float3 viewPos;
	float thickness;
	float4 color;
};

//============================================================================
//	main
//============================================================================
[maxvertexcount(4)]
void main(line VSOutput input[2], inout TriangleStream<GSOutput> triStream) {

	LinePoint p0;
	p0.worldPos = input[0].position;
	p0.viewPos = mul(float4(input[0].position, 1.0f), viewMatrix).xyz;
	p0.thickness = max(input[0].thickness, 0.01f);
	p0.color = input[0].color;

	LinePoint p1;
	p1.worldPos = input[1].position;
	p1.viewPos = mul(float4(input[1].position, 1.0f), viewMatrix).xyz;
	p1.thickness = max(input[1].thickness, 0.01f);
	p1.color = input[1].color;
	
	float4 clip0 = mul(float4(p0.viewPos, 1.0f), projectionMatrix);
	float4 clip1 = mul(float4(p1.viewPos, 1.0f), projectionMatrix);

	float w0 = max(abs(clip0.w), 1e-6f);
	float w1 = max(abs(clip1.w), 1e-6f);

	float2 ndc0 = clip0.xy / w0;
	float2 ndc1 = clip1.xy / w1;

	float2 pixelScale = max(viewportSize * 0.5f, float2(1.0f, 1.0f));
	float2 screen0 = ndc0 * pixelScale;
	float2 screen1 = ndc1 * pixelScale;

	float2 direction = screen1 - screen0;
	float lenSq = dot(direction, direction);
	if (lenSq < 1e-8f) {
		return;
	}
	direction = normalize(direction);

	float2 normal = float2(-direction.y, direction.x);

	float safeFeather = max(feather, 0.5f);

	float halfWidth0 = p0.thickness;
	float halfWidth1 = p1.thickness;

	// AA用の外側まで少し広げる
	float outerHalfWidth0 = halfWidth0 + safeFeather;
	float outerHalfWidth1 = halfWidth1 + safeFeather;

	float2 offsetPx0 = normal * outerHalfWidth0;
	float2 offsetPx1 = normal * outerHalfWidth1;

	float2 ndcOffset0 = float2(offsetPx0.x / pixelScale.x, offsetPx0.y / pixelScale.y);
	float2 ndcOffset1 = float2(offsetPx1.x / pixelScale.x, offsetPx1.y / pixelScale.y);

	float2 clipOffset0 = ndcOffset0 * clip0.w;
	float2 clipOffset1 = ndcOffset1 * clip1.w;

	GSOutput v;

	v.color = p0.color;
	v.worldPos = p0.worldPos;
	v.side = +1.0f;
	v.halfWidth = halfWidth0;
	v.outerHalfWidth = outerHalfWidth0;
	v.position = float4(clip0.x + clipOffset0.x, clip0.y + clipOffset0.y, clip0.z, clip0.w);
	triStream.Append(v);

	v.color = p0.color;
	v.worldPos = p0.worldPos;
	v.side = -1.0f;
	v.halfWidth = halfWidth0;
	v.outerHalfWidth = outerHalfWidth0;
	v.position = float4(clip0.x - clipOffset0.x, clip0.y - clipOffset0.y, clip0.z, clip0.w);
	triStream.Append(v);

	v.color = p1.color;
	v.worldPos = p1.worldPos;
	v.side = +1.0f;
	v.halfWidth = halfWidth1;
	v.outerHalfWidth = outerHalfWidth1;
	v.position = float4(clip1.x + clipOffset1.x, clip1.y + clipOffset1.y, clip1.z, clip1.w);
	triStream.Append(v);

	v.color = p1.color;
	v.worldPos = p1.worldPos;
	v.side = -1.0f;
	v.halfWidth = halfWidth1;
	v.outerHalfWidth = outerHalfWidth1;
	v.position = float4(clip1.x - clipOffset1.x, clip1.y - clipOffset1.y, clip1.z, clip1.w);
	triStream.Append(v);

	triStream.RestartStrip();
}