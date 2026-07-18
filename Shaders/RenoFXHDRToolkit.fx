#include "ReShade.fxh"

// Standalone image grading and presentation effect.
// SDR input uses BT.709. HDR10 input is decoded from BT.2020 PQ into the
// normalized linear BT.709 representation used by the processing pipeline.

#define SPACE_BT709  0
#define SPACE_BT2020 1
#define SPACE_AP1    2
#define SPACE_LMS    3
#define SPACE_YF     4
#define SPACE_MAX_CHANNEL 5

#define INPUT_AUTO   0
#define INPUT_LINEAR 1
#define INPUT_SRGB   2
#define INPUT_HDR10  3
#define INPUT_SCRGB  4

#define OUTPUT_AUTO   0
#define OUTPUT_SRGB   1
#define OUTPUT_HDR10  2
#define OUTPUT_SCRGB  3

#define COLOR_SPACE_UNKNOWN   0
#define COLOR_SPACE_SRGB      1
#define COLOR_SPACE_SCRGB     2
#define COLOR_SPACE_HDR10_PQ  3
#define COLOR_SPACE_HDR10_HLG 4

#define FORMAT_RGBA16_FLOAT 10
#define FORMAT_RGB10A2      24

#define GAMUT_TARGET_OFF    0
#define GAMUT_TARGET_AUTO   1
#define GAMUT_TARGET_BT709  2
#define GAMUT_TARGET_BT2020 3

#define GAMMA_CORRECTION_OFF 0
#define GAMMA_CORRECTION_22  1
#define GAMMA_CORRECTION_24  2

#define SATURATION_OKLAB      0
#define SATURATION_WORKING_YF 1

// Average picture level where inverse tone mapping reduction begins, expressed
// as a percentage of normalized SDR white. Override before compiling to experiment.
#ifndef HDR_BOOST_APL_START
#define HDR_BOOST_APL_START 30.0
#endif

#ifndef HDR_BOOST_APL_MINIMUM
#define HDR_BOOST_APL_MINIMUM 0.0
#endif

#ifndef LMS_HUE_RESTORE_STRENGTH
#define LMS_HUE_RESTORE_STRENGTH 1.0
#endif

// TODO: Rewrite. Too wordy to be something anybody will read.
#define SETTINGS_INSTRUCTIONS "SETUP\nChoose the Input Transfer that matches the image received by ReShade. Use sRGB for most SDR games and Linear only when the SDR input looks obviously incorrect.\n\nUse HDR10 or scRGB only for an HDR input. Input Scaling then defines the number of nits used by the HDR input. Getting the input scale correct is important for proper behavior with the color grading and hdr boost controls. If the game does not give you a paper white control or only gives an exposure control, assume 100 nits. Change the output nits to match unless you want to rescale the game.\n\nOutput Presentation controls how the result is encoded for the display. Auto is recommended. It selects sRGB for SDR or HDR10/scRGB when ReShade reports an HDR swap chain.\n\nGame Brightness scales the image linearly\n\nHDR BOOST\nHDR Boost is the primary tool for forming an HDR image. It expands bright parts of the source beyond normal game white to create HDR highlights.\n\nA value of 0 applies no inverse tone mapping. This gives you the original SDR image mapped into the HDR output at the selected Game Brightness.\n\nIncrease HDR Boost until highlights have the desired impact. HDR Boost Start controls how early that expansion begins.\n\nHDR Boost Limiter reduces the boost in scenes with a high average brightness level, preventing very bright scenes from becoming excessively bright.\n\nCOLOR GRADING\nThe color grading section is optional. Leave the controls at their neutral defaults to preserve the original appearance, or adjust them to preference after setting HDR Boost.\n\nHDR Boost should normally be the main control used to build the HDR image.\n\nESTIMATED PEAK\nShow Estimated Peak draws the peak brightness that will result from HDR Boost and the Color Grading sliders, assuming the input is limited to SDR range. If the game unclamps with swapchain or resource upgrades, this value will not be accurate.\n\nI recommend confirming the peak target using Lilium's HDR Analysis shader.\n\nTONE MAPPING\nTone mapping should normally remain Off.\n\nUse it only for games where the HDR upgrade unclamps values beyond the original SDR range and those values need to be controlled, or for a native HDR game that needs a tone mapper.\n\nADVANCED\nThere are two umbrellas that these options fall under: Per Channel adjustment and By Luminance adjustment.\n\nPer Channel: BT.709, BT.2020, AP1, LMS\nA per channel adjustment will alter hue and saturation the more extreme the transform is. Each working space will have a different look when changing the controls.\n\nBy Luminance: Yf\nThis using a conversion to find the perceived brightness of a pixel, which all channels are uniformly scaled by. This method is hue/saturation conserving."

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

// Stockman-Sharpe 2-degree cone fundamentals, composed with BT.709 <-> XYZ.
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

// Observer weights used to keep very strong colors within a visible range.
static const float3 LMS_WEIGHTS = float3(
	0.68990272f, 0.34832189f, 0.0371597069161f
);
// clang-format on

#define RENOFX_INSTRUCTIONS "Instructions\n\nNative HDR:\n\n* Make sure your Input Transfer matches the type of HDR the game uses (HDR10 or scRGB). If in doubt, HDR10 is probably right.\n* Set the correct Input Scaling. This should match the paper white option in the game, unless implemented wrong. If no paper white option is provided, 100 is a safe assumption to work around. Check KoKlusz HDR Gaming Database on GitHub to easily figure out what to use.\n* Set Input Peak Nits to the peak target used by the game. For the highest quality, set the peak target as high as it can go in-game.\n* Ensure that Output Transfer was automatically detected correctly.\n* Set Output Peak Nits to your display peak.\n\nTips: \n* Output Scaling can be used to rescale the game's brightness to your desired level.\n* The game may need SDR EOTF Emulation set to Gamma 2.2. Most HDR games get this wrong, but this is a case-by-case issue.\n* Everything should be configured properly now to freely tweak Color Grading/Inverse Tone Mapping sliders.\n\n=====================================================\n\nSDR to HDR Upgrade:\n\n* This will require another tool to upgrade the swapchain. You can use the renodx-upgrade.addon32/64, the old autohdr addon, or SK. Whatever works best for your game.\n* Set Input Transfer to sRGB. This is generally what you'll need, but if things still look wrong by the end of these steps, switch it to Linear (SDR).\n* Keep Input Scaling at 100 nits.\n* Keep Input Peak Nits at 100 nits, unless the swapchain upgrade and/or resource upgrades unclamped the game. If the game was unclamped by upgrades, set this to 10000. If unsure, 100 nits is probably correct.\n* Ensure that Output Transfer was automatically detected correctly.\n* Set Output Peak Nits to your display peak.\n\nTips: \n* Output Scaling can be used to rescale the game's brightness to your desired level.\n* The main driver for the SDR to HDR upgrade will be HDR Boost. Setting this to 40 is a good starting point.\n* The game probably needs SDR EOTF Emulation set to Gamma 2.2. Which one looks better will be a case-by-case issue.\n* Everything should be configured properly now to freely tweak Color Grading/Inverse Tone Mapping sliders.\n\n=====================================================\n\nSDR:\n\n* Auto probably worked correctly, but set Input Transfer to sRGB if not.\n* Input Scaling, Output Scaling, and Output Peak Nits do not have any impact in SDR.\n* Keep Input Peak Nits at 100.\n\n====================================================="

uniform bool INSTRUCTIONS_TEXT <
	ui_type = "button";
	ui_category = "Instructions";
	ui_category_closed = 1;
	ui_text = RENOFX_INSTRUCTIONS;
	ui_label = " ";
	noedit = 1;
	noreset = 1;
> = false;

uniform uint INPUT_TRANSFER <
	ui_type = "combo";
	ui_category = "Input";
	ui_items = "Auto\0Linear (SDR)\0sRGB (SDR)\0HDR10 (HDR)\0scRGB (HDR)\0";
	ui_label = "Input Transfer";
	ui_tooltip = "Auto detects HDR10 or scRGB from the color space reported to ReShade and uses sRGB for SDR or unknown input. Use a manual choice only if Auto produces incorrect colors or brightness.";
> = INPUT_AUTO;

uniform float INPUT_SCALING_NITS <
	ui_type = "slider";
	ui_category = "Input";
	ui_min = 1.0;
	ui_max = 1000.0;
	ui_step = 1.0;
	ui_units = " nits";
	ui_label = "Input Scaling";
	ui_tooltip = "For HDR10 and scRGB input. This should match the brightness scaling used by the game. This setting does not affect SDR input.";
> = 100.0;

uniform float MAX_INPUT_WHITE_NITS <
	ui_type = "slider";
	ui_category = "Input";
	ui_min = 100.0;
	ui_max = 10000.0;
	ui_step = 1.0;
	ui_units = " nits";
	ui_label = "Input Peak Nits";
	ui_tooltip = "Set to the peak brightness of the input image. This is used to adjust behavior for highlight saturation, blowout, and Neutwo tone mapping.\nKeep at 100 nits for SDR input, unless upgrades unclamp the image before inverse tone mapping is applied.";
> = 100.0;

uniform uint OUTPUT_TRANSFER <
	ui_type = "combo";
	ui_category = "Output";
	ui_items = "Auto\0sRGB\0HDR10 (BT.2020 PQ)\0scRGB (BT.709 Linear)\0";
	ui_label = "Output Transfer";
	ui_tooltip = "Auto detects the display mode reported to ReShade. Use a manual choice only if Auto produces incorrect colors or brightness.";
> = OUTPUT_AUTO;

