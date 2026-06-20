#ifndef NEM_SCREEN_SPACE_OUTLINE_COMMON_HLSLI
#define NEM_SCREEN_SPACE_OUTLINE_COMMON_HLSLI

//============================================================================
//	Screen-space Outline 共通定義
//============================================================================
struct ScreenSpaceOutlineStyleGPU {

	float4 color;
	float widthPixels;
	int priority;
	uint visibilityMode;
	uint regionMode;
};

struct ScreenSpaceOutlineMaskConstants {

	uint styleID;
	int restrictSubMeshIndex;
	uint2 padding;
};

struct ScreenSpaceOutlineDilateConstants {

	uint width;
	uint height;
	uint styleCount;
	uint maxRadiusPixels;
};

static const uint kMaxScreenSpaceOutlineRadiusPixels = 16u;

#endif // NEM_SCREEN_SPACE_OUTLINE_COMMON_HLSLI