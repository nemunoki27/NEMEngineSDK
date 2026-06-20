//============================================================================
//	resources
//============================================================================
cbuffer PickingBuffer : register(b0) {

	uint inputPixelX;
	uint inputPixelY;
	uint textureWidth;
	uint textureHeight;
	
	float4x4 inverseViewProjection;

	float3 cameraWorldPos;
	float rayMax;
};

RaytracingAccelerationStructure gSceneTLAS : register(t0);
RWStructuredBuffer<uint> gOutput : register(u0);

//============================================================================
//	functions
//============================================================================
float3 NDCFromPixel(uint2 pixel, uint2 size, float depth) {

	float2 uv = (float2(pixel) + 0.5f) / float2(size);
	float2 ndc = float2(uv.x * 2.0f - 1.0f, 1.0f - uv.y * 2.0f);
	return float3(ndc, depth);
}

//============================================================================
//	main
//============================================================================
[numthreads(1, 1, 1)]
void main(uint3 dispatchThreadID : SV_DispatchThreadID) {

	// 初期値は無効なインスタンスID
	gOutput[0] = 0xFFFFFFFFu;

	uint2 size = max(uint2(textureWidth, textureHeight), uint2(1, 1));
	uint2 pixel = min(uint2(inputPixelX, inputPixelY), size - 1u);

	float4 nearPos = mul(float4(NDCFromPixel(pixel, size, 0.0f), 1.0f), inverseViewProjection);
	float4 farPos = mul(float4(NDCFromPixel(pixel, size, 1.0f), 1.0f), inverseViewProjection);

	nearPos.xyz /= max(abs(nearPos.w), 1e-6f);
	farPos.xyz /= max(abs(farPos.w), 1e-6f);

	// ピック用のレイを生成してトレース
	RayDesc rayDesc;
	rayDesc.Origin = cameraWorldPos;
	rayDesc.Direction = normalize(farPos.xyz - nearPos.xyz);
	rayDesc.TMin = 0.0f;
	rayDesc.TMax = rayMax;
	RayQuery < 0 > rayQuery;
	rayQuery.TraceRayInline(gSceneTLAS, 0, 0xFF, rayDesc);

	while (rayQuery.Proceed()) {
	}

	// コミットされたヒットが三角形であれば、インスタンスIDを出力
	if (rayQuery.CommittedStatus() == COMMITTED_TRIANGLE_HIT) {
		
		gOutput[0] = rayQuery.CommittedInstanceID();
	}
}