uniform float GAME_BRIGHTNESS_NITS <
	ui_type = "slider";
	ui_category = "Output";
	ui_min = 1.0;
	ui_max = 500.0;
	ui_step = 1.0;
	ui_units = " nits";
	ui_label = "Output Scaling";
	ui_tooltip = "Sets the HDR reference-white brightness for HDR10 and scRGB output. This setting does not affect sRGB output.";
> = 100.0;

uniform float TONEMAP_PEAK_NITS <
	ui_type = "slider";
	ui_category = "Output";
	ui_min = 100.0;
	ui_max = 10000.0;
	ui_step = 1.0;
	ui_units = " nits";
	ui_label = "Output Peak Nits";
	ui_tooltip = "Sets the brightest value the forward tone mapper aims to preserve. Match this roughly to your display's peak brightness.\nThis setting does not apply in SDR.";
> = 1000.0;

uniform uint GAMMA_CORRECTION <
	ui_type = "combo";
	ui_category = "Output";
	ui_items = "Off\0Gamma 2.2\0Gamma 2.4\0";
	ui_label = "SDR EOTF Emulation";
	ui_tooltip = "Emulates the look of an sRGB game viewed on an SDR display at either 2.2 or 2.4. 2.2 is correct for most games.\nIf you're using this on a native HDR game and it already uses the correct gamma, set this off.";
> = GAMMA_CORRECTION_22;

uniform uint SHOW_PEAK_BRIGHTNESS <
	ui_type = "combo";
	ui_category = "Output";
	ui_items = "Off\0On\0";
	ui_label = "Show Estimated Peak";
	ui_tooltip = "Shows the estimated output brightness of Max Input White after inverse tone mapping and brightness grading. The estimate does not include APL limiting.";
> = 0;

uniform float HDR_BOOST <
	ui_type = "slider";
	ui_category = "Inverse Tone Mapping";
	ui_min = 0.0;
	ui_max = 100.0;
	ui_step = 1.0;
	ui_label = "HDR Boost";
	ui_tooltip = "Makes bright parts of the SDR image brighter in HDR. Zero turns it off; higher values create stronger highlights.";
> = 0.0;

uniform float HDR_BOOST_START <
	ui_type = "slider";
	ui_category = "Inverse Tone Mapping";
	ui_min = 0.001;
	ui_max = 1.0;
	ui_step = 0.001;
	ui_label = "HDR Boost Start";
	ui_tooltip = "Sets how early expansion begins. Lower values affect more of the image; higher values limit the boost to brighter areas.";
> = 0.100;

uniform float HDR_BOOST_GAMUT_EXPANSION <
	ui_type = "slider";
	ui_category = "Inverse Tone Mapping";
	ui_min = 0.0;
	ui_max = 100.0;
	ui_step = 1.0;
	ui_label = "Gamut Expansion";
	ui_tooltip = "Controls how much color expansion HDR Boost adds while preserving its brightness. Zero preserves the source color balance; 100 uses the full result from the selected working space.";
> = 50.0;

uniform uint HDR_BOOST_APL_LIMITER <
	ui_type = "combo";
	ui_category = "Inverse Tone Mapping";
	ui_items = "Off\0On\0";
	ui_label = "APL Limiter";
	ui_tooltip = "Lowers inverse tone mapping based on the average luminance of the full scene. This prevents very bright scenes from becoming too bright.";
> = 1;

uniform float HIGHLIGHTS <
	ui_type = "slider";
	ui_category = "Color Grading";
	ui_min = 0.0;
	ui_max = 100.0;
	ui_step = 1.0;
	ui_label = "Highlights";
	ui_tooltip = "Adjusts the bright parts of the image. 50 is unchanged; lower values soften bright areas and higher values make them stronger.";
> = 50.0;

uniform float SHADOWS <
	ui_type = "slider";
	ui_category = "Color Grading";
	ui_min = 0.0;
	ui_max = 100.0;
	ui_step = 1.0;
	ui_label = "Shadows";
	ui_tooltip = "Adjusts the dark parts of the image. 50 is unchanged; lower values deepen shadows and higher values reveal more shadow detail.";
> = 50.0;

uniform float CONTRAST <
	ui_type = "slider";
	ui_category = "Color Grading";
	ui_min = 0.0;
	ui_max = 100.0;
	ui_step = 1.0;
	ui_label = "Contrast";
	ui_tooltip = "Controls the difference between dark and bright areas. 50 is unchanged; lower values look flatter and higher values look stronger.";
> = 50.0;

uniform float SATURATION <
	ui_type = "slider";
	ui_category = "Color Grading";
	ui_min = 0.0;
	ui_max = 100.0;
	ui_step = 1.0;
	ui_label = "Saturation";
	ui_tooltip = "Controls overall color strength. 50 is unchanged; lower values reduce color and higher values make colors more vivid.";
> = 50.0;

uniform float HIGHLIGHT_SATURATION <
	ui_type = "slider";
	ui_category = "Color Grading";
	ui_min = 0.0;
	ui_max = 100.0;
	ui_step = 1.0;
	ui_label = "Highlight Saturation";
	ui_tooltip = "Controls color strength in bright areas. 50 is unchanged; lower values make highlights whiter and higher values keep more color.";
> = 50.0;

uniform float BLOWOUT <
	ui_type = "slider";
	ui_category = "Color Grading";
	ui_min = 0.0;
	ui_max = 100.0;
	ui_step = 1.0;
	ui_label = "Blowout";
	ui_tooltip = "Fades color from the brightest areas to imitate an overexposed camera image. Zero turns it off.";
> = 0.0;

uniform float FLARE <
	ui_type = "slider";
	ui_category = "Color Grading";
	ui_min = 0.0;
	ui_max = 100.0;
	ui_step = 1.0;
	ui_label = "Flare";
	ui_tooltip = "Lifts very dark areas and softens their contrast, similar to light spreading through a camera lens. Zero turns it off.";
> = 0.0;

uniform float COLOR_TEMPERATURE_KELVIN <
	ui_type = "slider";
	ui_category = "Color Grading";
	ui_min = 4000.0;
	ui_max = 9300.0;
	ui_step = 100.0;
	ui_units = " K";
	ui_label = "White Point";
	ui_tooltip = "Adjusts the image white point using Bradford chromatic adaptation. 6500 K is neutral; higher values are cooler and lower values are warmer.";
> = 6500.0;

uniform float GRADING_MID_GRAY <
	ui_type = "slider";
	ui_category = "Color Grading";
	ui_min = 0.01;
	ui_max = 1.0;
	ui_step = 0.01;
	ui_label = "Mid Gray";
	ui_tooltip = "Sets the linear mid-gray pivot used by the highlights, shadows, contrast, flare, highlight saturation, and blowout controls.";
> = 0.18;

uniform uint TONEMAP_ENABLED <
	ui_type = "combo";
	ui_category = "Tone Mapping";
	ui_items = "Off\0Neutwo\0";
	ui_label = "Tone Mapper";
	ui_tooltip = "Applies forward Neutwo compression after inverse tone mapping and grading. Max Input White becomes Neutwo's white clip. If used with a native HDR game, make sure to set input white to the game's peak brightness.";
> = 1;

uniform uint GAMUT_COMPRESSION_TARGET <
	ui_type = "combo";
	ui_category = "Tone Mapping";
	ui_items = "Off\0Auto (BT.709 SDR, BT.2020 HDR)\0BT.709\0BT.2020\0";
	ui_label = "Gamut Compression Target";
	ui_tooltip = "Prevents colors from becoming too strong for the selected output. Auto is recommended and chooses the correct range for SDR or HDR.";
> = GAMUT_TARGET_AUTO;

uniform uint HDR_BOOST_SPACE <
	ui_type = "combo";
	ui_category = "Advanced";
	ui_items = "BT.709\0BT.2020\0AP1 (ACEScg)\0LMS (Stockman-Sharpe)\0Yf (Brightness)\0";
	ui_label = "Inverse Tone Mapping Working Space";
	ui_tooltip = "Changes how inverse tone mapping reacts to color. LMS is the recommended default. Yf changes brightness while preserving the original color balance.";
> = SPACE_LMS;

uniform uint GRADING_SPACE <
	ui_type = "combo";
	ui_category = "Advanced";
	ui_items = "BT.709\0BT.2020\0AP1 (ACEScg)\0LMS (Stockman-Sharpe)\0Yf (Brightness)\0";
	ui_label = "Grading Working Space";
	ui_tooltip = "Changes how the brightness and color controls react. LMS is the recommended default. Yf adjusts brightness without shifting colors; color-only controls have no effect in that mode.";
> = SPACE_LMS;

uniform uint TONEMAP_SPACE <
	ui_type = "combo";
	ui_category = "Advanced";
	ui_items = "BT.709\0BT.2020\0AP1 (ACEScg)\0LMS (Stockman-Sharpe)\0Yf (Brightness)\0Brightest Channel\0";
	ui_label = "Tone Map Working Space";
	ui_tooltip = "Changes how bright values are controlled. LMS is the recommended default. Yf preserves color balance. Brightest Channel protects the strongest channel and scales the others with it.";
> = SPACE_LMS;

uniform uint GAMMA_CORRECTION_WORKING_SPACE <
	ui_type = "combo";
	ui_category = "Advanced";
	ui_items = "BT.709\0BT.2020\0AP1 (ACEScg)\0LMS (Stockman-Sharpe)\0Yf (Brightness)\0";
	ui_label = "Gamma Correction Working Space";
	ui_tooltip = "Select the working space used by gamma correction when enabled. BT.709 is the correct choice to emulate the screen's behavior, but other working spaces may be visually preferrable.";
