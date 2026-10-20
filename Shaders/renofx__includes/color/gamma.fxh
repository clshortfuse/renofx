#pragma once

namespace renodx {
namespace color {

float3 ApplyEotfGamma(float3 bt709, float gamma, uint working_space) {
	if (working_space == SPACE_BT2020) {
		float3 bt2020 = renodx::color::BT709ToBT2020(bt709);
		bt2020 = renodx::color::SignPow(renodx::color::SRGBEncode(bt2020), gamma);
		return renodx::color::BT2020ToBT709(bt2020);
	}
	if (working_space == SPACE_AP1) {
		float3 ap1 = renodx::color::BT709ToAP1(bt709);
		ap1 = renodx::color::SignPow(renodx::color::SRGBEncode(ap1), gamma);
		return renodx::color::AP1ToBT709(ap1);
	}
	if (working_space == SPACE_LMS) {
		float3 lms = renodx::color::BT709ToLMS(bt709);
		float3 white = renodx::color::WorkingWhite(SPACE_LMS);
		float3 normalized = renodx::color::DivideSafe(lms, white, 0.0f);
		normalized = renodx::color::SignPow(renodx::color::SRGBEncode(normalized), gamma);
		return renodx::color::LMSToBT709(normalized * white);
	}
	if (working_space == SPACE_YF) {
		float white_yf = max(renodx::color::YfWhite(), 1e-6f);
		float source_yf = max(renodx::color::YfFromBT709(bt709), 0.0f);
		float normalized_yf = source_yf / white_yf;
		float mapped_yf = renodx::color::SignPow(renodx::color::SRGBEncode(normalized_yf), gamma) * white_yf;
		return renodx::color::ScaleToYf(bt709, source_yf, mapped_yf);
	}
	return renodx::color::SignPow(renodx::color::SRGBEncode(bt709), gamma);
}

float3 RemoveEotfGamma(float3 bt709, float inverse_gamma, uint working_space) {
	if (working_space == SPACE_BT2020) {
		float3 bt2020 = renodx::color::BT709ToBT2020(bt709);
		bt2020 = renodx::color::SRGBDecode(renodx::color::SignPow(bt2020, inverse_gamma));
		return renodx::color::BT2020ToBT709(bt2020);
	}
	if (working_space == SPACE_AP1) {
		float3 ap1 = renodx::color::BT709ToAP1(bt709);
		ap1 = renodx::color::SRGBDecode(renodx::color::SignPow(ap1, inverse_gamma));
		return renodx::color::AP1ToBT709(ap1);
	}
	if (working_space == SPACE_LMS) {
		float3 white = renodx::color::WorkingWhite(SPACE_LMS);
		float3 normalized = renodx::color::DivideSafe(renodx::color::BT709ToLMS(bt709), white, 0.0f);
		normalized = renodx::color::SRGBDecode(renodx::color::SignPow(normalized, inverse_gamma));
		return renodx::color::LMSToBT709(normalized * white);
	}
	if (working_space == SPACE_YF) {
		float white_yf = max(renodx::color::YfWhite(), 1e-6f);
		float source_yf = max(renodx::color::YfFromBT709(bt709), 0.0f);
		float normalized_yf = source_yf / white_yf;
		float mapped_yf = renodx::color::SRGBDecode(renodx::color::SignPow(normalized_yf, inverse_gamma)) * white_yf;
		return renodx::color::ScaleToYf(bt709, source_yf, mapped_yf);
	}
	return renodx::color::SRGBDecode(renodx::color::SignPow(bt709, inverse_gamma));
}

}
}



