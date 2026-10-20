#pragma once

#define LMS_HUE_RESTORE_STRENGTH 1.0

namespace renodx {
namespace color {

float HueRestoreHalfspaceRayT(float2 origin, float2 direction, float2 normal, float numerator) {
	float denominator = dot(normal, direction);
	float2 white_to_origin = renodx::color::CIE1702WhiteChromaticity() - origin;
	float adjusted_numerator = numerator + dot(normal, white_to_origin);
	return denominator > 1e-8f ? adjusted_numerator / denominator : 1e20f;
}

float HueRestoreRayExitTCIE1702(float2 origin, float2 direction) {
	if (dot(direction, direction) <= 1e-14f) return 1e20f;
	float result = 1e20f;
	result = min(result, renodx::color::HueRestoreHalfspaceRayT(origin, direction, float2(-0.043889f, -0.006807f), 0.0065035249f));
	result = min(result, renodx::color::HueRestoreHalfspaceRayT(origin, direction, float2(-0.007821f, -0.008564f), 0.00104900495f));
	result = min(result, renodx::color::HueRestoreHalfspaceRayT(origin, direction, float2(-0.000604f, -0.007942f), 0.000207697044f));
	result = min(result, renodx::color::HueRestoreHalfspaceRayT(origin, direction, float2(0.0f, -0.080835f), 0.00165556648f));
	result = min(result, renodx::color::HueRestoreHalfspaceRayT(origin, direction, float2(0.953597f, 0.307020f), 0.252472349f));
	result = min(result, renodx::color::HueRestoreHalfspaceRayT(origin, direction, float2(-0.060969f, 0.019752f), 0.0241967351f));
	result = min(result, renodx::color::HueRestoreHalfspaceRayT(origin, direction, float2(-0.106895f, 0.004035f), 0.0199621232f));
	return max(result, 0.0f);
}

float HueRestorePuritySignal(float t_clip) {
	return t_clip > 0.0f ? saturate(rcp(t_clip)) : 0.0f;
}

float HueRestoreAdaptiveSensitivity(float t_clip) {
	static const float mean_d65_ray_distance = 0.20139844f;
	static const float max_d65_ray_distance = 1.02634534f;
	static const float minimum_sensitivity = 0.35f;
	float long_ray_weight = saturate((t_clip - mean_d65_ray_distance)
			/ (max_d65_ray_distance - mean_d65_ray_distance));
	return lerp(1.0f, minimum_sensitivity, long_ray_weight);
}

float3 RestoreLMSHue(float3 source_lms, float3 target_lms) {
	float amount = saturate(LMS_HUE_RESTORE_STRENGTH);
	if (amount <= 0.0f) return target_lms;
	float3 adaptive_state_lms = renodx::color::WorkingWhite(SPACE_LMS) * 0.18f;
	float3 source_relative_weighted = renodx::color::DivideSafe(source_lms * renodx::color::LMS_WEIGHTS, adaptive_state_lms, 0.0f);
	float3 target_relative_weighted = renodx::color::DivideSafe(target_lms * renodx::color::LMS_WEIGHTS, adaptive_state_lms, 0.0f);
	float3 source_mb = renodx::color::WeightedLMSToMB(source_relative_weighted);
	float3 target_mb = renodx::color::WeightedLMSToMB(target_relative_weighted);
	float2 adapted_neutral = renodx::color::WeightedLMSToMB(renodx::color::LMS_WEIGHTS).xy;
	float2 source_offset = source_mb.xy - adapted_neutral;
	float2 target_offset = target_mb.xy - adapted_neutral;
	float source_radius_squared = dot(source_offset, source_offset);
	float target_radius_squared = dot(target_offset, target_offset);
	if (source_radius_squared <= 1e-7f || target_radius_squared <= 1e-7f) return target_lms;

	float target_t_clip = renodx::color::HueRestoreRayExitTCIE1702(adapted_neutral, target_offset);
	float source_t_clip = renodx::color::HueRestoreRayExitTCIE1702(adapted_neutral, source_offset);
	float source_purity = renodx::color::HueRestorePuritySignal(source_t_clip);
	float target_purity = renodx::color::HueRestorePuritySignal(target_t_clip);
	float purity_weight = source_purity > 1e-7f ? saturate(target_purity / source_purity) : 1.0f;
	float restore_weight = amount * renodx::color::HueRestoreAdaptiveSensitivity(target_t_clip) * purity_weight;
	if (restore_weight <= 0.0f) return target_lms;

	float inverse_source_radius = rsqrt(source_radius_squared);
	float inverse_target_radius = rsqrt(target_radius_squared);
	float target_radius = target_radius_squared * inverse_target_radius;
	float2 source_direction = source_offset * inverse_source_radius;
	float2 target_direction = target_offset * inverse_target_radius;
	float2 restored_direction = lerp(target_direction, source_direction, saturate(restore_weight));
	float restored_length_squared = dot(restored_direction, restored_direction);
	if (restored_length_squared > 1e-7f) {
		restored_direction *= rsqrt(restored_length_squared);
	} else {
		restored_direction = target_direction;
	}
	float2 restored_chromaticity = adapted_neutral + restored_direction * target_radius;
	float3 restored_relative_weighted = renodx::color::MBToWeightedLMS(restored_chromaticity, target_mb.z);
	return restored_relative_weighted * max(adaptive_state_lms, 1e-6f) / renodx::color::LMS_WEIGHTS;
}

float3 RestoreWorkingHue(float3 source, float3 target, uint working_space) {
	if (working_space == SPACE_LMS) return RestoreLMSHue(source, target);
	return target;
}

}
}



