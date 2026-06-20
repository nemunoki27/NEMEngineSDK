//============================================================================
//	resources
//============================================================================
cbuffer SceneOverlaySpriteView : register(b0) {
	float2 gViewSize;
	float2 _pad0;
};

struct SpriteInstance {
	float2 center;
	float2 halfSize;
	float4 color;
	float rotationRadians;
	float3 _pad0;
};
StructuredBuffer<SpriteInstance> gSceneOverlaySpriteInstances : register(t1);

//============================================================================
//	output
//============================================================================
struct VSOutput {
	float4 position : SV_POSITION;
	float2 uv : TEXCOORD0;
	float4 color : COLOR0;
};

//============================================================================
//	main
//============================================================================
VSOutput main(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID) {

	static const float2 kQuadPos[6] = {
		float2(0.0f, 1.0f),
		float2(0.0f, 0.0f),
		float2(1.0f, 1.0f),
		float2(0.0f, 0.0f),
		float2(1.0f, 0.0f),
		float2(1.0f, 1.0f),
	};

	SpriteInstance instance = gSceneOverlaySpriteInstances[instanceID];
	float2 uv = kQuadPos[vertexID];
	float2 local = (uv - 0.5f) * (instance.halfSize * 2.0f);
	float s = sin(instance.rotationRadians);
	float c = cos(instance.rotationRadians);
	float2 rotated = float2(local.x * c - local.y * s, local.x * s + local.y * c);
	float2 pixel = instance.center + rotated;
	float2 ndc = float2(pixel.x / gViewSize.x * 2.0f - 1.0f,
		1.0f - pixel.y / gViewSize.y * 2.0f);

	VSOutput output;
	output.position = float4(ndc, 0.0f, 1.0f);
	output.uv = uv;
	output.color = instance.color;
	return output;
}
