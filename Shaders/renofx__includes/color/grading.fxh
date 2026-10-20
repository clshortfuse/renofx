#pragma once

namespace renodx {
namespace color {

float WorkingGradingLuminance(float3 working, uint working_space) {
	if (working_space == SPACE_YF) {
		return dot(renodx::color::BT709ToLMS(working), float3(0.68990272f, 0.34832189f, 0.0f));
	}
	return renodx::color::WorkingLuminance(working, working_space);
}

float3 SaturateAroundNeutral(float3 working, float amount, uint working_space) {
	float3 white = renodx::color::WorkingWhite(working_space);
	float white_luminance = max(renodx::color::WorkingGradingLuminance(white, working_space), 1e-6f);
	float luminance = renodx::color::WorkingGradingLuminance(working, working_space);
	float3 neutral = white * (luminance / white_luminance);
	return neutral + (working - neutral) * amount;
}

float3 ApplyColorGrading(
		float3 working,
		uint working_space,
		float3 peak_white,
		float pivot,
		float input_scaling_nits,
		float saturation,
		float highlight_saturation,
		float blowout,
		bool apply_global_saturation,
		uint saturation_space) {
	if ((!apply_global_saturation || saturation == 1.0f)
			&& highlight_saturation == 1.0f
			&& blowout == 0.0f) {
		return working;
	}

	float3 white = renodx::color::WorkingWhite(working_space);
	float3 adaptive_state = white * pivot;
	float3 graded = working;
	float highlight_scale = 1.0f;
	if (highlight_saturation != 1.0f) {
		float luminance = max(renodx::color::WorkingGradingLuminance(working, working_space), 0.0f);
		float neutral_luminance = max(renodx::color::WorkingGradingLuminance(adaptive_state, working_space), 1e-6f);
		float luminance_from_neutral = max(luminance, neutral_luminance) / neutral_luminance;
		float peak_from_neutral = 10000.0f / (neutral_luminance * max(input_scaling_nits, 1e-6f));
		float position = saturate(log2(luminance_from_neutral) / log2(max(peak_from_neutral, 1.00001f)));
		float rolloff = position * position * position
				* (position * (position * 6.0f - 15.0f) + 10.0f);
		highlight_scale = 1.0f - rolloff * (1.0f - highlight_saturation);
	}

	if (apply_global_saturation && saturation != 1.0f && working_space != SPACE_YF) {
		graded = renodx::color::ApplySaturation(graded, saturation, working_space, saturation_space);
	}
	if (highlight_saturation != 1.0f) {
		graded = renodx::color::SaturateAroundNeutral(graded, highlight_scale, working_space);
	}
	if (blowout != 0.0f) {
		float adaptive_luminance = max(renodx::color::WorkingGradingLuminance(adaptive_state, working_space), 1e-6f);
		float peak_luminance = max(renodx::color::WorkingGradingLuminance(peak_white, working_space), 1e-6f);
		float full_bleach_availability = rcp(1.0f + peak_luminance / adaptive_luminance);
		graded = renodx::color::SaturateAroundNeutral(graded, lerp(1.0f, full_bleach_availability, blowout), working_space);
	}
	return graded;
}

float3 CInfinityTransition(float3 position) {
	return float3(
			renodx::color::CInfinityTransition(position.r),
			renodx::color::CInfinityTransition(position.g),
			renodx::color::CInfinityTransition(position.b));
}

float3 ApplyAnchoredCInfinityGrading(
		float3 color,
		float3 anchor_in,
		float3 anchor_out,
		float contrast,
		float flare,
		float highlight_contrast,
		float shadow_contrast,
		float highlights,
		float shadows) {
	if (contrast == 1.0f && flare == 0.0f && highlight_contrast == 1.0f
			&& shadow_contrast == 1.0f && highlights == 1.0f && shadows == 1.0f
			&& all(anchor_in == anchor_out)) return color;

	float3 normalized = abs(color) / max(anchor_in, 1e-6f.xxx);
	float3 contrasted = normalized;
	if (contrast != 1.0f || flare > 0.0f) {
		float3 exponent = contrast.xxx;
		if (flare > 0.0f) {
			float3 shadow_distance = saturate(1.0f - normalized);
			float3 flat_shadow_weight = exp2(-normalized / max(shadow_distance, 1e-20f.xxx));
			exponent *= 1.0f + flat_shadow_weight * flare / max(normalized + flare, 1e-20f.xxx);
		}
		float3 input_stops = log2(max(normalized, 1e-30f.xxx));
		float3 highlight_stops = max(input_stops, 0.0f);
		float3 output_highlight_stops = highlight_stops;
		if (contrast != 1.0f) {
			float3 displacement = (contrast - 1.0f) * highlight_stops;
			float3 magnitude = abs(displacement);
			float3 falloff = exp2(-1.0f / max(magnitude, 1e-20f.xxx));
			output_highlight_stops += displacement / mad(magnitude, falloff, 1.0f);
		}
		contrasted = exp2(min(input_stops, 0.0f) * exponent + output_highlight_stops);
	}
	if (highlight_contrast != 1.0f) {
		float3 distance = max(contrasted - 1.0f, 0.0f);
		float3 distance_squared = distance * distance;
		float3 flat_distance = (1.0f + distance_squared) * exp2(-1.0f / max(distance_squared, 1e-20f.xxx));
		contrasted += distance * (pow(1.0f + flat_distance, 0.5f * (highlight_contrast - 1.0f)) - 1.0f);
	}
	if (shadow_contrast != 1.0f) {
		float3 distance = saturate(1.0f - contrasted);
		float3 distance_squared = distance * distance;
		float3 flat_distance = distance_squared * distance * exp2(1.0f - 1.0f / max(distance_squared, 1e-20f.xxx));
		contrasted *= pow(1.0f + flat_distance, shadow_contrast - 1.0f);
	}
	if (highlights != 1.0f || shadows != 1.0f) {
		float3 tonal_stops = log2(max(contrasted, 1e-30f.xxx));
		float3 displacement = 0.0f.xxx;
		if (highlights != 1.0f) {
			float adjustment = highlights - 1.0f;
			float tonal_adjustment = adjustment * mad(1.5f, abs(adjustment), 0.5f);
			displacement = tonal_adjustment * CInfinityTransition((tonal_stops - 1.0f) * 0.125f);
		}
		if (shadows != 1.0f) {
			float adjustment = shadows - 1.0f;
			float tonal_adjustment = adjustment * mad(1.5f, abs(adjustment), 0.5f);
			displacement = mad(tonal_adjustment, CInfinityTransition((-1.0f - tonal_stops) * 0.125f), displacement);
		}
		contrasted *= exp2(displacement);
	}
	return sign(color) * contrasted * anchor_out;
}

float3 ApplyAnchoredCInfinityGrading(
		float3 working,
		uint working_space,
		float pivot,
		float contrast,
		float flare,
		float highlight_contrast,
		float shadow_contrast,
		float highlights,
		float shadows) {
	float3 anchor = renodx::color::WorkingWhite(working_space) * pivot;
	return ApplyAnchoredCInfinityGrading(working, anchor, anchor, contrast, flare,
			highlight_contrast, shadow_contrast, highlights, shadows);
}

float3 ApplyCInfinityGradingYf(
		float3 bt709,
		float pivot,
		float contrast,
		float flare,
		float highlight_contrast,
		float shadow_contrast,
		float highlights,
		float shadows) {
	float white_yf = max(renodx::color::YfWhite(), 1e-6f);
	float source_yf = max(renodx::color::YfFromBT709(bt709), 0.0f);
	float normalized_yf = source_yf / white_yf;
	float graded_yf = ApplyAnchoredCInfinityGrading(
			float3(normalized_yf, normalized_yf, normalized_yf), SPACE_BT709, pivot,
			contrast, flare, highlight_contrast, shadow_contrast, highlights, shadows).x * white_yf;
	return renodx::color::ScaleToYf(bt709, source_yf, graded_yf);
}

}
}



