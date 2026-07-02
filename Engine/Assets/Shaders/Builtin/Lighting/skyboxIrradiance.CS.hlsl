//============================================================================
//	定数
//============================================================================
static const float PI = 3.14159265f;

// 半球サンプリングの分割数
static const uint kPhiSampleCount = 64;
static const uint kThetaSampleCount = 16;

//============================================================================
//	resources
//============================================================================
cbuffer IrradianceConstants : register(b0) {

	// 畳み込み元のskybox cubemap
	uint sourceCubemapIndex;
	// 出力cubemapの1面のサイズ
	uint faceSize;
	uint2 _pad0;
};

RWTexture2DArray<float4> gIrradianceMap : register(u0);
SamplerState gSampler : register(s0);

//============================================================================
//	functions
//============================================================================

// cubemapの面indexとuvからサンプリング方向を作る
float3 BuildCubemapDirection(uint faceIndex, float2 uv) {

	// uvを-1から1へ、yはテクスチャ座標系なので反転する
	float2 st = float2(uv.x * 2.0f - 1.0f, 1.0f - uv.y * 2.0f);

	// D3Dのcubemap面順、+X,-X,+Y,-Y,+Z,-Z
	if (faceIndex == 0) { return normalize(float3(1.0f, st.y, -st.x)); }
	if (faceIndex == 1) { return normalize(float3(-1.0f, st.y, st.x)); }
	if (faceIndex == 2) { return normalize(float3(st.x, 1.0f, -st.y)); }
	if (faceIndex == 3) { return normalize(float3(st.x, -1.0f, st.y)); }
	if (faceIndex == 4) { return normalize(float3(st.x, st.y, 1.0f)); }
	return normalize(float3(-st.x, st.y, -1.0f));
}

//============================================================================
//	main
//============================================================================
[numthreads(8, 8, 1)]
void main(uint3 dispatchID : SV_DispatchThreadID) {

	if (dispatchID.x >= faceSize || dispatchID.y >= faceSize) {
		return;
	}

	// 出力テクセルの法線方向
	float2 uv = (float2(dispatchID.xy) + 0.5f) / float(faceSize);
	float3 N = BuildCubemapDirection(dispatchID.z, uv);

	// 法線を軸にした接空間を作る
	float3 up = abs(N.y) < 0.999f ? float3(0.0f, 1.0f, 0.0f) : float3(1.0f, 0.0f, 0.0f);
	float3 tangent = normalize(cross(up, N));
	float3 bitangent = cross(N, tangent);

	TextureCube<float4> sourceCubemap = ResourceDescriptorHeap[NonUniformResourceIndex(sourceCubemapIndex)];

	// 半球をphi/thetaで等間隔サンプリングしてcos重み付きで畳み込む
	float3 irradiance = 0.0f.xxx;
	uint sampleCount = 0;
	for (uint phiIndex = 0; phiIndex < kPhiSampleCount; ++phiIndex) {
		for (uint thetaIndex = 0; thetaIndex < kThetaSampleCount; ++thetaIndex) {

			float phi = (float(phiIndex) + 0.5f) / float(kPhiSampleCount) * 2.0f * PI;
			float theta = (float(thetaIndex) + 0.5f) / float(kThetaSampleCount) * 0.5f * PI;

			float3 tangentDir = float3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));
			float3 sampleDir = tangentDir.x * tangent + tangentDir.y * bitangent + tangentDir.z * N;

			// cos(theta)で放射照度の重み、sin(theta)で立体角の補正を掛ける
			irradiance += sourceCubemap.SampleLevel(gSampler, sampleDir, 0.0f).rgb * cos(theta) * sin(theta);
			++sampleCount;
		}
	}
	irradiance = PI * irradiance / float(sampleCount);

	gIrradianceMap[dispatchID] = float4(irradiance, 1.0f);
}