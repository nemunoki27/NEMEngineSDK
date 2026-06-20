//============================================================================
//	include
//============================================================================
#include "screenSpaceOutlineCommon.hlsli"

//============================================================================
//	resources
//============================================================================
cbuffer DilateConstants : register(b0) {

	uint gWidth;
	uint gHeight;
	uint gStyleCount;
	uint gMaxRadiusPixels;
};

Texture2D<uint> gInputMask : register(t0);
StructuredBuffer<ScreenSpaceOutlineStyleGPU> gOutlineStyles : register(t1);
RWTexture2D<uint> gOutputMask : register(u0);

//============================================================================
//	Dilation Logic
//============================================================================
void RunDilation(uint2 pixel, int2 direction) {

	if (gWidth <= pixel.x || gHeight <= pixel.y) {
		return;
	}

	uint bestStyle = 0u;
	int bestPriority = -2147483648;
	int bestDistance = 2147483647;

	int radius = (int)min(gMaxRadiusPixels, kMaxScreenSpaceOutlineRadiusPixels);
	for (int offset = -radius; offset <= radius; ++offset) {

		int2 sampleCoord = (int2)pixel + direction * offset;
		if (sampleCoord.x < 0 || sampleCoord.x >= (int)gWidth ||
			sampleCoord.y < 0 || sampleCoord.y >= (int)gHeight) {
			continue;
		}

		uint styleID = gInputMask.Load(int3(sampleCoord, 0));
		if (styleID == 0u || styleID > gStyleCount) {
			continue;
		}

		ScreenSpaceOutlineStyleGPU style = gOutlineStyles[styleID - 1u];
		int distance = abs(offset);
		if ((float)distance > style.widthPixels) {
			continue;
		}

		bool better = false;
		if (style.priority > bestPriority) {
			better = true;
		}
		else if (style.priority == bestPriority) {
			if (distance < bestDistance) {
				better = true;
			}
			else if (distance == bestDistance && (bestStyle == 0u || styleID < bestStyle)) {
				better = true;
			}
		}
		if (better) {
			bestStyle = styleID;
			bestPriority = style.priority;
			bestDistance = distance;
		}
	}

	gOutputMask[pixel] = bestStyle;
}
