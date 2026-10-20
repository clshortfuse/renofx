#pragma once

// Public aggregate for shared color, tone-map, and inverse-tone-map helpers.
#define SPACE_BT709 0
#define SPACE_BT2020 1
#define SPACE_AP1 2
#define SPACE_LMS 3
#define SPACE_YF 4
#define SPACE_MAX_CHANNEL 5
#define SPACE_SRGB 6

#define SATURATION_OKLAB 0
#define SATURATION_WORKING_YF 1

#include "matrices.fxh"
#include "core_math.fxh"
#include "yf.fxh"
#include "RenoFXTransfer.fxh"
#include "RenoFXGrading.fxh"
#include "macleod_boynton.fxh"
#include "hue.fxh"
#include "gamut.fxh"
#include "../inverse_tonemap/RenoFXInverseTonemap.fxh"
#include "../tonemap/RenoFXTonemap.fxh"
