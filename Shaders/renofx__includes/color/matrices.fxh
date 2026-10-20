#pragma once

namespace renodx {
namespace color {

// clang-format off
static const float3x3 BT709_TO_BT2020 = float3x3(
	0.6274039149f, 0.3292830288f, 0.0433130674f,
	0.0690972894f, 0.9195404053f, 0.0113623152f,
	0.0163914394f, 0.0880133063f, 0.8955952525f
);

static const float3x3 BT2020_TO_BT709 = float3x3(
	 1.6604910021f, -0.5876411200f, -0.0728498623f,
	-0.1245504767f,  1.1328998804f, -0.0083494224f,
	-0.0181507636f, -0.1005788967f,  1.1187297106f
);

static const float3x3 BT709_TO_XYZ = float3x3(
	0.4123907993f, 0.3575843394f, 0.1804807884f,
	0.2126390059f, 0.7151686788f, 0.0721923154f,
	0.0193308187f, 0.1191947798f, 0.9505321522f
);

static const float3x3 BT2020_TO_XYZ = float3x3(
	0.6369580483f, 0.1446169036f, 0.1688809752f,
	0.2627002120f, 0.6779980715f, 0.0593017165f,
	0.0000000000f, 0.0280726930f, 1.0609850577f
);

static const float3x3 BT709_TO_LMS = float3x3(
	0.2896057766f, 0.6972466442f, 0.0763712786f,
	0.0901837576f, 0.7073490257f, 0.1122031464f,
	0.0155287401f, 0.0536093073f, 0.5097978305f
);

static const float3x3 LMS_TO_BT709 = float3x3(
	 4.9676196501f, -4.9223795290f,  0.3391991813f,
	-0.6196828788f,  2.0517506515f, -0.3587439845f,
	-0.0861520039f, -0.0658193831f,  1.9889544835f
);

static const float3 LMS_WEIGHTS = float3(
	0.68990272f, 0.34832189f, 0.0371597069161f
);

static const float3x3 XYZ_TO_BRADFORD_LMS = float3x3(
	 0.8951000f,  0.2664000f, -0.1614000f,
	-0.7502000f,  1.7135000f,  0.0367000f,
	 0.0389000f, -0.0685000f,  1.0296000f
);

static const float3x3 BT709_TO_BRADFORD_LMS = float3x3(
	0.4226580415f, 0.4913566408f, 0.0273644972f,
	0.0556908000f, 0.9615562081f, 0.0231893750f,
	0.0213792411f, 0.0876439216f, 0.9807434330f
);

static const float3x3 BRADFORD_LMS_TO_BT709 = float3x3(
	 2.5384479276f, -1.2934827422f, -0.0402430490f,
	-0.1460003045f,  1.1166225022f, -0.0223286193f,
	-0.0422884197f, -0.0715901011f,  1.0225073225f
);

// ACEScg/AP1 conversions include Bradford D65 <-> D60 adaptation.
static const float3x3 BT709_TO_AP1 = float3x3(
	0.6130974024f, 0.3395231462f, 0.0473794514f,
	0.0701937225f, 0.9163538791f, 0.0134523985f,
	0.0206155929f, 0.1095697729f, 0.8698146342f
);

static const float3x3 AP1_TO_BT709 = float3x3(
	 1.7050509927f, -0.6217921207f, -0.0832588720f,
	-0.1302564175f,  1.1408047366f, -0.0105483191f,
	-0.0240033568f, -0.1289689761f,  1.1529723329f
);

static const float3x3 BT709_TO_OKLAB_LMS = float3x3(
	0.4122214708f, 0.5363325363f, 0.0514459929f,
	0.2119034982f, 0.6806995451f, 0.1073969566f,
	0.0883024619f, 0.2817188376f, 0.6299787005f
);

static const float3x3 OKLAB_LMS_TO_OKLAB = float3x3(
	0.2104542553f,  0.7936177850f, -0.0040720468f,
	1.9779984951f, -2.4285922050f,  0.4505937099f,
	0.0259040371f,  0.7827717662f, -0.8086757660f
);

static const float3x3 OKLAB_TO_OKLAB_LMS = float3x3(
	1.0f,  0.3963377774f,  0.2158037573f,
	1.0f, -0.1055613458f, -0.0638541728f,
	1.0f, -0.0894841775f, -1.2914855480f
);

static const float3x3 OKLAB_LMS_TO_BT709 = float3x3(
	 4.0767416621f, -3.3077115913f,  0.2309699292f,
	-1.2684380046f,  2.6097574011f, -0.3413193965f,
	-0.0041960863f, -0.7034186147f,  1.7076147010f
);
// clang-format on

float3 BT709ToBT2020(float3 color) { return mul(renodx::color::BT709_TO_BT2020, color); }
float3 BT2020ToBT709(float3 color) { return mul(renodx::color::BT2020_TO_BT709, color); }
float3 BT709ToAP1(float3 color) { return mul(renodx::color::BT709_TO_AP1, color); }
float3 AP1ToBT709(float3 color) { return mul(renodx::color::AP1_TO_BT709, color); }
float3 BT709ToLMS(float3 color) { return mul(renodx::color::BT709_TO_LMS, color); }
float3 LMSToBT709(float3 color) { return mul(renodx::color::LMS_TO_BT709, color); }
float3 XYZToBradfordLMS(float3 color) { return mul(renodx::color::XYZ_TO_BRADFORD_LMS, color); }
float3 BT709ToBradfordLMS(float3 color) { return mul(renodx::color::BT709_TO_BRADFORD_LMS, color); }
float3 BradfordLMSToBT709(float3 color) { return mul(renodx::color::BRADFORD_LMS_TO_BT709, color); }

float3 ToWorking(float3 bt709, uint working_space) {
	if (working_space == SPACE_BT2020) return renodx::color::BT709ToBT2020(bt709);
	if (working_space == SPACE_AP1) return renodx::color::BT709ToAP1(bt709);
	if (working_space == SPACE_LMS) return renodx::color::BT709ToLMS(bt709);
	return bt709;
}

float3 FromWorking(float3 working, uint working_space) {
	if (working_space == SPACE_BT2020) return renodx::color::BT2020ToBT709(working);
	if (working_space == SPACE_AP1) return renodx::color::AP1ToBT709(working);
	if (working_space == SPACE_LMS) return renodx::color::LMSToBT709(working);
	return working;
}

float3 WorkingWhite(uint working_space) {
	return renodx::color::ToWorking(float3(1.0f, 1.0f, 1.0f), working_space);
}

float WorkingLuminance(float3 working, uint working_space) {
	if (working_space == SPACE_SRGB) return dot(working, float3(0.2989f, 0.5870f, 0.1140f));
	if (working_space == SPACE_BT2020) return dot(working, float3(0.2627002120f, 0.6779980715f, 0.0593017165f));
	if (working_space == SPACE_AP1) return dot(working, float3(0.2722287168f, 0.6740817658f, 0.0536895174f));
	if (working_space == SPACE_LMS) return dot(working, float3(0.68990272f, 0.34832189f, 0.0f));
	return dot(working, float3(0.2126390059f, 0.7151686788f, 0.0721923154f));
}

}
}



