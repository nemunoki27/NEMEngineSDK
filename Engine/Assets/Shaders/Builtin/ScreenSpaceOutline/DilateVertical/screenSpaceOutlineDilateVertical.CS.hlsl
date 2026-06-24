//============================================================================
//	include
//============================================================================
#include "../Common/screenSpaceOutlineCommon.hlsli"

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
//	main
//============================================================================
[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadID : SV_DispatchThreadID) {

	uint2 pixel = dispatchThreadID.xy;
	if (gWidth <= pixel.x || gHeight <= pixel.y) {
		return;
	}

	uint bestStyle = 0u;
	int bestPriority = -2147483648;
	int bestDistance = 2147483647;

	// 半径は共通上限でclampする、巨大値でもGPU Hangしない
	int radius = (int)min(gMaxRadiusPixels, kMaxScreenSpaceOutlineRadiusPixels);
	for (int oy = -radius; oy <= radius; ++oy) {

		int sy = (int)pixel.y + oy;
		if (sy < 0 || sy >= (int)gHeight) {
			continue;
		}

		uint styleID = gInputMask.Load(int3((int)pixel.x, sy, 0));
		if (styleID == 0u || styleID > gStyleCount) {
			continue;
		}

		ScreenSpaceOutlineStyleGPU style = gOutlineStyles[styleID - 1u];
		int distance = abs(oy);
		if ((float)distance > style.widthPixels) {
			continue;
		}

		bool better = false;
		if (style.priority > bestPriority) {
			better = true;
		} else if (style.priority == bestPriority) {
			if (distance < bestDistance) {
				better = true;
			} else if (distance == bestDistance && (bestStyle == 0u || styleID < bestStyle)) {
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
