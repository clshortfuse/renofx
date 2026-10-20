#pragma once

namespace renodx {
namespace color {

float SRGBDecode(float channel) {
	float value = abs(channel);
	float decoded = value <= 0.04045f
			? value / 12.92f
			: pow((value + 0.055f) / 1.055f, 2.4f);
	return sign(channel) * decoded;
}

float3 SRGBDecode(float3 color) {
	return float3(renodx::color::SRGBDecode(color.r), renodx::color::SRGBDecode(color.g), renodx::color::SRGBDecode(color.b));
}

float SRGBEncode(float channel) {
	float value = abs(channel);
	float encoded = value <= 0.0031308f
			? value * 12.92f
			: 1.055f * pow(value, 1.0f / 2.4f) - 0.055f;
	return sign(channel) * encoded;
}

float3 SRGBEncode(float3 color) {
	return float3(renodx::color::SRGBEncode(color.r), renodx::color::SRGBEncode(color.g), renodx::color::SRGBEncode(color.b));
}

}
}



