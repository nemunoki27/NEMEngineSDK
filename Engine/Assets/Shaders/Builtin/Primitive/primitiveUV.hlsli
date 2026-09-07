#ifndef NEM_PRIMITIVE_UV_HLSLI
#define NEM_PRIMITIVE_UV_HLSLI

// Ring以外は頂点UVを使い、Ringはローカル位置から角度と半径を復元する
float2 ResolvePrimitiveLocalUV(float4 coordinates, float4 ringParams) {

	const float width = ringParams.x - ringParams.y;
	const float span = radians(ringParams.w);
	if (width <= 0.00001f || abs(span) <= 0.00001f) {
		return coordinates.zw;
	}
	const float radius = length(coordinates.xy);
	if (radius <= 0.00001f) {
		return float2(coordinates.z, 1.0f);
	}
	const float start = radians(ringParams.z);
	const float period = 6.28318530718f;
	float angle = atan2(coordinates.y, coordinates.x);
	// 頂点UVを周回の基準にして全周の継ぎ目と逆向きの部分リングを連続にする
	angle += round((start + coordinates.z * span - angle) / period) * period;
	return float2((angle - start) / span,
		saturate((ringParams.x - radius) / width));
}

// ピクセルで求めた差分へUV行列のスケールと回転を適用する
float2 ResolvePrimitivePixelUV(float2 texcoord, float4 coordinates,
	float4 ringParams, float4 uvBasis) {

	const float2 delta = ResolvePrimitiveLocalUV(coordinates, ringParams) - coordinates.zw;
	return texcoord + float2(dot(delta, uvBasis.xz), dot(delta, uvBasis.yw));
}

#endif // NEM_PRIMITIVE_UV_HLSLI
