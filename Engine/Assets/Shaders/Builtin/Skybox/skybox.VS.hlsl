//============================================================================
//	output
//============================================================================
struct VSOutput {

	float4 position : SV_POSITION;
	float2 ndc : TEXCOORD0;
};

//============================================================================
//	main
//============================================================================
VSOutput main(uint vertexID : SV_VertexID) {

	VSOutput output;
	// SV_VertexIDから画面を覆う三角形を作る
	float2 uv = float2((vertexID << 1) & 2, vertexID & 2);
	output.ndc = uv * 2.0f - 1.0f;
	// 深度は最遠面に固定して背景として描く
	output.position = float4(output.ndc, 1.0f, 1.0f);
	return output;
}
