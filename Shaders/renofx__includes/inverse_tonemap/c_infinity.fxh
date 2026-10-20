#pragma once

namespace renodx {
namespace inverse_tonemap {

float CInfinityInverseTonemapRamp(float color, float start, float ramp_intensity) {
	if (color <= start) return 0.0f;
	float position = (color - start) / max(1.0f - start, 1e-6f);
	float warped = position / (1.0f + position);
	float ramp_exponent = rcp(max(ramp_intensity, 1e-3f));
	return position * pow(
			2.0f * renodx::color::CInfinityTransition(warped),
			ramp_exponent);
}

float CInfinityInverseTonemapPeakRamp(float input_peak, float start, float ramp_intensity) {
	float peak_ramp = renodx::inverse_tonemap::CInfinityInverseTonemapRamp(
			input_peak, start, ramp_intensity);
	return peak_ramp;
}

float CInfinityInverseTonemapWithPeakRamp(
		float color,
		float peak_multiplier,
		float peak_ramp,
		float start,
		float ramp_intensity) {
	if (peak_multiplier <= 1.0f || color <= start) return color;
	float ramp = renodx::inverse_tonemap::CInfinityInverseTonemapRamp(
			color, start, ramp_intensity);
	float calibrated_ramp = ramp / max(peak_ramp, 1e-6f);
	return color * (1.0f + (peak_multiplier - 1.0f) * calibrated_ramp);
}

float CInfinityInverseTonemap(
		float color,
		float peak_multiplier,
		float input_peak,
		float start,
		float ramp_intensity) {
	float peak_ramp = renodx::inverse_tonemap::CInfinityInverseTonemapPeakRamp(
			input_peak, start, ramp_intensity);
	if (peak_ramp <= 1e-6f) return color;
	return renodx::inverse_tonemap::CInfinityInverseTonemapWithPeakRamp(
			color, peak_multiplier, peak_ramp, start, ramp_intensity);
}

float3 CInfinityInverseTonemapWithPeakRamp(
		float3 color,
		float3 peak_multiplier,
		float peak_ramp,
		float start,
		float ramp_intensity) {
	if (peak_ramp <= 1e-6f) return color;
	return float3(
			renodx::inverse_tonemap::CInfinityInverseTonemapWithPeakRamp(color.r, peak_multiplier.r, peak_ramp, start, ramp_intensity),
			renodx::inverse_tonemap::CInfinityInverseTonemapWithPeakRamp(color.g, peak_multiplier.g, peak_ramp, start, ramp_intensity),
			renodx::inverse_tonemap::CInfinityInverseTonemapWithPeakRamp(color.b, peak_multiplier.b, peak_ramp, start, ramp_intensity));
}

float3 CInfinityInverseTonemap(
		float3 color,
		float3 peak_multiplier,
		float input_peak,
		float start,
		float ramp_intensity) {
	float peak_ramp = renodx::inverse_tonemap::CInfinityInverseTonemapPeakRamp(
			input_peak, start, ramp_intensity);
	return renodx::inverse_tonemap::CInfinityInverseTonemapWithPeakRamp(
			color, peak_multiplier, peak_ramp, start, ramp_intensity);
}

float3 ApplyCInfinityInverseTonemapWorkingSpace(
		float3 working,
		uint working_space,
		float peak_multiplier,
		float peak_ramp,
		float start,
		float ramp_intensity,
		float boost_availability) {
	if (peak_multiplier <= 1.0f || peak_ramp <= 1e-6f) return working;
	float3 white = renodx::color::WorkingWhite(working_space);
	float3 normalized = max(0.0f, renodx::color::DivideSafe(working, white, 0.0f));
	float3 fully_boosted = renodx::inverse_tonemap::CInfinityInverseTonemapWithPeakRamp(
			normalized,
			peak_multiplier.xxx,
			peak_ramp,
			start,
			ramp_intensity);
	return lerp(normalized, fully_boosted, saturate(boost_availability)) * white;
}

float3 ApplyCInfinityInverseTonemapYf(
		float3 bt709,
		float peak_multiplier,
		float peak_ramp,
		float start,
		float ramp_intensity,
		float boost_availability) {
	if (peak_multiplier <= 1.0f || peak_ramp <= 1e-6f) return bt709;
	float white_yf = max(renodx::color::YfWhite(), 1e-6f);
	float source_yf = max(renodx::color::YfFromBT709(bt709), 0.0f);
	float normalized_yf = source_yf / white_yf;
	float fully_boosted_yf = renodx::inverse_tonemap::CInfinityInverseTonemapWithPeakRamp(
			normalized_yf,
			peak_multiplier,
			peak_ramp,
			start,
			ramp_intensity) * white_yf;
	float boosted_yf = lerp(source_yf, fully_boosted_yf, saturate(boost_availability));
	return renodx::color::ScaleToYf(bt709, source_yf, boosted_yf);
}

float3 BlendHDRBoostGamutExpansion(float3 source_bt709, float3 boosted_bt709, float amount) {
	float source_yf = renodx::color::YfFromBT709(source_bt709);
	float boosted_yf = renodx::color::YfFromBT709(boosted_bt709);
	if (source_yf <= 1e-6f || boosted_yf <= 1e-6f) return boosted_bt709;
	float3 brightness_only = source_bt709 * (boosted_yf / source_yf);
	return lerp(brightness_only, boosted_bt709, saturate(amount));
}

}
}


