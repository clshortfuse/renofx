#pragma once

namespace renodx {
namespace color {

float3 PQEncode(float3 normalized_nits) {
	static const float m1 = 0.1593017578125f;
	static const float m2 = 78.84375f;
	static const float c1 = 0.8359375f;
	static const float c2 = 18.8515625f;
	static const float c3 = 18.6875f;
	float3 powered = pow(max(normalized_nits, 0.0f), m1);
	return pow((c1 + c2 * powered) / (1.0f + c3 * powered), m2);
}

float3 PQDecode(float3 pq) {
	static const float m1 = 0.1593017578125f;
	static const float m2 = 78.84375f;
	static const float c1 = 0.8359375f;
	static const float c2 = 18.8515625f;
	static const float c3 = 18.6875f;
	float3 powered = pow(max(pq, 0.0f), 1.0f / m2);
	float3 numerator = max(powered - c1, 0.0f);
	float3 denominator = max(c2 - c3 * powered, 1e-6f);
	return pow(numerator / denominator, 1.0f / m1);
}

float3 PQEncodeSafe(float3 normalized_nits) {
	return sign(normalized_nits) * renodx::color::PQEncode(abs(normalized_nits));
}

float3 PQDecodeSafe(float3 pq) {
	return sign(pq) * renodx::color::PQDecode(abs(pq));
}

float3 DecodeHDR10(float3 pq, float reference_white_nits, bool preserve_sign) {
	float3 bt2020_nits = preserve_sign
			? renodx::color::PQDecodeSafe(pq) * 10000.0f
			: renodx::color::PQDecode(pq) * 10000.0f;
	return renodx::color::BT2020ToBT709(bt2020_nits) / max(reference_white_nits, 1.0f);
}

float3 EncodeHDR10(float3 bt709, float reference_white_nits, bool preserve_sign) {
	float3 bt2020_nits = renodx::color::BT709ToBT2020(bt709) * max(reference_white_nits, 1.0f);
	float3 normalized_nits = bt2020_nits / 10000.0f;
	return preserve_sign ? renodx::color::PQEncodeSafe(normalized_nits) : renodx::color::PQEncode(normalized_nits);
}

float3 DecodeScRGB(float3 scrgb, float reference_white_nits) {
	return scrgb * (80.0f / max(reference_white_nits, 1.0f));
}

float3 EncodeScRGB(float3 bt709, float reference_white_nits) {
	return bt709 * (max(reference_white_nits, 1.0f) / 80.0f);
}

}
}



