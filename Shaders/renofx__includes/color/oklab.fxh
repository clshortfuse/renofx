#pragma once

namespace renodx {
namespace color {

float3 BT709ToOKLab(float3 bt709) {
	float3 lms = mul(renodx::color::BT709_TO_OKLAB_LMS, bt709);
	lms = float3(renodx::color::SignPow(lms.x, 1.0f / 3.0f), renodx::color::SignPow(lms.y, 1.0f / 3.0f), renodx::color::SignPow(lms.z, 1.0f / 3.0f));
	return mul(renodx::color::OKLAB_LMS_TO_OKLAB, lms);
}

float3 OKLabToBT709(float3 oklab) {
	float3 lms = mul(renodx::color::OKLAB_TO_OKLAB_LMS, oklab);
	lms *= lms * lms;
	return mul(renodx::color::OKLAB_LMS_TO_BT709, lms);
}

float3 SaturateOKLab(float3 bt709, float amount) {
	float3 oklab = renodx::color::BT709ToOKLab(bt709);
	oklab.yz *= amount;
	return renodx::color::OKLabToBT709(oklab);
}

float3 SaturateWorkingYf(float3 working, float amount, uint working_space) {
	float3 bt709 = renodx::color::FromWorking(working, working_space);
	float source_yf = renodx::color::YfFromBT709(bt709);
	float3 neutral_bt709 = source_yf.xxx / max(renodx::color::YfWhite(), 1e-6f);
	float3 neutral_working = renodx::color::ToWorking(neutral_bt709, working_space);
	return neutral_working + (working - neutral_working) * amount;
}

float3 ApplySaturation(float3 working, float amount, uint working_space, uint saturation_space) {
	if (saturation_space == SATURATION_WORKING_YF) return SaturateWorkingYf(working, amount, working_space);
	float3 bt709 = renodx::color::FromWorking(working, working_space);
	return renodx::color::ToWorking(renodx::color::SaturateOKLab(bt709, amount), working_space);
}

}
}



