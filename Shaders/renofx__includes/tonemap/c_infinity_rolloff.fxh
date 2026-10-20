#pragma once

namespace renodx {
namespace tonemap {

// Identity through the anchor, then a C-infinity shoulder that approaches peak.
// The clipped overload maps clip to peak and remains flat above clip.
#define C_INFINITY_ROLLOFF_GENERATOR(T) \
	T CInfinityRollOff(T color, T peak, T anchor = 0.18f, float compression_strength = 1.5f) { \
		T shoulder_range = peak - anchor; \
		T distance_from_anchor = max(color - anchor, (T)0.0f); \
		T inverse_position = shoulder_range * rcp(compression_strength * distance_from_anchor); \
		T flat_weight = exp2(-inverse_position); \
		T response_denominator = mad(compression_strength, inverse_position, flat_weight); \
		return mad(shoulder_range, rcp(response_denominator), min(color, anchor)); \
	} \
	T CInfinityRollOff(T color, T peak, T anchor, float compression_strength, T clip) { \
		T shoulder_range = peak - anchor; \
		T clip_range = clip - anchor; \
		T clipped_distance = min(max(color - anchor, (T)0.0f), clip_range); \
		T remaining_distance = clip_range - clipped_distance; \
		T numerator = shoulder_range * remaining_distance; \
		T denominator = abs(clip - peak) * clipped_distance; \
		T inverse_position = denominator > 0.0f ? numerator / denominator : 0.0f; \
		T flat_weight = exp2(-inverse_position / compression_strength); \
		T transition = clipped_distance * flat_weight / (clip_range * (flat_weight + inverse_position)); \
		return mad(peak - clip, transition, min(color, clip)); \
	}

C_INFINITY_ROLLOFF_GENERATOR(float)
C_INFINITY_ROLLOFF_GENERATOR(float3)
#undef C_INFINITY_ROLLOFF_GENERATOR

float3 ApplyCInfinityRollOffWorkingSpace(
		float3 bt709,
		float peak,
		float clip,
		uint working_space,
		float anchor,
		float compression_strength) {
	if (working_space == SPACE_YF) {
		float white_yf = max(renodx::color::YfWhite(), 1e-6f);
		float source_yf = max(renodx::color::YfFromBT709(bt709), 0.0f);
		float mapped_yf = renodx::tonemap::CInfinityRollOff(source_yf / white_yf, peak, anchor, compression_strength, clip) * white_yf;
		return renodx::color::ScaleToYf(bt709, source_yf, mapped_yf);
	}
	if (working_space == SPACE_MAX_CHANNEL) {
		float brightest = max(bt709.r, max(bt709.g, bt709.b));
		if (brightest <= 1e-6f) return bt709;
		return bt709 * (renodx::tonemap::CInfinityRollOff(brightest, peak, anchor, compression_strength, clip) / brightest);
	}
	float3 white = renodx::color::WorkingWhite(working_space);
	float3 working = renodx::color::ToWorking(bt709, working_space);
	float3 normalized = renodx::color::DivideSafe(working, white, 0.0f);
	float3 mapped = renodx::tonemap::CInfinityRollOff(normalized, peak.xxx, anchor.xxx, compression_strength, clip.xxx) * white;
	mapped = renodx::color::RestoreWorkingHue(working, mapped, working_space);
	return renodx::color::FromWorking(mapped, working_space);
}

}
}



