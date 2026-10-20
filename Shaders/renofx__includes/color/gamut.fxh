#pragma once

namespace renodx {
namespace color {

float3 SanitizeGamutInput(float3 color, float3x3 gamut_xyz) {
	const float3 luminance_weights = gamut_xyz[1];
	float y = dot(color, luminance_weights);
	[branch]
	if (y < 0.0f) {
		float3 positive = max(color, 0.0f);
		float positive_y = dot(positive, luminance_weights);
		float scale = positive_y > 0.0f ? positive_y / (positive_y - y) : 0.0f;
		color = mad(color - positive, scale, positive);
	}
	return color;
}

float3 SanitizeGamutInputBT709(float3 color) { return renodx::color::SanitizeGamutInput(color, renodx::color::BT709_TO_XYZ); }
float3 SanitizeGamutInputBT2020(float3 color) { return renodx::color::SanitizeGamutInput(color, renodx::color::BT2020_TO_XYZ); }

float CIE1702HalfspaceRayT(float2 direction, float2 normal, float numerator) {
	float denominator = dot(normal, direction);
	return denominator > 1e-8f ? numerator / denominator : 1e20f;
}

float RayExitTCIE1702(float2 direction) {
	if (dot(direction, direction) <= 1e-14f) return 1e20f;
	float result = 1e20f;
	result = min(result, renodx::color::CIE1702HalfspaceRayT(direction, float2(-0.043889f, -0.006807f), 0.0065035249f));
	result = min(result, renodx::color::CIE1702HalfspaceRayT(direction, float2(-0.007821f, -0.008564f), 0.00104900495f));
	result = min(result, renodx::color::CIE1702HalfspaceRayT(direction, float2(-0.000604f, -0.007942f), 0.000207697044f));
	result = min(result, renodx::color::CIE1702HalfspaceRayT(direction, float2(0.0f, -0.080835f), 0.00165556648f));
	result = min(result, renodx::color::CIE1702HalfspaceRayT(direction, float2(0.953597f, 0.307020f), 0.252472349f));
	result = min(result, renodx::color::CIE1702HalfspaceRayT(direction, float2(-0.060969f, 0.019752f), 0.0241967351f));
	result = min(result, renodx::color::CIE1702HalfspaceRayT(direction, float2(-0.106895f, 0.004035f), 0.0199621232f));
	return max(result, 0.0f);
}

float Cross2(float2 a, float2 b) { return a.x * b.y - a.y * b.x; }

bool RaySegmentHit(float2 origin, float2 direction, float2 a, float2 b, out float hit_t) {
	hit_t = 0.0f;
	float2 edge = b - a;
	float denominator = Cross2(direction, edge);
	if (abs(denominator) <= 1e-20f) return false;
	float2 offset = a - origin;
	float t = Cross2(offset, edge) / denominator;
	float u = Cross2(offset, direction) / denominator;
	if (t < 0.0f || u < 0.0f || u > 1.0f) return false;
	hit_t = t;
	return true;
}

float RayExitTRGBTriangle(float2 origin, float2 direction, float2 red, float2 green, float2 blue, out bool found) {
	found = false;
	float result = 1e20f;
	float hit_t = 0.0f;
	if (renodx::color::RaySegmentHit(origin, direction, red, green, hit_t)) { result = min(result, hit_t); found = true; }
	if (renodx::color::RaySegmentHit(origin, direction, green, blue, hit_t)) { result = min(result, hit_t); found = true; }
	if (renodx::color::RaySegmentHit(origin, direction, blue, red, hit_t)) { result = min(result, hit_t); found = true; }
	return found ? max(result, 0.0f) : 0.0f;
}

float GamutNeutwoScale(float peak, float clip) {
	float safe_peak = max(peak, 0.0f);
	float safe_clip = max(clip, safe_peak);
	float clip_squared = safe_clip * safe_clip;
	float peak_squared = safe_peak * safe_peak;
	float denominator_squared = clip_squared - peak_squared + clip_squared * peak_squared;
	return saturate(safe_clip * safe_peak * rsqrt(max(denominator_squared, 1e-20f)));
}

float3 ClampWeightedLMSToCIE1702(float3 weighted_lms) {
	float3 clamped = max(weighted_lms, 0.0f);
	float3 mb = renodx::color::WeightedLMSToMB(clamped);
	if (mb.z <= 1e-20f) return float3(clamped.x, clamped.y, 0.0f);
	float2 white = renodx::color::CIE1702WhiteChromaticity();
	float2 direction = mb.xy - white;
	if (dot(direction, direction) <= 1e-14f) return clamped;
	float scale = min(1.0f, renodx::color::RayExitTCIE1702(direction));
	return renodx::color::MBToWeightedLMS(white + direction * scale, mb.z);
}

float2 TargetPrimaryBT709MB(uint primary_index, float3 adaptive_state_lms) {
	float3 primary = primary_index == 0 ? float3(1.0f, 0.0f, 0.0f)
			: (primary_index == 1 ? float3(0.0f, 1.0f, 0.0f) : float3(0.0f, 0.0f, 1.0f));
	float3 primary_lms = renodx::color::BT709ToLMS(primary);
	float3 adaptive_weighted = renodx::color::DivideSafe(primary_lms * renodx::color::LMS_WEIGHTS, adaptive_state_lms, 0.0f);
	return renodx::color::WeightedLMSToMB(adaptive_weighted).xy;
}

float2 TargetPrimaryBT2020MB(uint primary_index, float3 adaptive_state_lms) {
	float3 primary = primary_index == 0 ? float3(1.0f, 0.0f, 0.0f)
			: (primary_index == 1 ? float3(0.0f, 1.0f, 0.0f) : float3(0.0f, 0.0f, 1.0f));
	float3 primary_bt709 = renodx::color::BT2020ToBT709(primary);
	float3 primary_lms = renodx::color::BT709ToLMS(primary_bt709);
	float3 adaptive_weighted = renodx::color::DivideSafe(primary_lms * renodx::color::LMS_WEIGHTS, adaptive_state_lms, 0.0f);
	return renodx::color::WeightedLMSToMB(adaptive_weighted).xy;
}

float ComputeGamutCompressionScaleWeightedLMS(float3 weighted_lms, float2 bound_red, float2 bound_green, float2 bound_blue, float strength) {
	float3 clamped = renodx::color::ClampWeightedLMSToCIE1702(max(weighted_lms, 0.0f));
	float3 mb = renodx::color::WeightedLMSToMB(clamped);
	if (mb.z <= 1e-20f) return 1.0f;
	float2 white = renodx::color::CIE1702WhiteChromaticity();
	float2 direction = mb.xy - white;
	if (dot(direction, direction) <= 1e-14f) return 1.0f;
	bool found = false;
	float peak = renodx::color::RayExitTRGBTriangle(white, direction, bound_red, bound_green, bound_blue, found);
	float clip = renodx::color::RayExitTCIE1702(direction);
	if (!found) peak = clip;
	float hard_scale = saturate(peak);
	float soft_scale = renodx::color::GamutNeutwoScale(min(peak, clip), clip);
	float outside = 1.0f - saturate(peak);
	float activation = outside / (outside + 0.08f);
	return lerp(hard_scale, soft_scale, saturate(strength) * activation);
}

float3 CompressWeightedLMSWithScale(float3 weighted_lms, float scale) {
	float3 clamped = renodx::color::ClampWeightedLMSToCIE1702(max(weighted_lms, 0.0f));
	float3 mb = renodx::color::WeightedLMSToMB(clamped);
	if (mb.z <= 1e-20f) return float3(clamped.x, clamped.y, 0.0f);
	float2 white = renodx::color::CIE1702WhiteChromaticity();
	float2 direction = mb.xy - white;
	if (dot(direction, direction) <= 1e-14f) return clamped;
	return renodx::color::MBToWeightedLMS(white + saturate(scale) * direction, mb.z);
}

float3 DecompressWeightedLMSWithScale(float3 weighted_lms, float scale) {
	float3 nonnegative = max(weighted_lms, 0.0f);
	float3 mb = renodx::color::WeightedLMSToMB(nonnegative);
	if (mb.z <= 1e-20f) return float3(nonnegative.x, nonnegative.y, 0.0f);
	float2 white = renodx::color::CIE1702WhiteChromaticity();
	float2 direction = mb.xy - white;
	if (dot(direction, direction) <= 1e-14f) return nonnegative;
	return renodx::color::MBToWeightedLMS(white + direction * rcp(max(scale, 1e-6f)), mb.z);
}

float3 GamutCompressWeightedLMS(float3 weighted_lms, float2 bound_red, float2 bound_green, float2 bound_blue, float strength) {
	float scale = renodx::color::ComputeGamutCompressionScaleWeightedLMS(weighted_lms, bound_red, bound_green, bound_blue, strength);
	return renodx::color::CompressWeightedLMSWithScale(weighted_lms, scale);
}

float3 CompressGamutFromBT709Bounds(float3 bt709, float3 adaptive_state_lms, float2 bound_red, float2 bound_green, float2 bound_blue, float strength) {
	float3 lms = renodx::color::BT709ToLMS(bt709);
	float3 adaptive_weighted = renodx::color::DivideSafe(lms * renodx::color::LMS_WEIGHTS, adaptive_state_lms, 0.0f);
	adaptive_weighted = renodx::color::GamutCompressWeightedLMS(adaptive_weighted, bound_red, bound_green, bound_blue, strength);
	float3 final_lms = adaptive_weighted * max(adaptive_state_lms, 1e-6f) / renodx::color::LMS_WEIGHTS;
	return renodx::color::LMSToBT709(final_lms);
}

float ComputeGamutCompressionScaleBT709AdaptiveD65(float3 bt709, float3 adaptive_state_lms, float strength) {
	bt709 = renodx::color::SanitizeGamutInputBT709(bt709);
	float3 lms = renodx::color::BT709ToLMS(bt709);
	float3 weighted_relative = renodx::color::DivideSafe(lms * renodx::color::LMS_WEIGHTS, adaptive_state_lms, 0.0f);
	return renodx::color::ComputeGamutCompressionScaleWeightedLMS(weighted_relative,
			renodx::color::TargetPrimaryBT709MB(0, adaptive_state_lms), renodx::color::TargetPrimaryBT709MB(1, adaptive_state_lms),
			renodx::color::TargetPrimaryBT709MB(2, adaptive_state_lms), strength);
}

float3 GamutCompressBT709AdaptiveD65(float3 bt709, float3 adaptive_state_lms, float compression_scale) {
	bt709 = renodx::color::SanitizeGamutInputBT709(bt709);
	float3 lms = renodx::color::BT709ToLMS(bt709);
	float3 weighted_relative = renodx::color::DivideSafe(lms * renodx::color::LMS_WEIGHTS, adaptive_state_lms, 0.0f);
	float3 compressed_relative = renodx::color::CompressWeightedLMSWithScale(weighted_relative, compression_scale);
	float3 compressed_lms = compressed_relative * max(adaptive_state_lms, 1e-6f) / renodx::color::LMS_WEIGHTS;
	return renodx::color::LMSToBT709(compressed_lms);
}

float3 GamutDecompressBT709AdaptiveD65(float3 bt709, float3 adaptive_state_lms, float compression_scale) {
	float3 lms = renodx::color::BT709ToLMS(bt709);
	float3 weighted_relative = renodx::color::DivideSafe(lms * renodx::color::LMS_WEIGHTS, adaptive_state_lms, 0.0f);
	float3 decompressed_relative = renodx::color::DecompressWeightedLMSWithScale(weighted_relative, compression_scale);
	float3 decompressed_lms = decompressed_relative * max(adaptive_state_lms, 1e-6f) / renodx::color::LMS_WEIGHTS;
	return renodx::color::LMSToBT709(decompressed_lms);
}

float3 CompressGamutBT709(float3 bt709, float strength) {
	bt709 = renodx::color::SanitizeGamutInputBT709(bt709);
	if (all(bt709 >= 0.0f)) return bt709;
	float3 adaptive_state_lms = renodx::color::BT709ToLMS(float3(0.18f, 0.18f, 0.18f));
	return renodx::color::CompressGamutFromBT709Bounds(bt709, adaptive_state_lms,
			renodx::color::TargetPrimaryBT709MB(0, adaptive_state_lms), renodx::color::TargetPrimaryBT709MB(1, adaptive_state_lms),
			renodx::color::TargetPrimaryBT709MB(2, adaptive_state_lms), strength);
}

float3 CompressGamutBT2020(float3 bt2020, float strength) {
	bt2020 = renodx::color::SanitizeGamutInputBT2020(bt2020);
	if (all(bt2020 >= 0.0f)) return bt2020;
	float3 bt709 = renodx::color::BT2020ToBT709(bt2020);
	float3 adaptive_state_lms = renodx::color::BT709ToLMS(float3(0.18f, 0.18f, 0.18f));
	float3 compressed_bt709 = renodx::color::CompressGamutFromBT709Bounds(bt709, adaptive_state_lms,
			renodx::color::TargetPrimaryBT2020MB(0, adaptive_state_lms), renodx::color::TargetPrimaryBT2020MB(1, adaptive_state_lms),
			renodx::color::TargetPrimaryBT2020MB(2, adaptive_state_lms), strength);
	return renodx::color::BT709ToBT2020(compressed_bt709);
}

}
}