> = SPACE_BT709;

uniform uint SATURATION_SPACE <
	ui_type = "combo";
	ui_category = "Advanced";
	ui_items = "OKLab (Perceptual)\0Working Space (Yf Brightness)\0";
	ui_label = "Saturation Space";
	ui_tooltip = "OKLab changes color strength more evenly across different colors. Working Space follows the selected grading space while keeping Yf brightness steady. Yf grading always uses OKLab.";
> = SATURATION_OKLAB;

texture2D APLTexture {
	Width = 256;
	Height = 256;
	MipLevels = 9;
	Format = R16F;
};

sampler2D APLSampler {
	Texture = APLTexture;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	MipFilter = LINEAR;
	AddressU = CLAMP;
	AddressV = CLAMP;
};

// Frame-global values calculated once after the APL mip chain is available.
// Texel 0 stores grading-space peak white in RGB and scene-dependent HDR Boost
// availability in alpha. Texel 1 stores the APL-independent overlay peak nits
// in red and the Bradford color-temperature adaptation in GBA.
texture2D FrameStateTexture {
	Width = 2;
	Height = 1;
	Format = RGBA32F;
};

sampler2D FrameStateSampler {
	Texture = FrameStateTexture;
	MinFilter = POINT;
	MagFilter = POINT;
	MipFilter = POINT;
	AddressU = CLAMP;
	AddressV = CLAMP;
};

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

float SRGBDecode(float channel) {
	float value = abs(channel);
	float decoded = value <= 0.04045f
			? value / 12.92f
			: pow((value + 0.055f) / 1.055f, 2.4f);
	return sign(channel) * decoded;
}

float3 SRGBDecode(float3 color) {
	return float3(
			SRGBDecode(color.r),
			SRGBDecode(color.g),
			SRGBDecode(color.b));
}

float SRGBEncode(float channel) {
	float value = abs(channel);
	float encoded = value <= 0.0031308f
			? value * 12.92f
			: 1.055f * pow(value, 1.0f / 2.4f) - 0.055f;
	return sign(channel) * encoded;
}

float3 SRGBEncode(float3 color) {
	return float3(
			SRGBEncode(color.r),
			SRGBEncode(color.g),
			SRGBEncode(color.b));
}

float3 PQEncode(float3 normalized_nits) {
	static const float m1 = 0.1593017578125f;
	static const float m2 = 78.84375f;
	static const float c1 = 0.8359375f;
	static const float c2 = 18.8515625f;
	static const float c3 = 18.6875f;

	float3 powered = pow(max(normalized_nits, 0.0f), m1);
	return pow((c1 + c2 * powered) / (1.0f + c3 * powered), m2);
}

float3 PQDecode(float3 pq) {
	static const float m1 = 0.1593017578125f;
	static const float m2 = 78.84375f;
	static const float c1 = 0.8359375f;
	static const float c2 = 18.8515625f;
	static const float c3 = 18.6875f;

	float3 powered = pow(max(pq, 0.0f), 1.0f / m2);
	float3 numerator = max(powered - c1, 0.0f);
	float3 denominator = max(c2 - c3 * powered, 1e-6f);
	return pow(numerator / denominator, 1.0f / m1);
}

uint ResolveInputTransfer() {
	if (INPUT_TRANSFER != INPUT_AUTO) return INPUT_TRANSFER;

#if defined(BUFFER_COLOR_SPACE)
	if (BUFFER_COLOR_SPACE == COLOR_SPACE_SRGB) return INPUT_SRGB;
	if (BUFFER_COLOR_SPACE == COLOR_SPACE_SCRGB) return INPUT_SCRGB;
	if (BUFFER_COLOR_SPACE == COLOR_SPACE_HDR10_PQ) return INPUT_HDR10;
	// HLG is known but unsupported; treat it as the SDR sRGB fallback.
	if (BUFFER_COLOR_SPACE == COLOR_SPACE_HDR10_HLG) return INPUT_SRGB;
#endif

#if defined(BUFFER_COLOR_FORMAT)
	if (BUFFER_COLOR_FORMAT == FORMAT_RGBA16_FLOAT) return INPUT_SCRGB;
	if (BUFFER_COLOR_FORMAT == FORMAT_RGB10A2) return INPUT_HDR10;
#elif defined(BUFFER_COLOR_BIT_DEPTH)
	if (BUFFER_COLOR_BIT_DEPTH == 16) return INPUT_SCRGB;
	if (BUFFER_COLOR_BIT_DEPTH == 10) return INPUT_HDR10;
#endif

	// Unknown metadata and ordinary SDR formats use sRGB, never linear SDR.
	return INPUT_SRGB;
}

float ResolveInputScalingNits() {
	uint input_transfer = ResolveInputTransfer();
	if (input_transfer == INPUT_HDR10 || input_transfer == INPUT_SCRGB) {
		return max(INPUT_SCALING_NITS, 1.0f);
	}
	return 100.0f;
}

float3 DecodeInput(float3 input_color) {
	uint input_transfer = ResolveInputTransfer();
	if (input_transfer == INPUT_SRGB) {
		return SRGBDecode(input_color);
	}
	if (input_transfer == INPUT_HDR10) {
		float3 bt2020_nits = PQDecode(input_color) * 10000.0f;
		return mul(BT2020_TO_BT709, bt2020_nits)
				/ ResolveInputScalingNits();
	}
	if (input_transfer == INPUT_SCRGB) {
		// scRGB is linear BT.709 where 1.0 represents 80 nits.
		return input_color * (80.0f / ResolveInputScalingNits());
	}
	return input_color;
}

uint ResolveOutputTransfer() {
	if (OUTPUT_TRANSFER != OUTPUT_AUTO) return OUTPUT_TRANSFER;

#if defined(BUFFER_COLOR_SPACE)
	// ReShade color-space metadata is authoritative when available.
	if (BUFFER_COLOR_SPACE == COLOR_SPACE_SRGB) return OUTPUT_SRGB;
	if (BUFFER_COLOR_SPACE == COLOR_SPACE_SCRGB) return OUTPUT_SCRGB;
	if (BUFFER_COLOR_SPACE == COLOR_SPACE_HDR10_PQ) return OUTPUT_HDR10;
	// HLG is known but unsupported by this effect's three output encoders.
	if (BUFFER_COLOR_SPACE == COLOR_SPACE_HDR10_HLG) return OUTPUT_SRGB;
#endif

#if defined(BUFFER_COLOR_FORMAT)
	// ReShade API format values. These are heuristics only when color-space
	// metadata is unknown: RGBA16F is normally scRGB and RGB10A2 HDR10.
	if (BUFFER_COLOR_FORMAT == FORMAT_RGBA16_FLOAT) return OUTPUT_SCRGB;
	if (BUFFER_COLOR_FORMAT == FORMAT_RGB10A2) return OUTPUT_HDR10;
#elif defined(BUFFER_COLOR_BIT_DEPTH)
	// Compatibility fallback for ReShade versions without BUFFER_COLOR_FORMAT.
	if (BUFFER_COLOR_BIT_DEPTH == 16) return OUTPUT_SCRGB;
	if (BUFFER_COLOR_BIT_DEPTH == 10) return OUTPUT_HDR10;
#endif

	return OUTPUT_SRGB;
}

float3 ToWorking(float3 bt709, uint working_space) {
	if (working_space == SPACE_BT2020) return mul(BT709_TO_BT2020, bt709);
	if (working_space == SPACE_AP1) return mul(BT709_TO_AP1, bt709);
	if (working_space == SPACE_LMS) return mul(BT709_TO_LMS, bt709);
	return bt709;
}

float3 FromWorking(float3 working, uint working_space) {
	if (working_space == SPACE_BT2020) return mul(BT2020_TO_BT709, working);
	if (working_space == SPACE_AP1) return mul(AP1_TO_BT709, working);
	if (working_space == SPACE_LMS) return mul(LMS_TO_BT709, working);
	return working;
}

float3 WorkingWhite(uint working_space) {
	return ToWorking(float3(1.0f, 1.0f, 1.0f), working_space);
}

float WorkingLuminance(float3 working, uint working_space) {
	if (working_space == SPACE_BT2020) {
		return dot(working, float3(0.2627002120f, 0.6779980715f, 0.0593017165f));
	}
	if (working_space == SPACE_AP1) {
		return dot(working, float3(0.2722287168f, 0.6740817658f, 0.0536895174f));
	}
	if (working_space == SPACE_LMS) {
		return dot(working, float3(0.68990272f, 0.34832189f, 0.0f));
	}
	return dot(working, float3(0.2126390059f, 0.7151686788f, 0.0721923154f));
}

float3 HueRestoreWeightedLMSToMB(float3 weighted_lms) {
	float y = max(weighted_lms.x + weighted_lms.y, 0.0f);
	float inverse_y = y > 0.0f ? rcp(y) : 0.0f;
	return float3(weighted_lms.x * inverse_y, weighted_lms.z * inverse_y, y);
}

float3 HueRestoreMBToWeightedLMS(float2 chromaticity, float y) {
	return float3(chromaticity.x, 1.0f - chromaticity.x, chromaticity.y) * y;
}

float2 HueRestoreCIE1702WhiteChromaticity() {
	float3 d65_lms = mul(BT709_TO_LMS, float3(1.0f, 1.0f, 1.0f));
	return HueRestoreWeightedLMSToMB(d65_lms * LMS_WEIGHTS).xy;
}

