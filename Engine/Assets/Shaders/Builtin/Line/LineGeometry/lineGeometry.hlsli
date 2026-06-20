//============================================================================
//	Common VS/GS/PS
//============================================================================
struct VSInput {

	float3 position : POSITION;
	float thickness : THICKNESS0;
	float4 color : COLOR0;
};

struct VSOutput {

	float3 position : POSITION0;
	float thickness : THICKNESS0;
	float4 color : COLOR0;
};

struct GSOutput {

	float4 position : SV_POSITION;
	float4 color : COLOR0;
	float3 worldPos : TEXCOORD0;

	noperspective float side : TEXCOORD1;
	noperspective float halfWidth : TEXCOORD2;
	noperspective float outerHalfWidth : TEXCOORD3;
};