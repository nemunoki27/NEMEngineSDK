//============================================================================
//	include
//============================================================================
#include "../Common/defaultMesh.hlsli"
#include "../Common/meshLighting.hlsli"
#include "../Common/meshPBRMaterial.hlsli"
#include "../Common/meshPBR.hlsli"
#include "../Common/deferredGBuffer.hlsli"

//============================================================================
//	output
//============================================================================
GBufferOutput EncodeMeshPBRGBuffer(
	VSOutput input, ResolvedPBRMaterial material) {

	MeshSurface surface;
	surface.albedo = material.baseColor.rgb;
	surface.normal = material.N;
	surface.worldPos = input.worldPos;
	surface.metallic = material.metallic;
	surface.roughness = material.roughness;
	surface.occlusion = material.ao;
	surface.emissive = material.emissive;
	surface.motion = ComputeGBufferMotion(
		input.currentClipPosition, input.previousClipPosition);
	// MeshRendererのフラグをGBufferへ渡してライティングパスで分岐させる
	surface.flags = BuildMaterialFlags(gMeshInstances[input.instanceID].flags);
	return EncodeGBuffer(surface);
}

//============================================================================
//	main
//============================================================================
GBufferOutput main(VSOutput input) {

	return EncodeMeshPBRGBuffer(input, ResolvePBRMaterial(input));
}

GBufferOutput mainMasked(VSOutput input) {

	ResolvedPBRMaterial material = ResolvePBRMaterial(input);
	clip(material.baseColor.a - ResolveMeshPBRAlphaClip(input));
	return EncodeMeshPBRGBuffer(input, material);
}
