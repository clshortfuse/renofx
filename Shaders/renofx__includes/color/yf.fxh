#pragma once

namespace renodx {
namespace color {

float YfFromBT709(float3 bt709) {
	return dot(renodx::color::BT709ToLMS(bt709), float3(0.68990272f, 0.34832189f, 0.0f));
}

float YfWhite() {
	return renodx::color::YfFromBT709(float3(1.0f, 1.0f, 1.0f));
}

float3 ScaleToYf(float3 bt709, float source_yf, float target_yf) {
	if (source_yf <= 1e-6f) return bt709;
	return bt709 * (target_yf / source_yf);
}

}
}



