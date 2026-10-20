#pragma once

namespace renodx {
namespace tonemap {

float Neutwo(float value, float peak, float clip) {
	float clip_squared = clip * clip;
	float peak_squared = peak * peak;
	float value_squared = value * value;
	float numerator = clip * peak * value;
	float denominator_squared = value_squared * (clip_squared - peak_squared) + clip_squared * peak_squared;
	return numerator * rsqrt(max(denominator_squared, 1e-12f));
}

float3 Neutwo(float3 value, float3 peak, float3 clip) {
	return float3(renodx::tonemap::Neutwo(value.r, peak.r, clip.r), renodx::tonemap::Neutwo(value.g, peak.g, clip.g), renodx::tonemap::Neutwo(value.b, peak.b, clip.b));
}

float WhiteClipFromPeak(float3 peak_white, float3 normalized_white, bool use_peak_maximum) {
	if (use_peak_maximum) return max(peak_white.r, max(peak_white.g, peak_white.b));
	float3 normalized = renodx::color::DivideSafe(peak_white, normalized_white, 0.0f);
	return max(normalized.r, max(normalized.g, normalized.b));
}

float3 ApplyNeutwoWorkingSpace(float3 bt709, float peak, float clip, uint working_space) {
	if (working_space == SPACE_YF) {
		float white_yf = max(renodx::color::YfWhite(), 1e-6f);
		float source_yf = max(renodx::color::YfFromBT709(bt709), 0.0f);
		float normalized_yf = source_yf / white_yf;
		return renodx::color::ScaleToYf(bt709, source_yf, renodx::tonemap::Neutwo(normalized_yf, peak, clip) * white_yf);
	}
	if (working_space == SPACE_MAX_CHANNEL) {
		float brightest = max(bt709.r, max(bt709.g, bt709.b));
		if (brightest <= 1e-6f) return bt709;
		return bt709 * (renodx::tonemap::Neutwo(brightest, peak, clip) / brightest);
	}
	float3 white = renodx::color::WorkingWhite(working_space);
	float3 working = renodx::color::ToWorking(bt709, working_space);
	float3 normalized = renodx::color::DivideSafe(working, white, 0.0f);
	normalized = float3(renodx::tonemap::Neutwo(normalized.r, peak, clip), renodx::tonemap::Neutwo(normalized.g, peak, clip), renodx::tonemap::Neutwo(normalized.b, peak, clip));
	float3 mapped = renodx::color::RestoreWorkingHue(working, normalized * white, working_space);
	return renodx::color::FromWorking(mapped, working_space);
}

float NeutwoMaxChannelScale(float3 color, float peak, float clip) {
	float maximum = max(color.r, max(color.g, color.b));
	if (maximum <= 1e-6f) return 1.0f;
	return renodx::tonemap::Neutwo(maximum, peak, clip) / maximum;
}

float3 ApplyNeutwoMaxChannel(float3 color, float peak, float clip) {
	return color * renodx::tonemap::NeutwoMaxChannelScale(color, peak, clip);
}

}
}



