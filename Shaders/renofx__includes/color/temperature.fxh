#pragma once

namespace renodx {
namespace color {

float2 DaylightChromaticityFromKelvin(float kelvin) {
	float temperature = clamp(kelvin, 4000.0f, 25000.0f);
	float inverse_temperature = rcp(temperature);
	float inverse_temperature_squared = inverse_temperature * inverse_temperature;
	float inverse_temperature_cubed = inverse_temperature_squared * inverse_temperature;
	float x = temperature <= 7000.0f
			? 0.244063f + 99.11f * inverse_temperature
					+ 2967800.0f * inverse_temperature_squared
					- 4607000000.0f * inverse_temperature_cubed
			: 0.237040f + 247.48f * inverse_temperature
					+ 1901800.0f * inverse_temperature_squared
					- 2006400000.0f * inverse_temperature_cubed;
	float y = -3.0f * x * x + 2.87f * x - 0.275f;
	return float2(x, y);
}

float3 XYZFromxyY(float2 chromaticity, float luminance) {
	float scale = luminance / max(chromaticity.y, 1e-6f);
	return float3(chromaticity.x * scale, luminance,
			(1.0f - chromaticity.x - chromaticity.y) * scale);
}

float3 BradfordAdaptationFromKelvin(float kelvin) {
	float target_kelvin = clamp(kelvin, 4000.0f, 9300.0f);
	if (abs(target_kelvin - 6500.0f) < 0.5f) return 1.0f.xxx;
	float3 source_white_xyz = renodx::color::XYZFromxyY(float2(0.31272f, 0.32903f), 1.0f);
	float3 target_white_xyz = renodx::color::XYZFromxyY(renodx::color::DaylightChromaticityFromKelvin(target_kelvin), 1.0f);
	float3 source_white_lms = renodx::color::XYZToBradfordLMS(source_white_xyz);
	float3 target_white_lms = renodx::color::XYZToBradfordLMS(target_white_xyz);
	return renodx::color::DivideSafe(target_white_lms,
			max(source_white_lms, float3(1e-6f, 1e-6f, 1e-6f)), 1.0f);
}

float3 ApplyBradfordAdaptation(float3 bt709, float3 adaptation) {
	if (all(adaptation == 1.0f.xxx)) return bt709;
	float3 color_lms = renodx::color::BT709ToBradfordLMS(bt709);
	return renodx::color::BradfordLMSToBT709(color_lms * adaptation);
}

float3 ApplyBradfordWhitePoint(float3 bt709, float kelvin) {
	return renodx::color::ApplyBradfordAdaptation(bt709, renodx::color::BradfordAdaptationFromKelvin(kelvin));
}

}
}



