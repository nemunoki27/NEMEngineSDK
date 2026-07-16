//============================================================================
//	Common VS/PS
//============================================================================
struct VSOutput {

	float4 position : SV_Position;
	float2 texcoord : TEXCOORD0;
	float2 materialTexcoord : TEXCOORD1;
	uint instanceID : INSTANCEID;
};
