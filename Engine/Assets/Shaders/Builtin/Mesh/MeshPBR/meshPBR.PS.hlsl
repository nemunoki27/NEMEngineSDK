//============================================================================
//	include
//============================================================================
#include "../Common/defaultMesh.hlsli"
#include "../Common/meshLighting.hlsli"
#include "../Common/meshPBRMaterial.hlsli"
#include "../Common/meshPBR.hlsli"
#include "../Common/deferredGBuffer.hlsli"

//============================================================================
//	main
//============================================================================
GBufferOutput main(VSOutput input) {

	ResolvedPBRMaterial m = ResolvePBRMaterial(input);

	MeshSurface surface;
	surface.albedo = m.baseColor.rgb;
	surface.normal = m.N;
	surface.worldPos = input.worldPos;
	surface.metallic = m.metallic;
	surface.roughness = m.roughness;
	surface.occlusion = m.ao;
	surface.emissive = m.emissive;
	return EncodeGBuffer(surface);
}