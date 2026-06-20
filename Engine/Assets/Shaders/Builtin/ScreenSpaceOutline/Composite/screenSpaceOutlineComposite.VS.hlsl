//============================================================================
//	output
//============================================================================
struct CompositeVSOutput {

	float4 position : SV_Position;
};

//============================================================================
//	constants
//	FullscreenCopyと同じ全画面三角形
//============================================================================
static const uint kNumVertex = 3;
static const float4 kPositions[kNumVertex] = {
	{ -1.0f, 1.0f, 0.0f, 1.0f },
	{ 3.0f, 1.0f, 0.0f, 1.0f },
	{ -1.0f, -3.0f, 0.0f, 1.0f }
};

//============================================================================
//	main
//============================================================================
CompositeVSOutput main(uint vertexID : SV_VertexID) {

	CompositeVSOutput output;
	output.position = kPositions[vertexID];
	return output;
}