float HueRestoreHalfspaceRayT(
		float2 origin,
		float2 direction,
		float2 normal,
		float numerator) {
	float denominator = dot(normal, direction);
	float2 white_to_origin = HueRestoreCIE1702WhiteChromaticity() - origin;
	float adjusted_numerator = numerator + dot(normal, white_to_origin);
	return denominator > 1e-8f ? adjusted_numerator / denominator : 1e20f;
}

float HueRestoreRayExitTCIE1702(float2 origin, float2 direction) {
	if (dot(direction, direction) <= 1e-14f) return 1e20f;

	float result = 1e20f;
	result = min(result, HueRestoreHalfspaceRayT(origin, direction, float2(-0.043889f, -0.006807f), 0.0065035249f));
	result = min(result, HueRestoreHalfspaceRayT(origin, direction, float2(-0.007821f, -0.008564f), 0.00104900495f));
	result = min(result, HueRestoreHalfspaceRayT(origin, direction, float2(-0.000604f, -0.007942f), 0.000207697044f));
	result = min(result, HueRestoreHalfspaceRayT(origin, direction, float2(0.0f, -0.080835f), 0.00165556648f));
	result = min(result, HueRestoreHalfspaceRayT(origin, direction, float2(0.953597f, 0.307020f), 0.252472349f));
	result = min(result, HueRestoreHalfspaceRayT(origin, direction, float2(-0.060969f, 0.019752f), 0.0241967351f));
	result = min(result, HueRestoreHalfspaceRayT(origin, direction, float2(-0.106895f, 0.004035f), 0.0199621232f));
	return max(result, 0.0f);
}

float HueRestorePuritySignal(float t_clip) {
	return t_clip > 0.0f ? saturate(rcp(t_clip)) : 0.0f;
}

float HueRestoreAdaptiveSensitivity(float t_clip) {
	static const float mean_d65_ray_distance = 0.20139844f;
	static const float max_d65_ray_distance = 1.02634534f;
	static const float minimum_sensitivity = 0.35f;
	float long_ray_weight = saturate(
			(t_clip - mean_d65_ray_distance)
			/ (max_d65_ray_distance - mean_d65_ray_distance));
	return lerp(1.0f, minimum_sensitivity, long_ray_weight);
}

float3 RestoreLMSHue(float3 source_lms, float3 target_lms) {
	float amount = saturate(LMS_HUE_RESTORE_STRENGTH);
	if (amount <= 0.0f) return target_lms;

	float3 adaptive_state_lms = WorkingWhite(SPACE_LMS) * 0.18f;
	float3 source_relative_weighted = DivideSafe(
			source_lms * LMS_WEIGHTS,
			adaptive_state_lms,
			0.0f);
	float3 target_relative_weighted = DivideSafe(
			target_lms * LMS_WEIGHTS,
			adaptive_state_lms,
			0.0f);
	float3 source_mb = HueRestoreWeightedLMSToMB(source_relative_weighted);
	float3 target_mb = HueRestoreWeightedLMSToMB(target_relative_weighted);
	float2 adapted_neutral = HueRestoreWeightedLMSToMB(LMS_WEIGHTS).xy;
	float2 source_offset = source_mb.xy - adapted_neutral;
	float2 target_offset = target_mb.xy - adapted_neutral;
	float source_radius_squared = dot(source_offset, source_offset);
	float target_radius_squared = dot(target_offset, target_offset);
	if (source_radius_squared <= 1e-7f || target_radius_squared <= 1e-7f) {
		return target_lms;
	}

	float target_t_clip = HueRestoreRayExitTCIE1702(adapted_neutral, target_offset);
	float source_t_clip = HueRestoreRayExitTCIE1702(adapted_neutral, source_offset);
	float source_purity = HueRestorePuritySignal(source_t_clip);
	float target_purity = HueRestorePuritySignal(target_t_clip);
	float purity_weight = source_purity > 1e-7f
			? saturate(target_purity / source_purity)
			: 1.0f;
	float restore_weight = amount
			* HueRestoreAdaptiveSensitivity(target_t_clip)
			* purity_weight;
	if (restore_weight <= 0.0f) return target_lms;

	float inverse_source_radius = rsqrt(source_radius_squared);
	float inverse_target_radius = rsqrt(target_radius_squared);
	float target_radius = target_radius_squared * inverse_target_radius;
	float2 source_direction = source_offset * inverse_source_radius;
	float2 target_direction = target_offset * inverse_target_radius;
	float2 restored_direction = lerp(
			target_direction,
			source_direction,
			saturate(restore_weight));
	float restored_length_squared = dot(restored_direction, restored_direction);
	if (restored_length_squared > 1e-7f) {
		restored_direction *= rsqrt(restored_length_squared);
	} else {
		restored_direction = target_direction;
	}

	float2 restored_chromaticity = adapted_neutral
			+ restored_direction * target_radius;
	float3 restored_relative_weighted = HueRestoreMBToWeightedLMS(
			restored_chromaticity,
			target_mb.z);
	return restored_relative_weighted
			* max(adaptive_state_lms, 1e-6f)
			/ LMS_WEIGHTS;
}

float3 RestoreWorkingHue(
		float3 source,
		float3 target,
		uint working_space) {
	if (working_space == SPACE_LMS) {
		return RestoreLMSHue(source, target);
	}
	return target;
}

float Reinhard(float value, float peak) {
	return peak == 0.0f ? 0.0f : value * peak / (value + peak);
}

float HDRBoostChannel(float color, float power, float normalization_point) {
	if (power == 0.0f) return color;

	float smoothing = power * 2.0f;
	float powered = normalization_point
			* pow(max(color, 0.0f) / normalization_point, 1.0f + power);
	float weight = Reinhard(max(color, 0.0f), smoothing);
	return max(color, lerp(color, powered, weight));
}

float3 ApplyHDRBoostShaping(
		float3 working,
		uint working_space,
		float boost_availability) {
	float power = HDR_BOOST * 0.01f;
	if (power == 0.0f) return working;

	float3 white = WorkingWhite(working_space);
	float3 normalized = max(0.0f, DivideSafe(working, white, 0.0f));
	float3 fully_boosted = float3(
			HDRBoostChannel(normalized.r, power, HDR_BOOST_START),
			HDRBoostChannel(normalized.g, power, HDR_BOOST_START),
			HDRBoostChannel(normalized.b, power, HDR_BOOST_START));
	float3 boosted = lerp(
			normalized,
			fully_boosted,
			saturate(boost_availability)) * white;
	return boosted;
}

float3 ApplyHDRBoost(
		float3 working,
		uint working_space,
		float boost_availability) {
	if (HDR_BOOST == 0.0f || boost_availability <= 0.0f) return working;
	float3 boosted = ApplyHDRBoostShaping(
			working,
			working_space,
			boost_availability);
	return RestoreWorkingHue(working, boosted, working_space);
}

float3 SaturateAroundNeutral(
		float3 working,
		float amount,
		uint working_space) {
	float3 white = WorkingWhite(working_space);
	float white_luminance = max(WorkingLuminance(white, working_space), 1e-6f);
	float luminance = WorkingLuminance(working, working_space);
	float3 neutral = white * (luminance / white_luminance);
	return neutral + (working - neutral) * amount;
}

float3 BT709ToOKLab(float3 bt709) {
	float3 lms = mul(BT709_TO_OKLAB_LMS, bt709);
	lms = float3(
			SignPow(lms.x, 1.0f / 3.0f),
			SignPow(lms.y, 1.0f / 3.0f),
			SignPow(lms.z, 1.0f / 3.0f));
	return mul(OKLAB_LMS_TO_OKLAB, lms);
}

float3 OKLabToBT709(float3 oklab) {
	float3 lms = mul(OKLAB_TO_OKLAB_LMS, oklab);
	lms *= lms * lms;
	return mul(OKLAB_LMS_TO_BT709, lms);
}

float3 SaturateOKLab(float3 bt709, float amount) {
	float3 oklab = BT709ToOKLab(bt709);
	oklab.yz *= amount;
	return OKLabToBT709(oklab);
}

float3 SaturateWorkingYf(
		float3 working,
		float amount,
		uint working_space) {
	float3 bt709 = FromWorking(working, working_space);
	float source_yf = dot(
			mul(BT709_TO_LMS, bt709),
			float3(0.68990272f, 0.34832189f, 0.0f));
	float white_yf = dot(
			mul(BT709_TO_LMS, float3(1.0f, 1.0f, 1.0f)),
			float3(0.68990272f, 0.34832189f, 0.0f));
	float3 neutral_bt709 = float3(source_yf, source_yf, source_yf)
			/ max(white_yf, 1e-6f);
	float3 neutral_working = ToWorking(neutral_bt709, working_space);
	return neutral_working + (working - neutral_working) * amount;
}

float3 ApplyGlobalSaturation(
		float3 working,
		float amount,
		uint working_space) {
	if (SATURATION_SPACE == SATURATION_WORKING_YF) {
		return SaturateWorkingYf(working, amount, working_space);
	}

	float3 bt709 = FromWorking(working, working_space);
	return ToWorking(SaturateOKLab(bt709, amount), working_space);
}

bool IsBrightnessGradingNeutral() {
	return HIGHLIGHTS == 50.0f
			&& SHADOWS == 50.0f
			&& CONTRAST == 50.0f
			&& FLARE == 0.0f;
}

