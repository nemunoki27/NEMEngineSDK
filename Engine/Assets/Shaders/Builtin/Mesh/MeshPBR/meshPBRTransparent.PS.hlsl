//============================================================================
//	include
//============================================================================
#include "../Common/defaultMesh.hlsli"
#include "../Common/meshLighting.hlsli"
#include "../Common/meshPBRMaterial.hlsli"
#include "../Common/meshPBR.hlsli"

//============================================================================
//	output
//============================================================================
struct TransparentPSOutput {

	float4 color : SV_TARGET0;
};

//============================================================================
//	mainTransparent
//	半透明は前方描画のままPBRライティングして合成色を出す
//============================================================================
TransparentPSOutput mainTransparent(VSOutput input) {

	ResolvedPBRMaterial m = ResolvePBRMaterial(input);
	float3 finalColor = EvaluateForwardPBRLighting(input, m);

	TransparentPSOutput output;
	output.color = float4(finalColor, m.baseColor.a);
	return output;
}
