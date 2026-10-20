#pragma once

namespace renodx {
namespace color {

float SignPow(float value, float power) {
	return sign(value) * pow(abs(value), power);
}

float3 SignPow(float3 value, float power) {
	return sign(value) * pow(abs(value), power);
}

float3 DivideSafe(float3 numerator, float3 denominator, float fallback) {
	return float3(
			denominator.r != 0.0f ? numerator.r / denominator.r : fallback,
			denominator.g != 0.0f ? numerator.g / denominator.g : fallback,
			denominator.b != 0.0f ? numerator.b / denominator.b : fallback);
}

float CInfinityTransition(float position) {
	position = saturate(position);
	if (position <= 0.0f) return 0.0f;
	if (position >= 1.0f) return 1.0f;
	return rcp(1.0f + exp2((1.0f - 2.0f * position) / (position * (1.0f - position))));
}

}
}



