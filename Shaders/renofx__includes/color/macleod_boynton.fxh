#pragma once

namespace renodx {
namespace color {

float3 WeightedLMSToMB(float3 weighted_lms) {
	float y = max(weighted_lms.x + weighted_lms.y, 0.0f);
	float inverse_y = y > 0.0f ? rcp(y) : 0.0f;
	return float3(weighted_lms.x * inverse_y, weighted_lms.z * inverse_y, y);
}

float3 MBToWeightedLMS(float2 chromaticity, float y) {
	return float3(chromaticity.x, 1.0f - chromaticity.x, chromaticity.y) * y;
}

float2 CIE1702WhiteChromaticity() {
	float3 d65_lms = renodx::color::BT709ToLMS(float3(1.0f, 1.0f, 1.0f));
	return renodx::color::WeightedLMSToMB(d65_lms * renodx::color::LMS_WEIGHTS).xy;
}

}
}



