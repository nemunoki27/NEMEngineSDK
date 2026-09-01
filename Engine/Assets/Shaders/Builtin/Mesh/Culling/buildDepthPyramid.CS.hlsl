//============================================================================
//	resources
//============================================================================
cbuffer DepthPyramidConstants : register(b0) {

	uint2 sourceSize;
	uint2 destinationSize;
	uint copySource;
	uint3 _pad0;
};
Texture2D<float> gSourceDepth : register(t0);
RWTexture2D<float> gOutputDepth : register(u0);

//============================================================================
//	main
//============================================================================
[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadID : SV_DispatchThreadID) {

	const uint2 destination = dispatchThreadID.xy;
	if (any(destination >= destinationSize)) {
		return;
	}

	if (copySource != 0u) {
		gOutputDepth[destination] =
			gSourceDepth.Load(int3(destination, 0));
		return;
	}

	const uint2 sourceBase = destination * 2u;
	float maxDepth = 0.0f;
	const uint sampleCountX =
		(sourceSize.x > destinationSize.x * 2u &&
			destination.x + 1u == destinationSize.x) ?
		3u : 2u;
	const uint sampleCountY =
		(sourceSize.y > destinationSize.y * 2u &&
			destination.y + 1u == destinationSize.y) ?
		3u : 2u;
	for (uint y = 0; y < sampleCountY; ++y) {
		for (uint x = 0; x < sampleCountX; ++x) {

			const uint2 source = sourceBase + uint2(x, y);
			if (all(source < sourceSize)) {
				maxDepth = max(maxDepth,
					gSourceDepth.Load(int3(source, 0)));
			}
		}
	}
	gOutputDepth[destination] = maxDepth;
}
