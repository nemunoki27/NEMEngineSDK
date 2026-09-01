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
	uint alphaSource;
	uint padding;
};

static const uint SCREEN_SPACE_OUTLINE_ALPHA_TEXTURE_COLOR = 0u;
static const uint SCREEN_SPACE_OUTLINE_ALPHA_OUTPUT_COLOR = 1u;

float ResolveScreenSpaceOutlineAlpha(
	float4 textureColor,
	float4 outputColor,
	uint alphaSource) {

	return alphaSource == SCREEN_SPACE_OUTLINE_ALPHA_TEXTURE_COLOR ?
		textureColor.a : outputColor.a;
}

struct ScreenSpaceOutlineDilateConstants {

	uint width;
	uint height;
	uint styleCount;
	uint maxRadiusPixels;
};

static const uint kMaxScreenSpaceOutlineRadiusPixels = 16u;

#endif // NEM_SCREEN_SPACE_OUTLINE_COMMON_HLSLI
