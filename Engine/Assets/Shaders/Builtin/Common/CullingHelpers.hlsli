#ifndef NEM_CULLING_HELPERS_HLSLI
#define NEM_CULLING_HELPERS_HLSLI

//============================================================================
//	Culling Helpers
//	ビュー定数に基づいた各種カリング判定関数群
//============================================================================

// ビュー錐台の平面を取得
float4 GetFrustumPlane(float4x4 cullingViewProj, uint index) {

	float4 col0 = float4(cullingViewProj[0][0], cullingViewProj[1][0], cullingViewProj[2][0], cullingViewProj[3][0]);
	float4 col1 = float4(cullingViewProj[0][1], cullingViewProj[1][1], cullingViewProj[2][1], cullingViewProj[3][1]);
	float4 col2 = float4(cullingViewProj[0][2], cullingViewProj[1][2], cullingViewProj[2][2], cullingViewProj[3][2]);
	float4 col3 = float4(cullingViewProj[0][3], cullingViewProj[1][3], cullingViewProj[2][3], cullingViewProj[3][3]);

	if (index == 0) { return col3 + col0; }
	if (index == 1) { return col3 - col0; }
	if (index == 2) { return col3 + col1; }
	if (index == 3) { return col3 - col1; }
	if (index == 4) { return col2; }
	return col3 - col2;
}

// 平面式の正規化
float4 NormalizePlane(float4 plane) {

	float len = length(plane.xyz);
	if (len <= 0.00001f) {
		return plane;
	}
	return plane / len;
}

// 行列の最大スケール値を取得
float GetMatrixMaxScale(float4x4 inputMat) {

	float sx = length(inputMat[0].xyz);
	float sy = length(inputMat[1].xyz);
	float sz = length(inputMat[2].xyz);
	return max(sx, max(sy, sz));
}

// 球が錐台内にあるか判定
bool IsSphereInFrustum(float4x4 cullingViewProj, float3 center, float radius) {

	[unroll]
	for (uint i = 0; i < 6; ++i) {

		float4 plane = NormalizePlane(GetFrustumPlane(cullingViewProj, i));
		if (dot(plane.xyz, center) + plane.w < -radius) {
			return false;
		}
	}
	return true;
}

// 投影されたピクセル半径を計算
float2 CalcProjectedPixelRadiusXY(float4x4 cullingViewProj, float4x4 cullingView, float cullingNearClip, float2 cullingProjectionScale, float2 cullingViewSize, float contributionPixelThreshold, float3 center, float radius) {

	float4 clip = mul(float4(center, 1.0f), cullingViewProj);
	if (clip.w <= 0.00001f) {
		return float2(contributionPixelThreshold, contributionPixelThreshold);
	}

	float3 viewCenter = mul(float4(center, 1.0f), cullingView).xyz;
	float nearZ = viewCenter.z - radius;
	if (nearZ <= max(cullingNearClip, 0.00001f)) {
		return float2(1000000.0f, 1000000.0f);
	}

	float2 projectedRadius = abs(radius * cullingProjectionScale / nearZ);
	return projectedRadius * cullingViewSize * 0.5f;
}

#endif // NEM_CULLING_HELPERS_HLSLI
