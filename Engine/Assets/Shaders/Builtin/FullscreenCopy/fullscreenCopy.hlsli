//============================================================================
//	Common VS/PS
//============================================================================
struct VSOutput {

	float4 position : SV_POSITION;
	float2 texcoord : TEXCOORD0;
};

//============================================================================
//	画面全体を覆う3頂点の三角形を出力する共通VS
//============================================================================
static const uint kFullscreenTriangleVertexCount = 3;
static const float4 kFullscreenTrianglePositions[kFullscreenTriangleVertexCount] = {
	{ -1.0f, 1.0f, 0.0f, 1.0f },
	{ 3.0f, 1.0f, 0.0f, 1.0f },
	{ -1.0f, -3.0f, 0.0f, 1.0f }
};
static const float2 kFullscreenTriangleTexcoords[kFullscreenTriangleVertexCount] = {
	{ 0.0f, 0.0f },
	{ 2.0f, 0.0f },
	{ 0.0f, 2.0f }
};

VSOutput FullscreenTriangleVS(uint vertexID) {

	VSOutput output;

	output.position = kFullscreenTrianglePositions[vertexID];
	output.texcoord = kFullscreenTriangleTexcoords[vertexID];

	return output;
}