float3 ApplyBrightnessGradingShaping(float3 working, uint working_space) {
	if (IsBrightnessGradingNeutral()) return working;

	float highlights = HIGHLIGHTS * 0.02f;
	float shadows = SHADOWS * 0.02f;
	float contrast = CONTRAST * 0.02f;
	float flare = FLARE * 0.0005f;

	float3 white = WorkingWhite(working_space);
	float3 adaptive_state = white * GRADING_MID_GRAY;
	float3 graded = working;

	// Shape bright values around the middle of the visible range.
	if (highlights != 1.0f) {
		float3 normalized = DivideSafe(graded, adaptive_state, 0.0f);
		float3 curved = pow(max(normalized, 0.0f), highlights);
		if (highlights > 1.0f) {
			normalized = max(normalized, lerp(normalized, curved, saturate(normalized)));
		} else {
			normalized = lerp(normalized, curved, step(1.0f, normalized));
		}
		graded = normalized * adaptive_state;
	}

	// Shape dark values while keeping brighter values stable.
	if (shadows != 1.0f) {
		float3 scaled = DivideSafe(graded, adaptive_state, 0.0f);
		float3 shadowed = pow(max(scaled, 0.0f), 2.0f - shadows);
		scaled = lerp(shadowed, scaled, saturate(shadowed));
		graded = scaled * adaptive_state;
	}

	// Apply contrast and the optional flare adjustment.
	if (contrast != 1.0f || flare > 0.0f) {
		float3 normalized = DivideSafe(graded, adaptive_state, 0.0f);
		float3 flare_multiplier = DivideSafe(normalized + flare, normalized, 1.0f);
		float3 exponent = contrast * flare_multiplier;
		graded = float3(
				SignPow(normalized.r, exponent.r),
				SignPow(normalized.g, exponent.g),
				SignPow(normalized.b, exponent.b)) * adaptive_state;
	}

	return graded;
}

float3 ApplyBrightnessGrading(float3 working, uint working_space) {
	if (IsBrightnessGradingNeutral()) return working;
	float3 graded = ApplyBrightnessGradingShaping(working, working_space);
	return RestoreWorkingHue(working, graded, working_space);
}

float3 ApplyColorGrading(
		float3 working,
		uint working_space,
		float3 peak_white) {
	float saturation = SATURATION * 0.02f;
	float highlight_saturation = HIGHLIGHT_SATURATION * 0.02f;
	float bleaching = BLOWOUT * 0.01f;
	if (saturation == 1.0f
			&& highlight_saturation == 1.0f
			&& bleaching == 0.0f) {
		return working;
	}

	float3 white = WorkingWhite(working_space);
	float3 adaptive_state = white * GRADING_MID_GRAY;
	float3 graded = working;

	if (saturation != 1.0f && GRADING_SPACE != SPACE_YF) {
		graded = ApplyGlobalSaturation(graded, saturation, working_space);
	}

	if (highlight_saturation != 1.0f) {
		float3 relative = DivideSafe(graded, adaptive_state, 0.0f);
		float3 peak_relative = DivideSafe(peak_white, adaptive_state, 0.0f);
		float relative_luminance = max(0.0f, WorkingLuminance(relative, working_space));
		float peak_luminance = max(1.0f, WorkingLuminance(peak_relative, working_space));
		float weight = pow(smoothstep(0.0f, peak_luminance, relative_luminance), 0.375f);
		graded = SaturateAroundNeutral(
				graded,
				lerp(1.0f, highlight_saturation, weight),
				working_space);
	}

	// Reduce color in intense areas to create an overexposed look.
	if (bleaching != 0.0f) {
		float3 availability = 1.0f / (1.0f + DivideSafe(peak_white, adaptive_state, 0.0f));
		availability = lerp(float3(1.0f, 1.0f, 1.0f), availability, bleaching);
		float input_energy = graded.r + graded.g + graded.b;
		float white_energy = max(adaptive_state.r + adaptive_state.g + adaptive_state.b, 1e-6f);
		float3 white_at_energy = adaptive_state * (input_energy / white_energy);
		graded = max(0.0f, white_at_energy + (graded - white_at_energy) * availability);
	}

	return graded;
}

float3 ApplyGrading(
		float3 working,
		uint working_space,
		float3 peak_white) {
	float3 graded = ApplyBrightnessGrading(working, working_space);
	return ApplyColorGrading(graded, working_space, peak_white);
}

float3 ApplyCombinedBrightnessShaping(
		float3 working,
		uint working_space,
		float boost_availability) {
	bool boost_active = HDR_BOOST != 0.0f && boost_availability > 0.0f;
	bool grading_active = !IsBrightnessGradingNeutral();
	if (!boost_active && !grading_active) return working;

	float3 source = working;
	if (boost_active) {
		working = ApplyHDRBoostShaping(
				working,
				working_space,
				boost_availability);
	}
	if (grading_active) {
		working = ApplyBrightnessGradingShaping(working, working_space);
	}
	return RestoreWorkingHue(source, working, working_space);
}

float YfFromBT709(float3 bt709) {
	float3 lms = mul(BT709_TO_LMS, bt709);
	return dot(lms, float3(0.68990272f, 0.34832189f, 0.0f));
}

float YfWhite() {
	return YfFromBT709(float3(1.0f, 1.0f, 1.0f));
}

float3 ScaleToYf(float3 bt709, float source_yf, float target_yf) {
	if (source_yf <= 1e-6f) return bt709;
	return bt709 * (target_yf / source_yf);
}

float3 ApplyHDRBoostYf(float3 bt709, float boost_availability) {
	float power = HDR_BOOST * 0.01f;
	if (power == 0.0f) return bt709;

	float white_yf = max(YfWhite(), 1e-6f);
	float source_yf = max(YfFromBT709(bt709), 0.0f);
	float normalized_yf = source_yf / white_yf;
	float fully_boosted_yf = HDRBoostChannel(
			normalized_yf,
			power,
			HDR_BOOST_START) * white_yf;
	float boosted_yf = lerp(
			source_yf,
			fully_boosted_yf,
			saturate(boost_availability));
	return ScaleToYf(bt709, source_yf, boosted_yf);
}

float3 ApplyHDRBoostGamutExpansion(
		float3 source_bt709,
		float3 boosted_bt709) {
	float amount = saturate(HDR_BOOST_GAMUT_EXPANSION * 0.01f);
	if (amount >= 1.0f) return boosted_bt709;

	float source_yf = YfFromBT709(source_bt709);
	float boosted_yf = YfFromBT709(boosted_bt709);
	if (source_yf <= 1e-6f || boosted_yf <= 1e-6f) return boosted_bt709;

	float3 brightness_only = source_bt709 * (boosted_yf / source_yf);
	return lerp(brightness_only, boosted_bt709, amount);
}

float3 ApplyBrightnessGradingYf(float3 bt709) {
	float white_yf = max(YfWhite(), 1e-6f);
	float source_yf = max(YfFromBT709(bt709), 0.0f);
	float normalized_yf = source_yf / white_yf;
	float graded_yf = ApplyBrightnessGradingShaping(
			float3(normalized_yf, normalized_yf, normalized_yf),
			SPACE_BT709).x * white_yf;
	return ScaleToYf(bt709, source_yf, graded_yf);
}

float3 ApplyGradingYf(float3 bt709) {
	float3 graded = ApplyBrightnessGradingYf(bt709);
	float saturation = SATURATION * 0.02f;
	if (saturation != 1.0f) {
		graded = SaturateOKLab(graded, saturation);
	}
	return graded;
}

float3 EstimatePeakWhiteBT709(float boost_availability) {
	float max_input_white = max(
			MAX_INPUT_WHITE_NITS / ResolveInputScalingNits(),
			0.01f);
	float3 peak_white = max_input_white.xxx;
	if (HDR_BOOST_GAMUT_EXPANSION >= 100.0f
			&& HDR_BOOST_SPACE == GRADING_SPACE
			&& GRADING_SPACE != SPACE_YF) {
		float3 working = ToWorking(peak_white, GRADING_SPACE);
		working = ApplyCombinedBrightnessShaping(
				working,
				GRADING_SPACE,
				boost_availability);
		return FromWorking(working, GRADING_SPACE);
	}

	if (HDR_BOOST_SPACE == SPACE_YF) {
		peak_white = ApplyHDRBoostYf(peak_white, boost_availability);
	} else {
		float3 working = ToWorking(peak_white, HDR_BOOST_SPACE);
		working = ApplyHDRBoost(working, HDR_BOOST_SPACE, boost_availability);
		peak_white = FromWorking(working, HDR_BOOST_SPACE);
	}

	if (GRADING_SPACE == SPACE_YF) {
		return ApplyBrightnessGradingYf(peak_white);
	}

	float3 working = ToWorking(peak_white, GRADING_SPACE);
	working = ApplyBrightnessGrading(working, GRADING_SPACE);
	return FromWorking(working, GRADING_SPACE);
}

float3 ApplyControls(
		float3 bt709,
		float boost_availability,
		float3 estimated_peak_white_working) {
	// Keep compatible brightness operations in one working-space chain, restore
	// hue once, then apply intentional saturation and blowout adjustments.
	if (HDR_BOOST_GAMUT_EXPANSION >= 100.0f
			&& HDR_BOOST_SPACE == GRADING_SPACE
			&& GRADING_SPACE != SPACE_YF) {
		float3 working = ToWorking(bt709, GRADING_SPACE);
		working = ApplyCombinedBrightnessShaping(
				working,
				GRADING_SPACE,
				boost_availability);
		working = ApplyColorGrading(
				working,
				GRADING_SPACE,
				estimated_peak_white_working);
		return FromWorking(working, GRADING_SPACE);
	}

	float3 controlled = bt709;
	if (HDR_BOOST_SPACE == SPACE_YF) {
		controlled = ApplyHDRBoostYf(controlled, boost_availability);
	} else {
		float3 working = ToWorking(controlled, HDR_BOOST_SPACE);
		working = ApplyHDRBoost(working, HDR_BOOST_SPACE, boost_availability);
		controlled = FromWorking(working, HDR_BOOST_SPACE);
	}
	controlled = ApplyHDRBoostGamutExpansion(bt709, controlled);

	if (GRADING_SPACE == SPACE_YF) {
		controlled = ApplyGradingYf(controlled);
	} else {
		float3 working = ToWorking(controlled, GRADING_SPACE);
		working = ApplyGrading(
				working,
				GRADING_SPACE,
				estimated_peak_white_working);
		controlled = FromWorking(working, GRADING_SPACE);
	}
	return controlled;
}

