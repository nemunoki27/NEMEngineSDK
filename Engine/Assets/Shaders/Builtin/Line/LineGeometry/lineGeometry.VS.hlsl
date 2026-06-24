//============================================================================
//	include
//============================================================================
#include "lineGeometry.hlsli"

//============================================================================
//	main
//============================================================================
VSOutput main(VSInput input) {

	VSOutput output;

	output.position = input.position;
	output.thickness = input.thickness;
	output.color = input.color;

	return output;
}