//============================================================================
//	Tube GS/PS 共有
//============================================================================
struct TubeGSOutput {

	float4 position : SV_POSITION;
	float4 color : COLOR0;
	// 円柱表面の法線、PSの陰影で丸く見せる
	float3 worldNormal : TEXCOORD0;
};