float Neutwo(float value, float peak, float clip) {
	float clip_squared = clip * clip;
	float peak_squared = peak * peak;
	float value_squared = value * value;
	float numerator = clip * peak * value;
	float denominator_squared = value_squared
			* (clip_squared - peak_squared)
			+ clip_squared * peak_squared;
	return numerator * rsqrt(max(denominator_squared, 1e-12f));
}

float3 Neutwo(float3 value, float3 peak, float3 clip) {
	return float3(
		Neutwo(value.r, peak.r, clip.r),
		Neutwo(value.g, peak.g, clip.g),
		Neutwo(value.b, peak.b, clip.b));
}

float WhiteClipFromGradingPeak(float3 peak_white) {
	if (GRADING_SPACE == SPACE_YF) {
		return max(peak_white.r, max(peak_white.g, peak_white.b));
	}

	float3 normalized = DivideSafe(
			peak_white,
			WorkingWhite(GRADING_SPACE),
			0.0f);
	return max(normalized.r, max(normalized.g, normalized.b));
}

float3 ApplyNeutwo(float3 bt709, float white_clip) {
	if (TONEMAP_ENABLED == 0) return bt709;

	uint output_transfer = ResolveOutputTransfer();
	float output_peak = 1.0f;
	if (output_transfer != OUTPUT_SRGB) {
		float game_nits = max(GAME_BRIGHTNESS_NITS, 1.0f);
		output_peak = max(TONEMAP_PEAK_NITS / game_nits, 1.0f);
	}
	float peak = output_peak;
	float3 peak3 = float3(peak, peak, peak);
	if (output_transfer != OUTPUT_SRGB && GAMMA_CORRECTION != GAMMA_CORRECTION_OFF) {
		if (GAMMA_CORRECTION == GAMMA_CORRECTION_24) {
			peak = SRGBDecode(SignPow(output_peak, 1.0f / 2.4f));
		} else {
			peak = SRGBDecode(SignPow(output_peak, 1.0f / 2.2f));
		}
		peak3 = float3(peak, peak, peak);
	}
	if (white_clip <= peak) return bt709;
	float clip = max(white_clip, peak);
	float3 clip3 = max(white_clip.xxx, peak3);

	if (TONEMAP_SPACE == SPACE_YF) {
		float white_yf = max(YfWhite(), 1e-6f);
		float source_yf = max(YfFromBT709(bt709), 0.0f);
		float normalized_yf = source_yf / white_yf;
		float mapped_yf = Neutwo(normalized_yf, peak, clip) * white_yf;
		return ScaleToYf(bt709, source_yf, mapped_yf);
	}

	if (TONEMAP_SPACE == SPACE_MAX_CHANNEL) {
		float brightest = max(bt709.r, max(bt709.g, bt709.b));
		if (brightest <= 1e-6f) return bt709;
		float mapped_brightest = Neutwo(brightest, peak, clip);
		return bt709 * (mapped_brightest / brightest);
	}

	float3 white = WorkingWhite(TONEMAP_SPACE);
	float3 working = ToWorking(bt709, TONEMAP_SPACE);
	float3 normalized = DivideSafe(working, white, 0.0f);

	normalized = float3(
			Neutwo(normalized.r, peak, clip),
			Neutwo(normalized.g, peak, clip),
			Neutwo(normalized.b, peak, clip));
	float3 mapped = normalized * white;
	mapped = RestoreWorkingHue(working, mapped, TONEMAP_SPACE);
	return FromWorking(mapped, TONEMAP_SPACE);
}

// Keep very strong colors inside the selected output range while preserving
// their brightness as closely as possible.
float3 WeightedLMSToMB(float3 weighted_lms) {
	float y = max(weighted_lms.x + weighted_lms.y, 0.0f);
	float inverse_y = y > 0.0f ? rcp(y) : 0.0f;
	return float3(weighted_lms.x * inverse_y, weighted_lms.z * inverse_y, y);
}

float3 MBToWeightedLMS(float2 chromaticity, float y) {
	return float3(chromaticity.x, 1.0f - chromaticity.x, chromaticity.y) * y;
}

float2 CIE1702WhiteChromaticity() {
	float3 d65_lms = mul(BT709_TO_LMS, float3(1.0f, 1.0f, 1.0f));
	return WeightedLMSToMB(d65_lms * LMS_WEIGHTS).xy;
}

float CIE1702HalfspaceRayT(float2 direction, float2 normal, float numerator) {
	float denominator = dot(normal, direction);
	return denominator > 1e-8f ? numerator / denominator : 1e20f;
}

float RayExitTCIE1702(float2 direction) {
	if (dot(direction, direction) <= 1e-14f) return 1e20f;

	float result = 1e20f;
	result = min(result, CIE1702HalfspaceRayT(direction, float2(-0.043889f, -0.006807f), 0.0065035249f));
	result = min(result, CIE1702HalfspaceRayT(direction, float2(-0.007821f, -0.008564f), 0.00104900495f));
	result = min(result, CIE1702HalfspaceRayT(direction, float2(-0.000604f, -0.007942f), 0.000207697044f));
	result = min(result, CIE1702HalfspaceRayT(direction, float2(0.0f, -0.080835f), 0.00165556648f));
	result = min(result, CIE1702HalfspaceRayT(direction, float2(0.953597f, 0.307020f), 0.252472349f));
	result = min(result, CIE1702HalfspaceRayT(direction, float2(-0.060969f, 0.019752f), 0.0241967351f));
	result = min(result, CIE1702HalfspaceRayT(direction, float2(-0.106895f, 0.004035f), 0.0199621232f));
	return max(result, 0.0f);
}

float Cross2(float2 a, float2 b) {
	return a.x * b.y - a.y * b.x;
}

bool RaySegmentHit(float2 origin, float2 direction, float2 a, float2 b, out float hit_t) {
	hit_t = 0.0f;
	float2 edge = b - a;
	float denominator = Cross2(direction, edge);
	if (abs(denominator) <= 1e-20f) return false;

	float2 offset = a - origin;
	float t = Cross2(offset, edge) / denominator;
	float u = Cross2(offset, direction) / denominator;
	if (t < 0.0f || u < 0.0f || u > 1.0f) return false;

	hit_t = t;
	return true;
}

float RayExitTRGBTriangle(
		float2 origin,
		float2 direction,
		float2 red,
		float2 green,
		float2 blue,
		out bool found) {
	found = false;
	float result = 1e20f;
	float hit_t = 0.0f;

	if (RaySegmentHit(origin, direction, red, green, hit_t)) {
		result = min(result, hit_t);
		found = true;
	}
	if (RaySegmentHit(origin, direction, green, blue, hit_t)) {
		result = min(result, hit_t);
		found = true;
	}
	if (RaySegmentHit(origin, direction, blue, red, hit_t)) {
		result = min(result, hit_t);
		found = true;
	}
	return found ? max(result, 0.0f) : 0.0f;
}

float GamutNeutwoScale(float peak, float clip) {
	float safe_peak = max(peak, 0.0f);
	float safe_clip = max(clip, safe_peak);
	float clip_squared = safe_clip * safe_clip;
	float peak_squared = safe_peak * safe_peak;
	float denominator_squared = clip_squared - peak_squared + clip_squared * peak_squared;
	return saturate(safe_clip * safe_peak * rsqrt(max(denominator_squared, 1e-20f)));
}

float3 ClampWeightedLMSToCIE1702(float3 weighted_lms) {
	float3 clamped = max(weighted_lms, 0.0f);
	float3 mb = WeightedLMSToMB(clamped);
	if (mb.z <= 1e-20f) return float3(clamped.x, clamped.y, 0.0f);

	float2 white = CIE1702WhiteChromaticity();
	float2 direction = mb.xy - white;
	if (dot(direction, direction) <= 1e-14f) return clamped;

	float scale = min(1.0f, RayExitTCIE1702(direction));
	return MBToWeightedLMS(white + direction * scale, mb.z);
}

float2 TargetPrimaryMB(uint primary_index, bool target_bt2020, float3 adaptive_state_lms) {
	float3 primary = primary_index == 0
			? float3(1.0f, 0.0f, 0.0f)
			: (primary_index == 1
					? float3(0.0f, 1.0f, 0.0f)
					: float3(0.0f, 0.0f, 1.0f));
	float3 primary_bt709 = target_bt2020 ? mul(BT2020_TO_BT709, primary) : primary;
	float3 primary_lms = mul(BT709_TO_LMS, primary_bt709);
	float3 adaptive_weighted = DivideSafe(
			primary_lms * LMS_WEIGHTS,
			adaptive_state_lms,
			0.0f);
	return WeightedLMSToMB(adaptive_weighted).xy;
}

