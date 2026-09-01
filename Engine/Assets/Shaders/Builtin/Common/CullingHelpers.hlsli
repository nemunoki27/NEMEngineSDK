#ifndef NEM_CULLING_HELPERS_HLSLI
#define NEM_CULLING_HELPERS_HLSLI

//============================================================================
//	Culling Helpers
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

// 球の画面矩形とカメラに最も近い深度をHi-Z判定用に求める
bool CalcSphereOcclusionProjection(
	float4x4 cullingViewProj,
	float4x4 cullingView,
	float cullingNearClip,
	float2 cullingProjectionScale,
	float2 cullingViewSize,
	float3 cullingCameraForward,
	float3 center,
	float radius,
	out float2 uvMin,
	out float2 uvMax,
	out float nearestDepth) {

	const float3 viewCenter =
		mul(float4(center, 1.0f), cullingView).xyz;
	if (viewCenter.z - radius <=
		max(cullingNearClip, 0.00001f)) {
		return false;
	}

	const float4 centerClip =
		mul(float4(center, 1.0f), cullingViewProj);
	if (centerClip.w <= 0.00001f) {
		return false;
	}

	const float2 pixelRadius = CalcProjectedPixelRadiusXY(
		cullingViewProj, cullingView, cullingNearClip,
		cullingProjectionScale, cullingViewSize, 0.0f,
		center, radius);
	const float2 centerUV =
		centerClip.xy / centerClip.w *
		float2(0.5f, -0.5f) + 0.5f;
	const float2 uvRadius =
		pixelRadius / max(cullingViewSize, 1.0f);
	const float2 unclampedMin = centerUV - uvRadius;
	const float2 unclampedMax = centerUV + uvRadius;
	if (unclampedMax.x <= 0.0f ||
		unclampedMax.y <= 0.0f ||
		unclampedMin.x >= 1.0f ||
		unclampedMin.y >= 1.0f) {
		return false;
	}
	uvMin = saturate(unclampedMin);
	uvMax = saturate(unclampedMax);

	// 深度はカメラ距離ではなくView-Zで決まるため前方軸へ球半径分寄せる
	const float3 cameraForward =
		normalize(cullingCameraForward);
	const float3 nearestPoint =
		center - cameraForward * radius;
	const float4 nearestClip =
		mul(float4(nearestPoint, 1.0f),
			cullingViewProj);
	if (nearestClip.w <= 0.00001f) {
		return false;
	}
	nearestDepth = nearestClip.z / nearestClip.w;
	return nearestDepth > 0.0f &&
		nearestDepth < 1.0f;
}

#ifdef NEM_OCCLUSION_DEPTH_PYRAMID
// 球の投影矩形を覆うHi-Z Mipから遮蔽を判定する
bool IsSphereOccludedHiZ(
	float4x4 cullingViewProj,
	float4x4 cullingView,
	float cullingNearClip,
	float2 cullingProjectionScale,
	float2 cullingViewSize,
	float3 cullingCameraForward,
	float3 center,
	float radius) {

	float2 uvMin;
	float2 uvMax;
	float nearestDepth;
	if (!CalcSphereOcclusionProjection(
		cullingViewProj, cullingView,
		cullingNearClip, cullingProjectionScale,
		cullingViewSize, cullingCameraForward,
		center, radius, uvMin, uvMax,
		nearestDepth)) {
		return false;
	}

	uint width;
	uint height;
	uint mipCount;
	NEM_OCCLUSION_DEPTH_PYRAMID.GetDimensions(
		0, width, height, mipCount);
	const float2 rectangleSize =
		(uvMax - uvMin) * float2(width, height);
	const float maxExtent =
		max(rectangleSize.x, rectangleSize.y);
	const uint mipIndex = min(
		(uint)max(0.0f,
			floor(log2(max(maxExtent, 1.0f)))),
		mipCount - 1u);

	uint mipWidth;
	uint mipHeight;
	uint ignoredMipCount;
	NEM_OCCLUSION_DEPTH_PYRAMID.GetDimensions(
		mipIndex, mipWidth, mipHeight,
		ignoredMipCount);
	const uint2 maxPixel =
		uint2(mipWidth - 1u, mipHeight - 1u);
	const uint2 pixelMin = min(
		(uint2)(uvMin * float2(mipWidth, mipHeight)),
		maxPixel);
	const uint2 pixelMax = min(
		(uint2)(uvMax * float2(mipWidth, mipHeight)),
		maxPixel);

	float maxDepth =
		NEM_OCCLUSION_DEPTH_PYRAMID.Load(
			int3(pixelMin, mipIndex));
	maxDepth = max(maxDepth,
		NEM_OCCLUSION_DEPTH_PYRAMID.Load(
			int3(uint2(pixelMax.x, pixelMin.y),
				mipIndex)));
	maxDepth = max(maxDepth,
		NEM_OCCLUSION_DEPTH_PYRAMID.Load(
			int3(uint2(pixelMin.x, pixelMax.y),
				mipIndex)));
	maxDepth = max(maxDepth,
		NEM_OCCLUSION_DEPTH_PYRAMID.Load(
			int3(pixelMax, mipIndex)));
	// 未生成Mipや無効値を遮蔽面として扱わない
	return maxDepth > 0.000001f &&
		nearestDepth > maxDepth + 0.0005f;
}
#endif

#endif // NEM_CULLING_HELPERS_HLSLI
