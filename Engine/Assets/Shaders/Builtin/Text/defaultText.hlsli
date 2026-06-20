//============================================================================
//	Common VS/PS
//============================================================================
struct VSOutput {
	
	float4 position : SV_Position;
	float2 texcoord : TEXCOORD0;
	uint instanceID : INSTANCEID;
};