float3 GamutCompressWeightedLMS(
		float3 weighted_lms,
		float2 bound_red,
		float2 bound_green,
		float2 bound_blue,
		float strength) {
	float3 clamped = ClampWeightedLMSToCIE1702(max(weighted_lms, 0.0f));
	float3 mb = WeightedLMSToMB(clamped);
	if (mb.z <= 1e-20f) return float3(clamped.x, clamped.y, 0.0f);

	float2 white = CIE1702WhiteChromaticity();
	float2 direction = mb.xy - white;
	if (dot(direction, direction) <= 1e-14f) return clamped;

	bool found = false;
	float peak = RayExitTRGBTriangle(
			white,
			direction,
			bound_red,
			bound_green,
			bound_blue,
			found);
	// A boundary at or beyond the current chromaticity produces an exact
	// final scale of one in the compression path below.
	if (found && peak >= 1.0f) {
		return MBToWeightedLMS(white + direction, mb.z);
	}

	float clip = RayExitTCIE1702(direction);
	if (!found) peak = clip;

	float hard_scale = saturate(peak);
	float soft_scale = GamutNeutwoScale(min(peak, clip), clip);
	float outside = 1.0f - saturate(peak);
	float activation = outside / (outside + 0.08f);
	float final_scale = lerp(hard_scale, soft_scale, saturate(strength) * activation);
	return MBToWeightedLMS(white + direction * final_scale, mb.z);
}

float3 ApplyGamutCompression(float3 bt709) {
	if (GAMUT_COMPRESSION_TARGET == GAMUT_TARGET_OFF) return bt709;

	uint output_transfer = ResolveOutputTransfer();
	bool target_bt2020 = GAMUT_COMPRESSION_TARGET == GAMUT_TARGET_BT2020
			|| (GAMUT_COMPRESSION_TARGET == GAMUT_TARGET_AUTO
					&& output_transfer != OUTPUT_SRGB);

	// Nonnegative target RGB components prove that the chromaticity is already
	// inside the target triangle. Brightness is intentionally unbounded here.
	if (target_bt2020) {
		float3 bt2020 = mul(BT709_TO_BT2020, bt709);
		if (all(bt2020 >= 0.0f)) return bt709;
	} else {
		if (all(bt709 >= 0.0f)) return bt709;
	}

	float3 adaptive_state_lms = mul(BT709_TO_LMS, float3(0.18f, 0.18f, 0.18f));
	float2 bound_red = TargetPrimaryMB(0, target_bt2020, adaptive_state_lms);
	float2 bound_green = TargetPrimaryMB(1, target_bt2020, adaptive_state_lms);
	float2 bound_blue = TargetPrimaryMB(2, target_bt2020, adaptive_state_lms);

	float3 lms = mul(BT709_TO_LMS, bt709);
	float3 adaptive_weighted = DivideSafe(
			lms * LMS_WEIGHTS,
			adaptive_state_lms,
			0.0f);
	adaptive_weighted = GamutCompressWeightedLMS(
			adaptive_weighted,
			bound_red,
			bound_green,
			bound_blue,
			1.0f);
	float3 final_lms = adaptive_weighted
			* max(adaptive_state_lms, 1e-6f)
			/ LMS_WEIGHTS;
	return mul(LMS_TO_BT709, final_lms);
}

float3 ApplyGammaCorrectionBT709(float3 bt709, float gamma) {
	return SignPow(SRGBEncode(bt709), gamma);
}

float3 ApplyGammaCorrectionBT2020(float3 bt709, float gamma) {
	float3 bt2020 = mul(BT709_TO_BT2020, bt709);
	bt2020 = SignPow(SRGBEncode(bt2020), gamma);
	return mul(BT2020_TO_BT709, bt2020);
}

float3 ApplyGammaCorrectionAP1(float3 bt709, float gamma) {
	float3 ap1 = mul(BT709_TO_AP1, bt709);
	ap1 = SignPow(SRGBEncode(ap1), gamma);
	return mul(AP1_TO_BT709, ap1);
}

float3 ApplyGammaCorrectionLMS(float3 bt709, float gamma) {
	float3 lms = mul(BT709_TO_LMS, bt709);
	float3 white = WorkingWhite(SPACE_LMS);
	float3 normalized = DivideSafe(lms, white, 0.0f);
	normalized = SignPow(SRGBEncode(normalized), gamma);
	normalized *= white;
	return mul(LMS_TO_BT709, normalized);
}

float3 ApplyGammaCorrectionYf(float3 bt709, float gamma) {
	float white_yf = max(YfWhite(), 1e-6f);
	float source_yf = max(YfFromBT709(bt709), 0.0f);
	float normalized_yf = source_yf / white_yf;
	float mapped_yf = SignPow(SRGBEncode(normalized_yf), gamma) * white_yf;
	return ScaleToYf(bt709, source_yf, mapped_yf);
}

float3 ApplyGammaCorrection(float3 bt709) {
	float gamma = GAMMA_CORRECTION == GAMMA_CORRECTION_24 ? 2.4f : 2.2f;
	uint working_space = GAMMA_CORRECTION_WORKING_SPACE;
	if (working_space == SPACE_BT2020) {
		return ApplyGammaCorrectionBT2020(bt709, gamma);
	}
	if (working_space == SPACE_AP1) {
		return ApplyGammaCorrectionAP1(bt709, gamma);
	}
	if (working_space == SPACE_LMS) {
		return ApplyGammaCorrectionLMS(bt709, gamma);
	}
	if (working_space == SPACE_YF) {
		return ApplyGammaCorrectionYf(bt709, gamma);
	}
	return ApplyGammaCorrectionBT709(bt709, gamma);
}

float2 DaylightChromaticityFromKelvin(float kelvin) {
	float temperature = clamp(kelvin, 4000.0f, 25000.0f);
	float inverse_temperature = rcp(temperature);
	float inverse_temperature_squared = inverse_temperature * inverse_temperature;
	float inverse_temperature_cubed = inverse_temperature_squared * inverse_temperature;

	float x = temperature <= 7000.0f
			? 0.244063f
					+ 99.11f * inverse_temperature
					+ 2967800.0f * inverse_temperature_squared
					- 4607000000.0f * inverse_temperature_cubed
			: 0.237040f
					+ 247.48f * inverse_temperature
					+ 1901800.0f * inverse_temperature_squared
					- 2006400000.0f * inverse_temperature_cubed;
	float y = -3.0f * x * x + 2.87f * x - 0.275f;
	return float2(x, y);
}

float3 XYZFromxyY(float2 chromaticity, float luminance) {
	float scale = luminance / max(chromaticity.y, 1e-6f);
	return float3(
			chromaticity.x * scale,
			luminance,
			(1.0f - chromaticity.x - chromaticity.y) * scale);
}

float3 ComputeColorTemperatureAdaptation() {
	float target_kelvin = clamp(COLOR_TEMPERATURE_KELVIN, 4000.0f, 9300.0f);
	if (abs(target_kelvin - 6500.0f) < 0.5f) return 1.0f.xxx;

	float3 source_white_xyz = XYZFromxyY(float2(0.31272f, 0.32903f), 1.0f);
	float3 target_white_xyz = XYZFromxyY(
			DaylightChromaticityFromKelvin(target_kelvin),
			1.0f);
	float3 source_white_lms = mul(XYZ_TO_BRADFORD_LMS, source_white_xyz);
	float3 target_white_lms = mul(XYZ_TO_BRADFORD_LMS, target_white_xyz);
	return DivideSafe(
			target_white_lms,
			max(source_white_lms, float3(1e-6f, 1e-6f, 1e-6f)),
			1.0f);
}

float3 ApplyColorTemperature(float3 bt709, float3 adaptation) {
	if (abs(COLOR_TEMPERATURE_KELVIN - 6500.0f) < 0.5f) return bt709;
	float3 color_lms = mul(BT709_TO_BRADFORD_LMS, bt709);
	return mul(BRADFORD_LMS_TO_BT709, color_lms * adaptation);
}

float EstimatePeakNits() {
	// Evaluate the configured maximum input white at full HDR Boost availability
	// so the estimate remains independent of scene-dependent APL limiting.
	float3 probe = EstimatePeakWhiteBT709(1.0f);
	float reference_white_nits = ResolveOutputTransfer() == OUTPUT_SRGB
			? 100.0f
			: GAME_BRIGHTNESS_NITS;
	return max(probe.r, max(probe.g, probe.b)) * reference_white_nits;
}

float3 PrepareOutputLinear(
		float3 bt709,
		float white_clip,
		float3 color_temperature_adaptation) {
	uint output_transfer = ResolveOutputTransfer();
	bt709 = ApplyNeutwo(bt709, white_clip);

	if (output_transfer != OUTPUT_SRGB && GAMMA_CORRECTION != GAMMA_CORRECTION_OFF) {
		bt709 = ApplyGammaCorrection(bt709);
	}
	bt709 = ApplyColorTemperature(bt709, color_temperature_adaptation);

	return ApplyGamutCompression(bt709);
}

float3 EncodeOutput(
		float3 bt709,
		float white_clip,
		float3 color_temperature_adaptation) {
	uint output_transfer = ResolveOutputTransfer();
	bt709 = PrepareOutputLinear(
			bt709,
			white_clip,
			color_temperature_adaptation);

	if (output_transfer == OUTPUT_SRGB) {
		return SRGBEncode(bt709);
	}

	if (output_transfer == OUTPUT_HDR10) {
		float3 bt2020_nits = mul(BT709_TO_BT2020, bt709)
				* GAME_BRIGHTNESS_NITS;
		return PQEncode(bt2020_nits / 10000.0f);
	}

	// scRGB is linear BT.709 where 1.0 represents 80 nits.
	return bt709 * (GAME_BRIGHTNESS_NITS / 80.0f);
}

float4 MeasureAPL(
		float4 position : SV_Position,
		float2 texcoord : TexCoord) : SV_Target {
	if (HDR_BOOST_APL_LIMITER == 0 || HDR_BOOST <= 0.0f) {
		return 0.0f.xxxx;
	}

	float3 input_bt709 = DecodeInput(tex2D(ReShade::BackBuffer, texcoord).rgb);
	float normalized_yf = max(YfFromBT709(input_bt709), 0.0f)
			/ max(YfWhite(), 1e-6f);
	return float4(saturate(normalized_yf), 0.0f, 0.0f, 1.0f);
}

float ComputeAPLHDRBoostAvailability() {
	if (HDR_BOOST_APL_LIMITER == 0 || HDR_BOOST <= 0.0f) return 1.0f;

	float apl = tex2Dlod(
			APLSampler,
			float4(0.5f, 0.5f, 0.0f, 8.0f)).r;
	float apl_start = min(HDR_BOOST_APL_START * 0.01f, 0.999f);
	float apl_weight = smoothstep(
			apl_start,
			1.0f,
			saturate(apl));
	float minimum_percentage = HDR_BOOST_APL_MINIMUM * 0.01f;
	return lerp(1.0f, minimum_percentage, apl_weight);
}

float4 CacheFrameState(
		float4 position : SV_Position,
		float2 texcoord : TexCoord) : SV_Target {
	if (position.x >= 1.0f) {
		float estimated_peak_nits = 0.0f;
		if (SHOW_PEAK_BRIGHTNESS != 0) {
			estimated_peak_nits = EstimatePeakNits();
		}
		float3 color_temperature_adaptation = ComputeColorTemperatureAdaptation();
		return float4(estimated_peak_nits, color_temperature_adaptation);
	}

	float boost_availability = ComputeAPLHDRBoostAvailability();
	float3 estimated_peak_white = EstimatePeakWhiteBT709(boost_availability);
	float3 estimated_peak_white_working = GRADING_SPACE == SPACE_YF
			? estimated_peak_white
			: ToWorking(estimated_peak_white, GRADING_SPACE);
	return float4(estimated_peak_white_working, boost_availability);
}

float3 EncodeOverlayNits(float nits) {
	float safe_nits = max(nits, 0.0f);
	uint output_transfer = ResolveOutputTransfer();
	if (output_transfer == OUTPUT_HDR10) {
		return PQEncode((safe_nits / 10000.0f).xxx);
	}
	if (output_transfer == OUTPUT_SCRGB) {
		return (safe_nits / 80.0f).xxx;
	}
	return SRGBEncode(saturate(safe_nits / 100.0f).xxx);
}

// Compact inline 5x7 font containing only the characters needed by the peak
// overlay. Four top rows and three bottom rows are packed separately in base
// 32, keeping every packed value exactly representable as a float.
float2 PeakGlyph(int ascii) {
	if (ascii == 48) return float2(708142.0f, 14905.0f);
	if (ascii == 49) return float2(135364.0f, 14468.0f);
	if (ascii == 50) return float2(279086.0f, 31812.0f);
	if (ascii == 51) return float2(475678.0f, 15888.0f);
	if (ascii == 52) return float2(305544.0f, 8479.0f);
	if (ascii == 53) return float2(492607.0f, 15888.0f);
	if (ascii == 54) return float2(492620.0f, 14897.0f);
	if (ascii == 55) return float2(139807.0f, 2114.0f);
	if (ascii == 56) return float2(476718.0f, 14897.0f);
	if (ascii == 57) return float2(1001006.0f, 6416.0f);
	if (ascii == 80) return float2(509487.0f, 1057.0f);
	if (ascii == 101) return float2(571392.0f, 14399.0f);
	if (ascii == 97) return float2(538624.0f, 31294.0f);
	if (ascii == 107) return float2(312353.0f, 17703.0f);
	if (ascii == 58) return float2(4224.0f, 132.0f);
	if (ascii == 46) return float2(0.0f, 6336.0f);
	if (ascii == 110) return float2(572416.0f, 17969.0f);
	if (ascii == 105) return float2(137220.0f, 14468.0f);
	if (ascii == 116) return float2(80962.0f, 12866.0f);
	if (ascii == 115) return float2(63488.0f, 15886.0f);
	return 0.0f.xx;
}

float PowInteger(float base, int exponent) {
	float result = 1.0f;
	for (int index = 0; index < exponent; index++) {
		result *= base;
	}
	return result;
}

int PeakOverlayCharacter(int index, float peak_nits) {
	if (index == 0) return 80;
	if (index == 1) return 101;
	if (index == 2) return 97;
	if (index == 3) return 107;
	if (index == 4) return 58;
	if (index == 5 || index == 13) return 32;

	float rounded_tenths = floor(clamp(peak_nits, 0.0f, 99999.9f) * 10.0f + 0.5f);
	int integer_value = int(floor(rounded_tenths * 0.1f));
	int decimal_value = int(rounded_tenths - float(integer_value * 10));

	if (index >= 6 && index <= 10) {
		int digit_index = index - 6;
		int divisor = int(PowInteger(10.0f, 4 - digit_index));
		if (digit_index < 4 && integer_value < divisor) return 32;
		return 48 + (integer_value / divisor) % 10;
	}
	if (index == 11) return 46;
	if (index == 12) return 48 + decimal_value;
	if (index == 14) return 110;
	if (index == 15) return 105;
	if (index == 16) return 116;
	if (index == 17) return 115;
	return 32;
}

float PeakTextCoverage(float2 pixel_position, float2 origin, float scale, float peak_nits) {
	float2 local = (pixel_position - origin) / scale;
	if (local.x < 0.0f || local.y < 0.0f || local.y >= 7.0f) return 0.0f;

	int character_index = int(floor(local.x / 6.0f));
	if (character_index < 0 || character_index >= 18) return 0.0f;

	int column = int(floor(local.x - float(character_index) * 6.0f));
	int row = int(floor(local.y));
	if (column < 0 || column >= 5) return 0.0f;

	float2 glyph = PeakGlyph(PeakOverlayCharacter(character_index, peak_nits));
	float packed_rows = row < 4 ? glyph.x : glyph.y;
	int packed_row = row < 4 ? row : row - 4;
	float row_mask = floor(packed_rows / PowInteger(32.0f, packed_row));
	row_mask -= floor(row_mask / 32.0f) * 32.0f;
	float pixel_bit = floor(row_mask / PowInteger(2.0f, column));
	return pixel_bit - floor(pixel_bit * 0.5f) * 2.0f;
}

float4 DrawPeakBrightness(float4 output, float2 pixel_position) {
	if (SHOW_PEAK_BRIGHTNESS == 0) return output;

	float scale = max(2.0f, floor(BUFFER_HEIGHT / 540.0f));
	float2 panel_min = float2(12.0f, 12.0f) * scale;
	float2 panel_max = panel_min + float2(122.0f, 17.0f) * scale;
	bool inside_panel = all(pixel_position >= panel_min)
			&& all(pixel_position <= panel_max);
	if (!inside_panel) return output;

	float peak_nits = tex2Dlod(
			FrameStateSampler,
			float4(0.75f, 0.5f, 0.0f, 0.0f)).r;
	float2 text_origin = panel_min + float2(7.0f, 5.0f) * scale;

	float text_nits = ResolveOutputTransfer() == OUTPUT_SRGB
			? 100.0f
			: max(100.0f, min(GAME_BRIGHTNESS_NITS, 203.0f));

	output.rgb = lerp(output.rgb, EncodeOverlayNits(0.0f), 0.72f);

	float text_coverage = PeakTextCoverage(pixel_position, text_origin, scale, peak_nits);
	output.rgb = lerp(output.rgb, EncodeOverlayNits(text_nits), text_coverage);
	return output;
}

float4 Main(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target {
	float4 input = tex2D(ReShade::BackBuffer, texcoord);
	float3 bt709 = DecodeInput(input.rgb);
	float4 frame_state = tex2Dlod(
			FrameStateSampler,
			float4(0.25f, 0.5f, 0.0f, 0.0f));
	float white_clip = WhiteClipFromGradingPeak(frame_state.rgb);
	float3 color_temperature_adaptation = 1.0f.xxx;
	if (abs(COLOR_TEMPERATURE_KELVIN - 6500.0f) >= 0.5f) {
		color_temperature_adaptation = tex2Dlod(
				FrameStateSampler,
				float4(0.75f, 0.5f, 0.0f, 0.0f)).gba;
	}
	bt709 = ApplyControls(bt709, frame_state.a, frame_state.rgb);

	float4 output = float4(
			EncodeOutput(
					bt709,
					white_clip,
					color_temperature_adaptation),
			input.a);
	return DrawPeakBrightness(output, position.xy);
}

technique RenoFX <
	ui_label = "RenoFX HDR Toolkit";
	ui_tooltip = "Processes SDR or native HDR input with HDR expansion, color grading, tone mapping, gamut handling, and SDR or HDR output presentation.";
> {
	pass MeasureAveragePictureLevel {
		VertexShader = PostProcessVS;
		PixelShader = MeasureAPL;
		RenderTarget = APLTexture;
		GenerateMipmaps = true;
	}

	pass BuildFrameState {
		VertexShader = PostProcessVS;
		PixelShader = CacheFrameState;
		RenderTarget = FrameStateTexture;
		GenerateMipmaps = false;
	}

	pass Composite {
		VertexShader = PostProcessVS;
		PixelShader = Main;
		GenerateMipmaps = false;
	}
}
