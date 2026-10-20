#include "ReShade.fxh"
#include "renofx__includes/color/RenoFXColor.fxh"

// Image grading and presentation effect with optional split scene/UI output.
// SDR input uses BT.709. HDR10 input is decoded from BT.2020 PQ into the
// normalized linear BT.709 representation used by the processing pipeline.

#define INPUT_AUTO   0
#define INPUT_LINEAR 1
#define INPUT_SRGB   2
#define INPUT_GAMMA22 3
#define INPUT_BT1886  4
#define INPUT_HDR10  5
#define INPUT_SCRGB  6

#define OUTPUT_AUTO    0
#define OUTPUT_LINEAR  1
#define OUTPUT_SRGB    2
#define OUTPUT_GAMMA22 3
#define OUTPUT_BT1886  4
#define OUTPUT_HDR10   5
#define OUTPUT_SCRGB   6

#define COLOR_SPACE_UNKNOWN   0
#define COLOR_SPACE_SRGB      1
#define COLOR_SPACE_SCRGB     2
#define COLOR_SPACE_HDR10_PQ  3
#define COLOR_SPACE_HDR10_HLG 4

#define FORMAT_RGBA16_FLOAT 10
#define FORMAT_RGB10A2      24

#define RENOFX_MENU_MODE_AUTO 0
#define RENOFX_MENU_MODE_SDR  1
#define RENOFX_MENU_MODE_HDR  2

#define HANS_MODE_OFF      0
#define HANS_MODE_AUTO_SDR 1

// Override with RENOFX_MENU_MODE set to 1 (SDR) or 2 (HDR) in ReShade's
// preprocessor definitions. Auto uses recognized color-space metadata first,
// then target format/bit depth; inconclusive detection selects the SDR menu.
#ifndef RENOFX_MENU_MODE
	#define RENOFX_MENU_MODE RENOFX_MENU_MODE_AUTO
#endif

#if RENOFX_MENU_MODE == RENOFX_MENU_MODE_SDR
	#define RENOFX_ACTIVE_MENU_MODE RENOFX_MENU_MODE_SDR
#elif RENOFX_MENU_MODE == RENOFX_MENU_MODE_HDR
	#define RENOFX_ACTIVE_MENU_MODE RENOFX_MENU_MODE_HDR
#elif defined(BUFFER_COLOR_SPACE) \
		&& (BUFFER_COLOR_SPACE == COLOR_SPACE_HDR10_PQ \
				|| BUFFER_COLOR_SPACE == COLOR_SPACE_HDR10_HLG \
				|| BUFFER_COLOR_SPACE == COLOR_SPACE_SCRGB)
	#define RENOFX_ACTIVE_MENU_MODE RENOFX_MENU_MODE_HDR
#elif defined(BUFFER_COLOR_SPACE) \
		&& BUFFER_COLOR_SPACE == COLOR_SPACE_SRGB
	#define RENOFX_ACTIVE_MENU_MODE RENOFX_MENU_MODE_SDR
#elif defined(BUFFER_COLOR_FORMAT) \
		&& (BUFFER_COLOR_FORMAT == FORMAT_RGBA16_FLOAT \
				|| BUFFER_COLOR_FORMAT == FORMAT_RGB10A2)
	#define RENOFX_ACTIVE_MENU_MODE RENOFX_MENU_MODE_HDR
#elif defined(BUFFER_COLOR_BIT_DEPTH)
	#if BUFFER_COLOR_BIT_DEPTH == 16 || BUFFER_COLOR_BIT_DEPTH == 10
		#define RENOFX_ACTIVE_MENU_MODE RENOFX_MENU_MODE_HDR
	#else
		#define RENOFX_ACTIVE_MENU_MODE RENOFX_MENU_MODE_SDR
	#endif
#else
	#define RENOFX_ACTIVE_MENU_MODE RENOFX_MENU_MODE_SDR
#endif

#if RENOFX_ACTIVE_MENU_MODE == RENOFX_MENU_MODE_HDR
	#define RENOFX_UI_INPUT_CATEGORY      "Input"
	#define RENOFX_UI_OUTPUT_CATEGORY     "Output"
	#define RENOFX_UI_BOOST_CATEGORY      "HDR Boost"
	#define RENOFX_UI_COLOR_CATEGORY      "Color Grading"
	#define RENOFX_UI_TONEMAP_CATEGORY    "Tone Mapping"
	#define RENOFX_UI_ADVANCED_CATEGORY   "Advanced"
#else
	#define RENOFX_UI_INPUT_CATEGORY      "Input"
	#define RENOFX_UI_OUTPUT_CATEGORY     "Output"
	#define RENOFX_UI_BOOST_CATEGORY     "HDR Boost"
	#define RENOFX_UI_COLOR_CATEGORY     "Color Grading"
	#define RENOFX_UI_TONEMAP_CATEGORY   "Tone Mapping"
	#define RENOFX_UI_ADVANCED_CATEGORY  "Advanced"
#endif

#define GAMMA_CORRECTION_OFF 0
#define GAMMA_CORRECTION_22  1
#define GAMMA_CORRECTION_24  2

#define PIPELINE_DEBUG_OFF                0
#define PIPELINE_DEBUG_SWAPCHAIN          1
#define PIPELINE_DEBUG_SPLIT_INTERMEDIATE 2

// Average picture level where inverse tone mapping reduction begins, expressed
// as a percentage of normalized SDR white. Override before compiling to experiment.
#define HDR_BOOST_APL_START 30.0
#define HDR_BOOST_APL_MINIMUM 0.0

// TODO: Rewrite. Too wordy to be something anybody will read.
#define SETTINGS_INSTRUCTIONS "SETUP\nChoose the Input Transfer that matches the image received by ReShade. Use sRGB for most SDR games and Linear only when the SDR input looks obviously incorrect.\n\nUse HDR10 or scRGB only for an HDR input. Input Scaling then defines the number of nits used by the HDR input. Getting the input scale correct is important for proper behavior with the color grading and hdr boost controls. If the game does not give you a paper white control or only gives an exposure control, assume 100 nits. Change the output nits to match unless you want to rescale the game.\n\nOutput Presentation controls how the result is encoded for the display. Auto is recommended. It selects sRGB for SDR or HDR10/scRGB when ReShade reports an HDR swap chain.\n\nGame Brightness scales the image linearly\n\nHDR BOOST\nHDR Boost sets the relative peak output for reference-white input. 1x applies no boost; 2x targets twice the input brightness, up to 10x. HDR Boost Start controls where the increase begins.\n\nHDR Boost Limiter reduces the boost in scenes with a high average brightness level, preventing very bright scenes from becoming excessively bright.\n\nCOLOR GRADING\nThe color grading section is optional. Leave the controls at their neutral defaults to preserve the original appearance, or adjust them to preference after setting HDR Boost.\n\nHDR Boost should normally be the main control used to build the HDR image.\n\nESTIMATED PEAK\nShow Estimated Peak draws the peak brightness that will result from HDR Boost and the Color Grading sliders, assuming the input is limited to SDR range. If the game unclamps with swapchain or resource upgrades, this value will not be accurate.\n\nI recommend confirming the peak target using Lilium's HDR Analysis shader.\n\nTONE MAPPING\nTone mapping should normally remain Off.\n\nUse it only for games where the HDR upgrade unclamps values beyond the original SDR range and those values need to be controlled, or for a native HDR game that needs a tone mapper.\n\nADVANCED\nThere are two umbrellas that these options fall under: Per Channel adjustment and By Luminance adjustment.\n\nPer Channel: BT.709, BT.2020, AP1, LMS\nA per channel adjustment will alter hue and saturation the more extreme the transform is. Each working space will have a different look when changing the controls.\n\nBy Luminance: Yf\nThis using a conversion to find the perceived brightness of a pixel, which all channels are uniformly scaled by. This method is hue/saturation conserving."

#define RENOFX_INSTRUCTIONS "Instructions\n\nNative HDR:\n\n* Make sure your Input Transfer matches the type of HDR the game uses (HDR10 or scRGB). If in doubt, HDR10 is probably right.\n* Set the correct Input Scaling. This should match the paper white option in the game, unless implemented wrong. If no paper white option is provided, 100 is a safe assumption to work around. Check KoKlusz HDR Gaming Database on GitHub to easily figure out what to use.\n* Set Input Peak Nits to the peak target used by the game. For the highest quality, set the peak target as high as it can go in-game.\n* Ensure that Output Transfer was automatically detected correctly.\n* Set Output Peak Nits to your display peak.\n\nTips: \n* Output Scaling can be used to rescale the game's brightness to your desired level.\n* The game may need SDR EOTF Emulation set to Gamma 2.2. Most HDR games get this wrong, but this is a case-by-case issue.\n* Everything should be configured properly now to freely tweak Color Grading/Inverse Tone Mapping sliders.\n\n=====================================================\n\nSDR to HDR Upgrade:\n\n* This will require another tool to upgrade the swapchain. You can use the renodx-upgrade.addon32/64, the old autohdr addon, or SK. Whatever works best for your game.\n* Set Input Transfer to sRGB. This is generally what you'll need, but if things still look wrong by the end of these steps, switch it to Linear (SDR).\n* Keep Input Scaling at 100 nits.\n* Keep Input Peak Nits at 100 nits, unless the swapchain upgrade and/or resource upgrades unclamped the game. If the game was unclamped by upgrades, set this to 10000. If unsure, 100 nits is probably correct.\n* Ensure that Output Transfer was automatically detected correctly.\n* Set Output Peak Nits to your display peak.\n\nTips: \n* Output Scaling can be used to rescale the game's brightness to your desired level.\n* Set HDR Boost by relative peak: 1x leaves reference white unchanged, while 2x targets double brightness. Adjust upward to taste.\n* The game probably needs SDR EOTF Emulation set to Gamma 2.2. Which one looks better will be a case-by-case issue.\n* Everything should be configured properly now to freely tweak Color Grading/Inverse Tone Mapping sliders.\n\n=====================================================\n\nSDR:\n\n* Auto probably worked correctly, but set Input Transfer to sRGB if not.\n* Input Scaling, Output Scaling, and Output Peak Nits do not have any impact in SDR.\n* Keep Input Peak Nits at 100.\n\n====================================================="

uniform bool INSTRUCTIONS_TEXT <
	ui_type = "button";
	ui_category = "Instructions";
	ui_category_closed = 1;
	ui_text = RENOFX_INSTRUCTIONS;
	ui_label = " ";
	noedit = 1;
	noreset = 1;
> = false;

uniform uint FRAME_COUNT < source = "framecount"; >;

#if RENOFX_ACTIVE_MENU_MODE == RENOFX_MENU_MODE_HDR
uniform uint INPUT_TRANSFER <
	ui_type = "combo";
	ui_category = RENOFX_UI_INPUT_CATEGORY;
	ui_items = "Auto\0Linear (SDR)\0sRGB (SDR)\0Gamma 2.2 (SDR)\0BT.1886 (SDR)\0HDR10 (HDR)\0scRGB (HDR)\0";
	ui_label = "Input Transfer";
	ui_tooltip = "Auto detects HDR10 or scRGB from the color space reported to ReShade and uses sRGB for SDR or unknown input. Gamma 2.2 is for properly encoded SDR games. BT.1886 uses gamma 2.4 and is for video content or a very small selection of games.";
> = INPUT_AUTO;

uniform float INPUT_SCALING_NITS <
	ui_type = "slider";
	ui_category = RENOFX_UI_INPUT_CATEGORY;
	ui_min = 1.0;
	ui_max = 1000.0;
	ui_step = 1.0;
	ui_units = " nits";
	ui_label = "Input Scaling";
	ui_tooltip = "For HDR10 and scRGB input. This should match the brightness scaling used by the game. This setting does not affect SDR input.";
> = 100.0;

uniform float MAX_INPUT_WHITE_NITS <
	ui_type = "slider";
	ui_category = RENOFX_UI_INPUT_CATEGORY;
	ui_min = 100.0;
	ui_max = 10000.0;
	ui_step = 1.0;
	ui_units = " nits";
	ui_label = "Input Peak Nits";
	ui_tooltip = "Set to the peak brightness of the input image. This is used to adjust behavior for highlight saturation, blowout, and tone mapping.\nKeep at 100 nits for SDR input, unless upgrades unclamp the image before inverse tone mapping is applied.";
> = 100.0;

uniform uint OUTPUT_TRANSFER <
	ui_type = "combo";
	ui_category = RENOFX_UI_OUTPUT_CATEGORY;
	ui_items = "Auto\0Linear (SDR)\0sRGB (SDR)\0Gamma 2.2 (SDR)\0BT.1886 (SDR)\0HDR10 (BT.2020 PQ)\0scRGB (BT.709 Linear)\0";
	ui_label = "Output Transfer";
	ui_tooltip = "Auto detects the display mode reported to ReShade. Linear passes SDR output through without transfer encoding. Gamma 2.2 is for properly encoded SDR games. BT.1886 uses gamma 2.4 and is for video content or a very small selection of games.";
> = OUTPUT_AUTO;

uniform float GAME_BRIGHTNESS_NITS <
	ui_type = "slider";
	ui_category = RENOFX_UI_OUTPUT_CATEGORY;
	ui_min = 1.0;
	ui_max = 500.0;
	ui_step = 1.0;
	ui_units = " nits";
	ui_label = "Game Brightness";
	ui_tooltip = "Sets scene reference white for HDR10 and scRGB output. In split mode this scales the game independently from the UI. This setting does not affect SDR output.";
> = 100.0;

uniform float TONEMAP_PEAK_NITS <
	ui_type = "slider";
	ui_category = RENOFX_UI_OUTPUT_CATEGORY;
	ui_min = 100.0;
	ui_max = 10000.0;
	ui_step = 1.0;
	ui_units = " nits";
	ui_label = "Output Peak Nits";
	ui_tooltip = "Sets the brightest value the forward tone mapper aims to preserve. Match this roughly to your display's peak brightness.\nThis setting does not apply in SDR.";
> = 1000.0;

uniform uint GAMMA_CORRECTION <
	ui_type = "combo";
	ui_category = RENOFX_UI_OUTPUT_CATEGORY;
	ui_items = "Off\0Gamma 2.2\0BT.1886\0";
	ui_label = "SDR EOTF Emulation";
	ui_tooltip = "Emulates an SDR display EOTF for HDR output. Gamma 2.2 is for properly encoded SDR games. BT.1886 uses gamma 2.4 and is for video content or a very small selection of games. This setting is skipped for SDR output and when Input Transfer is Gamma 2.2 or BT.1886.\nIf you're using this on a native HDR game and it already uses the correct gamma, set this off.";
> = GAMMA_CORRECTION_22;

uniform uint SHOW_PEAK_BRIGHTNESS <
	ui_type = "combo";
	ui_category = RENOFX_UI_OUTPUT_CATEGORY;
	ui_items = "Off\0On\0";
	ui_label = "Show Estimated Peak";
	ui_tooltip = "Shows the estimated output brightness of Max Input White after inverse tone mapping and brightness grading. The estimate does not include APL limiting.";
> = 0;
#else
// SDR mode has no transfer/input/output controls: lock those paths to the
// standard SDR reference and sRGB transfers.
	#define INPUT_TRANSFER INPUT_SRGB
	#define INPUT_SCALING_NITS 100.0
	#define MAX_INPUT_WHITE_NITS 100.0
	#define OUTPUT_TRANSFER OUTPUT_SRGB
	#define GAME_BRIGHTNESS_NITS 100.0
	#define TONEMAP_PEAK_NITS 100.0
	#define GAMMA_CORRECTION GAMMA_CORRECTION_OFF
	#define SHOW_PEAK_BRIGHTNESS 0
#endif

uniform bool SEPARATE_SCENE_UI_SCALING <
	ui_type = "checkbox";
	ui_category = "RenoDX Pipeline Insert";
	ui_label = "Use RenoDX Pipeline Insert";
	ui_tooltip = "Requires renodx-upgrade.addon. This will allow you to insert the first pass before the UI renders, and finalize with the final output pass. This enables control of the image before the UI, as well as separate UI scaling.";
> = false;

#if RENOFX_ACTIVE_MENU_MODE == RENOFX_MENU_MODE_HDR
uniform float UI_BRIGHTNESS_NITS <
	ui_type = "slider";
	ui_category = "RenoDX Pipeline Insert";
	ui_min = 1.0;
	ui_max = 500.0;
	ui_step = 1.0;
	ui_units = " nits";
	ui_label = "UI Brightness";
	ui_tooltip = "Sets graphics/UI reference white for HDR10 and scRGB output when Separate Scene/UI Scaling is enabled. This setting does not affect sRGB output.";
> = 100.0;
#else
	#define UI_BRIGHTNESS_NITS 100.0
#endif

uniform uint PIPELINE_DEBUG_VIEW <
	ui_type = "combo";
	ui_category = "RenoDX Pipeline Insert";
	ui_items = "Off\0Swapchain Image\0Split Intermediate\0";
	ui_label = "Debug View";
	ui_tooltip = "Displays the final game swapchain image or RenoFX's decoded RGBA16F scene handoff before UI compositing.";
> = PIPELINE_DEBUG_OFF;

#if RENOFX_ACTIVE_MENU_MODE == RENOFX_MENU_MODE_HDR
uniform float HDR_BOOST <
	ui_type = "slider";
	ui_category = RENOFX_UI_BOOST_CATEGORY;
	ui_min = 1.0;
	ui_max = 10.0;
	ui_step = 0.1;
	ui_units = "x";
	ui_label = "HDR Boost";
	ui_tooltip = "Sets relative peak output for reference-white input at full availability: 1x is unchanged, 2x is double, up to 10x. HAnS and the APL limiter may reduce local boost. Start and Ramp Intensity shape the smooth rise.";
> = 1.0;

uniform float HDR_BOOST_START <
	ui_type = "slider";
	ui_category = RENOFX_UI_BOOST_CATEGORY;
	ui_min = 0.001;
	ui_max = 0.99;
	ui_step = 0.001;
	ui_label = "HDR Boost Start";
	ui_tooltip = "Sets where HDR Boost begins increasing brightness. Lower values affect more of the image; higher values limit the boost to brighter areas.";
> = 0.150;

uniform float HDR_BOOST_RAMP_INTENSITY <
	ui_type = "slider";
	ui_category = RENOFX_UI_BOOST_CATEGORY;
	ui_min = 0.25;
	ui_max = 4.0;
	ui_step = 0.05;
	ui_label = "Ramp Intensity";
	ui_tooltip = "Shapes the smooth C-infinity rise toward the selected peak. Higher values raise highlights earlier; lower values concentrate the increase nearer reference white.";
> = 1.0;

uniform float HDR_BOOST_GAMUT_EXPANSION <
	ui_type = "slider";
	ui_category = RENOFX_UI_BOOST_CATEGORY;
	ui_min = 0.0;
	ui_max = 100.0;
	ui_step = 1.0;
	ui_label = "Gamut Expansion";
	ui_tooltip = "Controls how much color expansion HDR Boost adds while preserving its brightness. Zero preserves the source color balance; 100 uses the full result from the selected working space.";
> = 50.0;

uniform uint HDR_BOOST_APL_LIMITER <
	ui_type = "combo";
	ui_category = RENOFX_UI_BOOST_CATEGORY;
	ui_items = "Off\0On\0";
	ui_label = "APL Limiter";
	ui_tooltip = "Lowers inverse tone mapping based on the average luminance of the full scene. This prevents very bright scenes from becoming too bright. It is bypassed while HAnS Highlight Analysis is active for SDR input.";
> = 1;

uniform uint HANS_MODE <
	ui_type = "combo";
	ui_category = "Highlight Analysis";
	ui_items = "Off\0Auto (SDR Input)\0";
	ui_label = "Highlight Analysis";
	ui_tooltip = "Controls per-pixel HDR Boost using the HAnS highlight detector. Auto analyzes SDR input and bypasses native HDR. Active HAnS bypasses the global APL limiter.";
> = HANS_MODE_OFF;

uniform float HANS_SIZE <
	ui_type = "slider";
	ui_category = "Highlight Analysis";
	ui_min = 2.0;
	ui_max = 24.0;
	ui_step = 2.0;
	ui_units = " px radius";
	ui_label = "Highlight Size";
	ui_tooltip = "Sets the source-image radius used by HAnS. Smaller values select small highlights; larger values also admit broader highlights.";
> = 24.0;

uniform float HANS_LOCAL_CONTRAST_THRESHOLD <
	ui_type = "slider";
	ui_category = "Highlight Analysis";
	ui_min = 0.0;
	ui_max = 0.5;
	ui_step = 0.01;
	ui_label = "Local Contrast Threshold";
	ui_tooltip = "Sets how strongly a candidate must stand above its surroundings. The HAnS paper commonly uses 0.2 or 0.3 for normalized LDR input.";
> = 0.25;

uniform float HANS_STRENGTH <
	ui_type = "slider";
	ui_category = "Highlight Analysis";
	ui_min = 0.0;
	ui_max = 100.0;
	ui_step = 1.0;
	ui_label = "Analysis Strength";
	ui_tooltip = "Blends between unrestricted HDR Boost and HAnS per-pixel control.";
> = 100.0;

uniform float HANS_FLOOR <
	ui_type = "slider";
	ui_category = "Highlight Analysis";
	ui_min = 0.0;
	ui_max = 100.0;
	ui_step = 1.0;
	ui_label = "Non-Highlight Boost";
	ui_tooltip = "Sets minimum HDR Boost availability for pixels HAnS does not identify as highlights.";
> = 20.0;

uniform float HANS_RESPONSE_GAMMA <
	ui_type = "slider";
	ui_category = "Highlight Analysis";
	ui_min = 0.1;
	ui_max = 4.0;
	ui_step = 0.1;
	ui_label = "Map Response";
	ui_tooltip = "Shapes the HAnS confidence map. Lower values admit weaker detections; higher values prioritize stronger highlights.";
> = 1.0;

uniform uint HANS_DEBUG_VIEW <
	ui_type = "combo";
	ui_category = "Highlight Analysis";
	ui_items = "Off\0Input Features\0Moving Average\0Dilated Average\0Local Contrast\0Feature Maps\0Fused Map\0Final Availability\0";
	ui_label = "Debug View";
	ui_tooltip = "Displays intermediate HAnS data. RGB views contain the selected analysis space's minimum component, luminance, and maximum component respectively.";
> = 0;
#else
	#define HDR_BOOST 1.0
	#define HDR_BOOST_START 0.100
	#define HDR_BOOST_RAMP_INTENSITY 1.0
	#define HDR_BOOST_GAMUT_EXPANSION 0.0
	#define HDR_BOOST_APL_LIMITER 0
	#define HANS_MODE HANS_MODE_OFF
	#define HANS_SIZE 24.0
	#define HANS_LOCAL_CONTRAST_THRESHOLD 0.25
	#define HANS_STRENGTH 0.0
	#define HANS_FLOOR 0.0
	#define HANS_RESPONSE_GAMMA 1.0
	#define HANS_DEBUG_VIEW 0
#endif

uniform float HIGHLIGHTS <
	ui_type = "slider";
	ui_category = RENOFX_UI_COLOR_CATEGORY;
	ui_min = 0.0;
	ui_max = 100.0;
	ui_step = 1.0;
	ui_label = "Highlights";
	ui_tooltip = "Shapes tonal values above the mid-gray anchor with the C-infinity curve. 50 is neutral; lower values darken highlights and higher values lift them.";
> = 50.0;

uniform float HIGHLIGHT_CONTRAST <
	ui_type = "slider";
	ui_category = RENOFX_UI_COLOR_CATEGORY;
	ui_min = 0.0;
	ui_max = 100.0;
	ui_step = 1.0;
	ui_label = "Highlight Contrast";
	ui_tooltip = "Adjusts broad contrast above the mid-gray anchor. 50 is neutral; lower values soften highlight contrast and higher values increase it.";
> = 50.0;

uniform float CONTRAST <
	ui_type = "slider";
	ui_category = RENOFX_UI_COLOR_CATEGORY;
	ui_min = 0.0;
	ui_max = 100.0;
	ui_step = 1.0;
	ui_label = "Contrast";
	ui_tooltip = "Applies anchored C-infinity contrast around the Mid Gray pivot. 50 is neutral; lower values reduce contrast and higher values increase it.";
> = 50.0;

uniform float SHADOW_CONTRAST <
	ui_type = "slider";
	ui_category = RENOFX_UI_COLOR_CATEGORY;
	ui_min = 0.0;
	ui_max = 100.0;
	ui_step = 1.0;
	ui_label = "Shadow Contrast";
	ui_tooltip = "Adjusts broad contrast below the mid-gray anchor. 50 is neutral; lower values soften shadow contrast and higher values increase it.";
> = 50.0;

uniform float SHADOWS <
	ui_type = "slider";
	ui_category = RENOFX_UI_COLOR_CATEGORY;
	ui_min = 0.0;
	ui_max = 100.0;
	ui_step = 1.0;
	ui_label = "Shadows";
	ui_tooltip = "Shapes tonal values below the mid-gray anchor with the C-infinity curve. 50 is neutral; lower values deepen shadows and higher values lift them.";
> = 50.0;

uniform float FLARE <
	ui_type = "slider";
	ui_category = RENOFX_UI_COLOR_CATEGORY;
	ui_min = 0.0;
	ui_max = 100.0;
	ui_step = 1.0;
	ui_label = "Flare";
	ui_tooltip = "Lifts very dark areas and softens their contrast, similar to light spreading through a camera lens. Zero turns it off.";
> = 0.0;

uniform float SATURATION <
	ui_type = "slider";
	ui_category = RENOFX_UI_COLOR_CATEGORY;
	ui_min = 0.0;
	ui_max = 100.0;
	ui_step = 1.0;
	ui_label = "Saturation";
	ui_tooltip = "Controls overall color strength. 50 is unchanged; lower values reduce color and higher values make colors more vivid.";
> = 50.0;

uniform float HIGHLIGHT_SATURATION <
	ui_type = "slider";
	ui_category = RENOFX_UI_COLOR_CATEGORY;
	ui_min = 0.0;
	ui_max = 100.0;
	ui_step = 1.0;
	ui_label = "Highlight Saturation";
	ui_tooltip = "Controls color strength in bright areas. 50 is unchanged; lower values make highlights whiter and higher values keep more color.";
> = 50.0;

uniform float BLOWOUT <
	ui_type = "slider";
	ui_category = RENOFX_UI_COLOR_CATEGORY;
	ui_min = 0.0;
	ui_max = 100.0;
	ui_step = 1.0;
	ui_label = "Blowout";
	ui_tooltip = "Fades color from the brightest areas to imitate an overexposed camera image. Zero turns it off.";
> = 0.0;

uniform float COLOR_TEMPERATURE_KELVIN <
	ui_type = "slider";
	ui_category = RENOFX_UI_COLOR_CATEGORY;
	ui_min = 4000.0;
	ui_max = 9300.0;
	ui_step = 100.0;
	ui_units = " K";
	ui_label = "White Point";
	ui_tooltip = "Adjusts the image white point using Bradford chromatic adaptation. 6500 K is neutral; higher values are cooler and lower values are warmer.";
> = 6500.0;

uniform float GRADING_MID_GRAY <
	ui_type = "slider";
	ui_category = RENOFX_UI_COLOR_CATEGORY;
	ui_min = 0.01;
	ui_max = 1.0;
	ui_step = 0.01;
	ui_label = "Mid Gray";
	ui_tooltip = "Sets where HDR Boost begins increasing brightness. Lower values affect more of the image; higher values limit the boost to brighter areas.";
> = 0.18;

uniform uint TONEMAP_ENABLED <
	ui_type = "combo";
	ui_category = RENOFX_UI_TONEMAP_CATEGORY;
	ui_items = "Off\0Neutwo\0C-infinity Roll-off\0";
	ui_label = "Tone Mapper";
	ui_tooltip = "Applies forward tone mapping after inverse tone mapping and grading. Neutwo or C-infinity Roll-off maps Max Input White to the selected output peak. For native HDR input, set Input Peak Nits to the game's peak brightness.";
> = 2;

uniform bool GAMUT_COMPRESSION_ENABLED <
	ui_type = "checkbox";
	ui_category = RENOFX_UI_TONEMAP_CATEGORY;
	ui_label = "Gamut Compression";
	ui_tooltip = "Compresses colors to the detected gamut target.";
> = true;

uniform uint HDR_BOOST_SPACE <
	ui_type = "combo";
	ui_category = RENOFX_UI_ADVANCED_CATEGORY;
	ui_items = "BT.709\0BT.2020\0AP1 (ACEScg)\0LMS (Stockman-Sharpe)\0Yf (Brightness)\0";
	ui_label = "Inverse Tone Mapping Working Space";
	ui_tooltip = "Changes how inverse tone mapping reacts to color. LMS is the recommended default. Yf changes brightness while preserving the original color balance.";
> = SPACE_LMS;

uniform uint GRADING_SPACE <
	ui_type = "combo";
	ui_category = RENOFX_UI_ADVANCED_CATEGORY;
	ui_items = "BT.709\0BT.2020\0AP1 (ACEScg)\0LMS (Stockman-Sharpe)\0Yf (Brightness)\0";
	ui_label = "Grading Working Space";
	ui_tooltip = "Changes how the brightness and color controls react. LMS is the recommended default. Yf adjusts brightness without shifting colors; color-only controls have no effect in that mode.";
> = SPACE_LMS;

uniform uint TONEMAP_SPACE <
	ui_type = "combo";
	ui_category = RENOFX_UI_ADVANCED_CATEGORY;
	ui_items = "BT.709\0BT.2020\0AP1 (ACEScg)\0LMS (Stockman-Sharpe)\0Yf (Brightness)\0Brightest Channel\0";
	ui_label = "Tone Map Working Space";
	ui_tooltip = "Changes how bright values are controlled. LMS is the recommended default. Yf preserves color balance. Brightest Channel protects the strongest channel and scales the others with it.";
> = SPACE_LMS;

uniform uint GAMMA_CORRECTION_WORKING_SPACE <
	ui_type = "combo";
	ui_category = RENOFX_UI_ADVANCED_CATEGORY;
	ui_items = "BT.709\0BT.2020\0AP1 (ACEScg)\0LMS (Stockman-Sharpe)\0Yf (Brightness)\0";
	ui_label = "Gamma Correction Working Space";
	ui_tooltip = "Select the working space used by gamma correction when enabled. BT.709 is the correct choice to emulate the screen's behavior, but other working spaces may be visually preferrable.";
> = SPACE_BT709;

uniform uint SATURATION_SPACE <
	ui_type = "combo";
	ui_category = RENOFX_UI_ADVANCED_CATEGORY;
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
// in red and the Bradford color-temperature adaptation in GBA. Texel 2 stores
// the inserted permutation's resolved game/intermediate transfer and scaling
// in RG. Blue indicates that the inserted target is RGBA16F, while alpha
// indicates authoritative presentation-target metadata. When both are zero,
// the normalized inserted target is treated as a final-output input: RenoFX
// clears it after preserving the scene in `SplitIntermediateTexture`, so later
// game UI can be composited with that HDR scene at presentation.
// Texel 3 provides a current-frame and matching-dimensions handshake so the
// final pass never consumes stale state or a differently sized handoff.
// Texel 4 caches normalized input peak and the C-infinity ramp value there.
texture2D FrameStateTexture {
	Width = 5;
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

// The normal final-output permutation publishes its authoritative transfer for
// the next inserted draw. Custom mid-frame permutations cannot inspect the
// final swapchain directly and retain the preceding frame-count uniform value.
texture2D OutputStateTexture {
	Width = 1;
	Height = 1;
	Format = RGBA32F;
};

sampler2D OutputStateSampler {
	Texture = OutputStateTexture;
	MinFilter = POINT;
	MagFilter = POINT;
	MipFilter = POINT;
	AddressU = CLAMP;
	AddressV = CLAMP;
};

// Split scene values must not pass through the normalized swapchain between
// RenoFX and RenoFXOutput. This texture is the authoritative adjacent-pass
// handoff and preserves extended sRGB and linear values above 1.0.
texture2D SplitIntermediateTexture {
	Width = BUFFER_WIDTH;
	Height = BUFFER_HEIGHT;
	Format = RGBA16F;
};

sampler2D SplitIntermediateSampler {
	Texture = SplitIntermediateTexture;
	MinFilter = POINT;
	MagFilter = POINT;
	MipFilter = POINT;
	AddressU = CLAMP;
	AddressV = CLAMP;
};

uint ResolveInputTransfer() {
	if (INPUT_TRANSFER != INPUT_AUTO) return INPUT_TRANSFER;

#if defined(BUFFER_COLOR_SPACE)
	if (BUFFER_COLOR_SPACE == COLOR_SPACE_SRGB) return INPUT_SRGB;
	if (BUFFER_COLOR_SPACE == COLOR_SPACE_SCRGB) return INPUT_SCRGB;
	if (BUFFER_COLOR_SPACE == COLOR_SPACE_HDR10_PQ) return INPUT_HDR10;
	// HLG is known but unsupported; treat it as the SDR sRGB fallback.
	if (BUFFER_COLOR_SPACE == COLOR_SPACE_HDR10_HLG) return INPUT_SRGB;
	// Custom insertion targets report unknown color-space metadata. Their
	// resource format does not identify the transfer used by the game.
	if (BUFFER_COLOR_SPACE == COLOR_SPACE_UNKNOWN) return INPUT_SRGB;
#elif defined(BUFFER_COLOR_FORMAT)
	if (BUFFER_COLOR_FORMAT == FORMAT_RGBA16_FLOAT) return INPUT_SCRGB;
	if (BUFFER_COLOR_FORMAT == FORMAT_RGB10A2) return INPUT_HDR10;
#elif defined(BUFFER_COLOR_BIT_DEPTH)
	if (BUFFER_COLOR_BIT_DEPTH == 16) return INPUT_SCRGB;
	if (BUFFER_COLOR_BIT_DEPTH == 10) return INPUT_HDR10;
#endif

	// Unknown metadata and ordinary SDR formats use sRGB, never linear SDR.
	return INPUT_SRGB;
}

float ResolveInputScalingNits(uint input_transfer) {
	if (input_transfer == INPUT_HDR10 || input_transfer == INPUT_SCRGB) {
		return max(INPUT_SCALING_NITS, 1.0f);
	}
	return 100.0f;
}

float ResolveInputScalingNits() {
	return ResolveInputScalingNits(ResolveInputTransfer());
}

float3 DecodeInput(float3 input_color) {
	uint input_transfer = ResolveInputTransfer();
	if (input_transfer == INPUT_SRGB) {
		return renodx::color::SRGBDecode(input_color);
	}
	if (input_transfer == INPUT_GAMMA22) {
		return renodx::color::SignPow(input_color, 2.2f);
	}
	if (input_transfer == INPUT_BT1886) {
		return renodx::color::SignPow(input_color, 2.4f);
	}
	if (input_transfer == INPUT_HDR10) {
		return renodx::color::DecodeHDR10(
				input_color,
				ResolveInputScalingNits(),
				false);
	}
	if (input_transfer == INPUT_SCRGB) {
		return renodx::color::DecodeScRGB(input_color, ResolveInputScalingNits());
	}
	return input_color;
}

float3 DecodeIntermediate(
		float3 input_color,
		uint intermediate_transfer,
		float intermediate_scaling_nits) {
	if (intermediate_transfer == INPUT_SRGB) {
		return renodx::color::SRGBDecode(input_color);
	}
	if (intermediate_transfer == INPUT_GAMMA22) {
		return renodx::color::SignPow(input_color, 2.2f);
	}
	if (intermediate_transfer == INPUT_BT1886) {
		return renodx::color::SignPow(input_color, 2.4f);
	}
	if (intermediate_transfer == INPUT_HDR10) {
		// Unlike physical PQ input, the split pass may contain signed BT.2020
		// components in a floating-point target. Keep them until final gamut
		// compression rather than clipping them at the intermediate boundary.
		return renodx::color::DecodeHDR10(input_color, intermediate_scaling_nits, true);
	}
	if (intermediate_transfer == INPUT_SCRGB) {
		return renodx::color::DecodeScRGB(input_color, intermediate_scaling_nits);
	}
	return input_color;
}

float3 EncodeIntermediate(
		float3 bt709,
		uint intermediate_transfer,
		float intermediate_scaling_nits) {
	if (intermediate_transfer == INPUT_SRGB) {
		return renodx::color::SRGBEncode(bt709);
	}
	if (intermediate_transfer == INPUT_GAMMA22) {
		return renodx::color::SignPow(bt709, 1.0f / 2.2f);
	}
	if (intermediate_transfer == INPUT_BT1886) {
		return renodx::color::SignPow(bt709, 1.0f / 2.4f);
	}
	if (intermediate_transfer == INPUT_HDR10) {
		return renodx::color::EncodeHDR10(bt709, intermediate_scaling_nits, true);
	}
	if (intermediate_transfer == INPUT_SCRGB) {
		return renodx::color::EncodeScRGB(bt709, intermediate_scaling_nits);
	}
	return bt709;
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

bool IsSDROutputTransfer(uint output_transfer) {
	return output_transfer == OUTPUT_LINEAR
			|| output_transfer == OUTPUT_SRGB
			|| output_transfer == OUTPUT_GAMMA22
			|| output_transfer == OUTPUT_BT1886;
}

bool UsesSDREotfEmulation(uint output_transfer) {
	uint input_transfer = ResolveInputTransfer();
	return !IsSDROutputTransfer(output_transfer)
			&& input_transfer != INPUT_GAMMA22
			&& input_transfer != INPUT_BT1886
			&& GAMMA_CORRECTION != GAMMA_CORRECTION_OFF;
}

uint ResolveSceneOutputTransfer() {
	if (OUTPUT_TRANSFER != OUTPUT_AUTO) return ResolveOutputTransfer();

#if defined(BUFFER_COLOR_SPACE)
	// A normal ReShade permutation has authoritative final-target metadata.
	if (BUFFER_COLOR_SPACE != COLOR_SPACE_UNKNOWN) return ResolveOutputTransfer();
#endif

	// An inserted permutation cannot observe the final swapchain directly. The
	// final technique publishes the authoritative transfer for the next frame.
	if (SEPARATE_SCENE_UI_SCALING) {
		float4 output_state = tex2Dlod(
				OutputStateSampler,
				float4(0.5f, 0.5f, 0.0f, 0.0f));
		uint output_state_frame = uint(output_state.g + 0.5f)
				| (uint(output_state.b + 0.5f) << 16u);
		uint previous_frame = FRAME_COUNT == 0u
				? 0xfffffffeu
				: FRAME_COUNT - 1u;
		// The final technique publishes this at the previous present boundary.
		// The inserted technique consumes it before the current present updates
		// ReShade's frame counter.
		if (output_state.a >= 0.5f
				&& (output_state_frame == FRAME_COUNT
						|| output_state_frame == previous_frame)) {
			return uint(output_state.r + 0.5f);
		}
		return OUTPUT_HDR10;
	}
	return ResolveOutputTransfer();
}

bool HasPresentationTargetMetadata() {
#if defined(BUFFER_COLOR_SPACE)
	return BUFFER_COLOR_SPACE != COLOR_SPACE_UNKNOWN;
#else
	return false;
#endif
}

bool IsFloatRenderTarget() {
#if defined(BUFFER_COLOR_FORMAT)
	return BUFFER_COLOR_FORMAT == FORMAT_RGBA16_FLOAT;
#elif defined(BUFFER_COLOR_BIT_DEPTH)
	return BUFFER_COLOR_BIT_DEPTH == 16;
#else
	return false;
#endif
}

// HAnS is included after input decoding and the working-space helpers it
// consumes; its guarded helper implementation is always emitted here.
#include "renofx__includes/RenoFXHAnS.fxh"

float3 ApplyHDRBoost(
		float3 working,
		uint working_space,
		float boost_availability,
		float peak_ramp) {
	if (HDR_BOOST <= 1.0f || boost_availability <= 0.0f) return working;
	float3 boosted = renodx::inverse_tonemap::ApplyCInfinityInverseTonemapWorkingSpace(
			working,
			working_space,
			HDR_BOOST,
			peak_ramp,
			HDR_BOOST_START,
			HDR_BOOST_RAMP_INTENSITY,
			boost_availability);
	return renodx::color::RestoreWorkingHue(working, boosted, working_space);
}

bool IsBrightnessGradingNeutral() {
	return HIGHLIGHTS == 50.0f
			&& SHADOWS == 50.0f
			&& CONTRAST == 50.0f
			&& HIGHLIGHT_CONTRAST == 50.0f
			&& SHADOW_CONTRAST == 50.0f
			&& FLARE == 0.0f;
}

float3 ApplyBrightnessGradingShaping(float3 working, uint working_space) {
	if (IsBrightnessGradingNeutral()) return working;

	return renodx::color::ApplyAnchoredCInfinityGrading(
			working,
			working_space,
			GRADING_MID_GRAY,
			CONTRAST * 0.02f,
			FLARE * 0.0005f,
			HIGHLIGHT_CONTRAST * 0.02f,
			SHADOW_CONTRAST * 0.02f,
			HIGHLIGHTS * 0.02f,
			SHADOWS * 0.02f);
}

float3 ApplyBrightnessGrading(float3 working, uint working_space) {
	if (IsBrightnessGradingNeutral()) return working;
	float3 graded = ApplyBrightnessGradingShaping(working, working_space);
	return renodx::color::RestoreWorkingHue(working, graded, working_space);
}

float3 ApplyGrading(
		float3 working,
		uint working_space,
		float3 peak_white) {
	float3 chroma_graded = renodx::color::ApplyColorGrading(
			working,
			working_space,
			peak_white,
			GRADING_MID_GRAY,
			ResolveInputScalingNits(),
			SATURATION * 0.02f,
			HIGHLIGHT_SATURATION * 0.02f,
			BLOWOUT * 0.01f,
			true,
			SATURATION_SPACE);
	return ApplyBrightnessGrading(chroma_graded, working_space);
}

float3 ApplyCombinedBrightnessShaping(
		float3 working,
		uint working_space,
		float boost_availability,
		float peak_ramp) {
	bool boost_active = HDR_BOOST > 1.0f && boost_availability > 0.0f;
	bool grading_active = !IsBrightnessGradingNeutral();
	if (!boost_active && !grading_active) return working;

	float3 source = working;
	if (boost_active) {
		working = renodx::inverse_tonemap::ApplyCInfinityInverseTonemapWorkingSpace(
				working,
				working_space,
				HDR_BOOST,
				peak_ramp,
				HDR_BOOST_START,
				HDR_BOOST_RAMP_INTENSITY,
				boost_availability);
	}
	if (grading_active) {
		working = ApplyBrightnessGradingShaping(working, working_space);
	}
	return renodx::color::RestoreWorkingHue(source, working, working_space);
}

float3 ApplyGradingYf(float3 bt709, float3 peak_white_bt709) {
	float3 graded = bt709;
	float saturation = SATURATION * 0.02f;
	if (saturation != 1.0f) {
		graded = renodx::color::SaturateOKLab(graded, saturation);
	}
	graded = renodx::color::ApplyColorGrading(
			graded,
			SPACE_YF,
			peak_white_bt709,
			GRADING_MID_GRAY,
			ResolveInputScalingNits(),
			SATURATION * 0.02f,
			HIGHLIGHT_SATURATION * 0.02f,
			BLOWOUT * 0.01f,
			false,
			SATURATION_SPACE);
	return renodx::color::ApplyCInfinityGradingYf(
			graded,
			GRADING_MID_GRAY,
			CONTRAST * 0.02f,
			FLARE * 0.0005f,
			HIGHLIGHT_CONTRAST * 0.02f,
			SHADOW_CONTRAST * 0.02f,
			HIGHLIGHTS * 0.02f,
			SHADOWS * 0.02f);
}

float ResolveNormalizedInputPeak() {
	return max(MAX_INPUT_WHITE_NITS / ResolveInputScalingNits(), 0.01f);
}

float3 EstimatePeakWhiteBT709(
		float boost_availability,
		float input_peak,
		float peak_ramp) {
	float3 peak_white = input_peak.xxx;
	if (HDR_BOOST_GAMUT_EXPANSION >= 100.0f
			&& HDR_BOOST_SPACE == GRADING_SPACE
			&& GRADING_SPACE != SPACE_YF) {
		float3 working = renodx::color::ToWorking(peak_white, GRADING_SPACE);
		working = ApplyCombinedBrightnessShaping(
				working,
				GRADING_SPACE,
				boost_availability,
				peak_ramp);
		return renodx::color::FromWorking(working, GRADING_SPACE);
	}

	if (HDR_BOOST_SPACE == SPACE_YF) {
		peak_white = renodx::inverse_tonemap::ApplyCInfinityInverseTonemapYf(
				peak_white,
				HDR_BOOST,
				peak_ramp,
				HDR_BOOST_START,
				HDR_BOOST_RAMP_INTENSITY,
				boost_availability);
	} else {
		float3 working = renodx::color::ToWorking(peak_white, HDR_BOOST_SPACE);
		working = ApplyHDRBoost(working, HDR_BOOST_SPACE, boost_availability, peak_ramp);
		peak_white = renodx::color::FromWorking(working, HDR_BOOST_SPACE);
	}

	if (GRADING_SPACE == SPACE_YF) {
		peak_white = renodx::color::ApplyColorGrading(
				peak_white,
				SPACE_YF,
				peak_white,
				GRADING_MID_GRAY,
				ResolveInputScalingNits(),
				SATURATION * 0.02f,
				HIGHLIGHT_SATURATION * 0.02f,
				BLOWOUT * 0.01f,
				false,
				SATURATION_SPACE);
		return renodx::color::ApplyCInfinityGradingYf(
				peak_white,
				GRADING_MID_GRAY,
				CONTRAST * 0.02f,
				FLARE * 0.0005f,
				HIGHLIGHT_CONTRAST * 0.02f,
				SHADOW_CONTRAST * 0.02f,
				HIGHLIGHTS * 0.02f,
				SHADOWS * 0.02f);
	}

	float3 working = renodx::color::ToWorking(peak_white, GRADING_SPACE);
	working = ApplyBrightnessGrading(working, GRADING_SPACE);
	return renodx::color::FromWorking(working, GRADING_SPACE);
}

float3 ApplyControls(
		float3 bt709,
		float boost_availability,
		float3 estimated_peak_white_working,
		float peak_ramp) {
	// Apply pre-tonal chroma controls, then keep compatible brightness
	// operations in one working-space chain and restore hue once.
	if (HDR_BOOST_GAMUT_EXPANSION >= 100.0f
			&& HDR_BOOST_SPACE == GRADING_SPACE
			&& GRADING_SPACE != SPACE_YF
			&& !HAnSShouldAnalyze()) {
		float3 working = renodx::color::ToWorking(bt709, GRADING_SPACE);
		working = renodx::color::ApplyColorGrading(
				working,
				GRADING_SPACE,
				estimated_peak_white_working,
				GRADING_MID_GRAY,
				ResolveInputScalingNits(),
				SATURATION * 0.02f,
				HIGHLIGHT_SATURATION * 0.02f,
				BLOWOUT * 0.01f,
				true,
				SATURATION_SPACE);
		working = ApplyCombinedBrightnessShaping(
				working,
				GRADING_SPACE,
				boost_availability,
				peak_ramp);
		return renodx::color::FromWorking(working, GRADING_SPACE);
	}

	float3 controlled = bt709;
	if (HDR_BOOST_SPACE == SPACE_YF) {
		controlled = renodx::inverse_tonemap::ApplyCInfinityInverseTonemapYf(
				controlled,
				HDR_BOOST,
				peak_ramp,
				HDR_BOOST_START,
				HDR_BOOST_RAMP_INTENSITY,
				boost_availability);
	} else {
		float3 working = renodx::color::ToWorking(controlled, HDR_BOOST_SPACE);
		working = ApplyHDRBoost(working, HDR_BOOST_SPACE, boost_availability, peak_ramp);
		controlled = renodx::color::FromWorking(working, HDR_BOOST_SPACE);
	}

	controlled = renodx::inverse_tonemap::BlendHDRBoostGamutExpansion(
			bt709,
			controlled,
			HDR_BOOST_GAMUT_EXPANSION * 0.01f);

	if (GRADING_SPACE == SPACE_YF) {
		controlled = ApplyGradingYf(controlled, estimated_peak_white_working);
	} else {
		float3 working = renodx::color::ToWorking(controlled, GRADING_SPACE);
		working = ApplyGrading(
				working,
				GRADING_SPACE,
				estimated_peak_white_working);
		controlled = renodx::color::FromWorking(working, GRADING_SPACE);
	}
	return controlled;
}

float WhiteClipFromGradingPeak(float3 peak_white) {
	return renodx::tonemap::WhiteClipFromPeak(
			peak_white,
			renodx::color::WorkingWhite(GRADING_SPACE),
			GRADING_SPACE == SPACE_YF);
}

float3 ApplyNeutwo(float3 bt709, float white_clip) {
	uint output_transfer = ResolveSceneOutputTransfer();
	float output_peak = 1.0f;
	if (!IsSDROutputTransfer(output_transfer)) {
		float game_nits = max(GAME_BRIGHTNESS_NITS, 1.0f);
		output_peak = max(TONEMAP_PEAK_NITS / game_nits, 1.0f);
	}
	float peak = output_peak;
	if (UsesSDREotfEmulation(output_transfer)) {
		if (GAMMA_CORRECTION == GAMMA_CORRECTION_24) {
			peak = renodx::color::SRGBDecode(renodx::color::SignPow(output_peak, 1.0f / 2.4f));
		} else {
			peak = renodx::color::SRGBDecode(renodx::color::SignPow(output_peak, 1.0f / 2.2f));
		}
	}
	if (white_clip <= peak) return bt709;
	float clip = max(white_clip, peak);
	return renodx::tonemap::ApplyNeutwoWorkingSpace(
			bt709,
			peak,
			clip,
			TONEMAP_SPACE);
}

float3 ApplyCInfinityRollOff(float3 bt709, float white_clip) {
	uint output_transfer = ResolveSceneOutputTransfer();
	float peak = 1.0f;
	if (!IsSDROutputTransfer(output_transfer)) {
		float game_nits = max(GAME_BRIGHTNESS_NITS, 1.0f);
		peak = max(TONEMAP_PEAK_NITS / game_nits, 1.0f);
	}
	if (UsesSDREotfEmulation(output_transfer)) {
		if (GAMMA_CORRECTION == GAMMA_CORRECTION_24) {
			peak = renodx::color::SRGBDecode(renodx::color::SignPow(peak, 1.0f / 2.4f));
		} else {
			peak = renodx::color::SRGBDecode(renodx::color::SignPow(peak, 1.0f / 2.2f));
		}
	}
	if (white_clip <= peak) return bt709;

	float clip_value = max(white_clip, peak);
	return renodx::tonemap::ApplyCInfinityRollOffWorkingSpace(
			bt709,
			peak,
			clip_value,
			TONEMAP_SPACE,
			0.18f,
			1.5f);
}

float3 ApplyTonemap(float3 bt709, float white_clip) {
	if (TONEMAP_ENABLED == 1) {
		return ApplyNeutwo(bt709, white_clip);
	}
	if (TONEMAP_ENABLED == 2) {
		return ApplyCInfinityRollOff(bt709, white_clip);
	}
	return bt709;
}

float3 ApplyGamutCompression(float3 bt709) {
	if (!GAMUT_COMPRESSION_ENABLED) return bt709;

#if RENOFX_ACTIVE_MENU_MODE == RENOFX_MENU_MODE_HDR
	float3 bt2020 = renodx::color::BT709ToBT2020(bt709);
	bt2020 = renodx::color::CompressGamutBT2020(bt2020, 1.0f);
	// Keep the toolkit's output pipeline in BT.709; the selected gamut only
	// changes the compression boundary, not the working domain downstream.
	return renodx::color::BT2020ToBT709(bt2020);
#else
	return renodx::color::CompressGamutBT709(bt709, 1.0f);
#endif
}

float3 ApplyGammaCorrection(float3 bt709) {
	float gamma = GAMMA_CORRECTION == GAMMA_CORRECTION_24 ? 2.4f : 2.2f;
	return renodx::color::ApplyEotfGamma(
			bt709,
			gamma,
			GAMMA_CORRECTION_WORKING_SPACE);
}

float3 RemoveGammaCorrection(float3 bt709) {
	float inverse_gamma = GAMMA_CORRECTION == GAMMA_CORRECTION_24
			? 1.0f / 2.4f
			: 1.0f / 2.2f;
	return renodx::color::RemoveEotfGamma(
			bt709,
			inverse_gamma,
			GAMMA_CORRECTION_WORKING_SPACE);
}

float EstimatePeakNits(float input_peak, float peak_ramp) {
	// Evaluate the configured maximum input white at full HDR Boost availability
	// so the estimate remains independent of scene-dependent APL limiting.
	float3 probe = EstimatePeakWhiteBT709(1.0f, input_peak, peak_ramp);
	float reference_white_nits = IsSDROutputTransfer(ResolveSceneOutputTransfer())
			? 100.0f
			: GAME_BRIGHTNESS_NITS;
	return max(probe.r, max(probe.g, probe.b)) * reference_white_nits;
}

float3 PrepareOutputLinear(
		float3 bt709,
		float white_clip,
		float3 color_temperature_adaptation,
		bool apply_gamma_correction) {
	uint output_transfer = ResolveSceneOutputTransfer();
	bt709 = ApplyTonemap(bt709, white_clip);

	if (apply_gamma_correction && UsesSDREotfEmulation(output_transfer)) {
		bt709 = ApplyGammaCorrection(bt709);
	}
	bt709 = renodx::color::ApplyBradfordAdaptation(bt709, color_temperature_adaptation);

	return bt709;
}

float3 EncodePresentation(
		float3 bt709,
		float reference_white_nits,
		uint output_transfer) {
	bt709 = ApplyGamutCompression(bt709);

	if (output_transfer == OUTPUT_LINEAR) {
		return bt709;
	}
	if (output_transfer == OUTPUT_SRGB) {
		return renodx::color::SRGBEncode(bt709);
	}
	if (output_transfer == OUTPUT_GAMMA22) {
		return renodx::color::SignPow(bt709, 1.0f / 2.2f);
	}
	if (output_transfer == OUTPUT_BT1886) {
		return renodx::color::SignPow(bt709, 1.0f / 2.4f);
	}

	float scaling_nits = max(reference_white_nits, 1.0f);
	if (output_transfer == OUTPUT_HDR10) {
		return renodx::color::EncodeHDR10(bt709, scaling_nits, false);
	}

	return renodx::color::EncodeScRGB(bt709, scaling_nits);
}

float3 EncodePresentation(float3 bt709, float reference_white_nits) {
	return EncodePresentation(
			bt709,
			reference_white_nits,
			ResolveOutputTransfer());
}

float3 EncodeOutput(
		float3 bt709,
		float white_clip,
		float3 color_temperature_adaptation) {
	bt709 = PrepareOutputLinear(
			bt709,
			white_clip,
			color_temperature_adaptation,
			true);
	return EncodePresentation(bt709, GAME_BRIGHTNESS_NITS);
}

float4 MeasureAPL(
		float4 position : SV_Position,
		float2 texcoord : TexCoord) : SV_Target {
	// HAnS owns HDR Boost availability for supported SDR input. The global APL
	// limiter remains available whenever HAnS is disabled or bypassed for HDR.
	if (HDR_BOOST_APL_LIMITER == 0 || HDR_BOOST <= 1.0f || HAnSShouldAnalyze()) {
		return 0.0f.xxxx;
	}

	float3 input_bt709 = DecodeInput(tex2D(ReShade::BackBuffer, texcoord).rgb);
	float normalized_yf = max(renodx::color::YfFromBT709(input_bt709), 0.0f)
			/ max(renodx::color::YfWhite(), 1e-6f);
	return float4(saturate(normalized_yf), 0.0f, 0.0f, 1.0f);
}

float ComputeAPLHDRBoostAvailability() {
	if (HDR_BOOST_APL_LIMITER == 0
			|| HDR_BOOST <= 1.0f
			|| HAnSShouldAnalyze()) return 1.0f;

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
	if (position.x >= 4.0f) {
		float input_peak = ResolveNormalizedInputPeak();
		float peak_ramp = renodx::inverse_tonemap::CInfinityInverseTonemapPeakRamp(
				input_peak,
				HDR_BOOST_START,
				HDR_BOOST_RAMP_INTENSITY);
		return float4(input_peak, peak_ramp, 0.0f, 0.0f);
	}

	if (position.x >= 3.0f) {
		return float4(
				float(FRAME_COUNT & 0xffffu),
				float(FRAME_COUNT >> 16u),
				float(BUFFER_WIDTH),
				float(BUFFER_HEIGHT));
	}

	if (position.x >= 2.0f) {
		uint intermediate_transfer = ResolveInputTransfer();
		return float4(
				float(intermediate_transfer),
				ResolveInputScalingNits(intermediate_transfer),
				IsFloatRenderTarget() ? 1.0f : 0.0f,
				HasPresentationTargetMetadata() ? 1.0f : 0.0f);
	}

	if (position.x >= 1.0f) {
		float estimated_peak_nits = 0.0f;
		if (SHOW_PEAK_BRIGHTNESS != 0) {
			float input_peak = ResolveNormalizedInputPeak();
			float peak_ramp = renodx::inverse_tonemap::CInfinityInverseTonemapPeakRamp(
					input_peak,
					HDR_BOOST_START,
					HDR_BOOST_RAMP_INTENSITY);
			estimated_peak_nits = EstimatePeakNits(input_peak, peak_ramp);
		}
		float3 color_temperature_adaptation = renodx::color::BradfordAdaptationFromKelvin(
				COLOR_TEMPERATURE_KELVIN);
		return float4(estimated_peak_nits, color_temperature_adaptation);
	}

	float apl_boost_availability = ComputeAPLHDRBoostAvailability();
	float input_peak = ResolveNormalizedInputPeak();
	float peak_ramp = renodx::inverse_tonemap::CInfinityInverseTonemapPeakRamp(
			input_peak,
			HDR_BOOST_START,
			HDR_BOOST_RAMP_INTENSITY);
	float3 estimated_peak_white = EstimatePeakWhiteBT709(
			apl_boost_availability,
			input_peak,
			peak_ramp);
	float3 estimated_peak_white_working = GRADING_SPACE == SPACE_YF
			? estimated_peak_white
			: renodx::color::ToWorking(estimated_peak_white, GRADING_SPACE);
	return float4(estimated_peak_white_working, apl_boost_availability);
}

float4 CacheOutputState(
		float4 position : SV_Position,
		float2 texcoord : TexCoord) : SV_Target {
	return float4(
			float(ResolveOutputTransfer()),
			float(FRAME_COUNT & 0xffffu),
			float(FRAME_COUNT >> 16u),
			1.0f);
}

float3 EncodeOverlayNits(float nits, uint output_transfer) {
	float safe_nits = max(nits, 0.0f);
	if (output_transfer == OUTPUT_HDR10) {
		return renodx::color::PQEncode((safe_nits / 10000.0f).xxx);
	}
	if (output_transfer == OUTPUT_SCRGB) {
		return (safe_nits / 80.0f).xxx;
	}
	if (output_transfer == OUTPUT_LINEAR) {
		return saturate(safe_nits / 100.0f).xxx;
	}
	if (output_transfer == OUTPUT_GAMMA22) {
		return pow(saturate(safe_nits / 100.0f), 1.0f / 2.2f).xxx;
	}
	if (output_transfer == OUTPUT_BT1886) {
		return pow(saturate(safe_nits / 100.0f), 1.0f / 2.4f).xxx;
	}
	return renodx::color::SRGBEncode(saturate(safe_nits / 100.0f).xxx);
}

float3 EncodeOverlayNits(float nits) {
	return EncodeOverlayNits(nits, ResolveOutputTransfer());
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

float4 DrawPeakBrightness(
		float4 output,
		float2 pixel_position,
		uint output_transfer) {
	if (SHOW_PEAK_BRIGHTNESS == 0) return output;

	float scale = max(2.0f, floor(BUFFER_HEIGHT / 540.0f));
	float2 panel_min = float2(12.0f, 12.0f) * scale;
	float2 panel_max = panel_min + float2(122.0f, 17.0f) * scale;
	bool inside_panel = all(pixel_position >= panel_min)
			&& all(pixel_position <= panel_max);
	if (!inside_panel) return output;

	float peak_nits = tex2Dlod(
			FrameStateSampler,
			float4(3.0f / 10.0f, 0.5f, 0.0f, 0.0f)).r;
	float2 text_origin = panel_min + float2(7.0f, 5.0f) * scale;

	float text_nits = IsSDROutputTransfer(output_transfer)
			? 100.0f
			: max(
					100.0f,
					min(
							SEPARATE_SCENE_UI_SCALING
									? UI_BRIGHTNESS_NITS
									: GAME_BRIGHTNESS_NITS,
							203.0f));

	output.rgb = lerp(
			output.rgb,
			EncodeOverlayNits(0.0f, output_transfer),
			0.72f);

	float text_coverage = PeakTextCoverage(pixel_position, text_origin, scale, peak_nits);
	output.rgb = lerp(
			output.rgb,
			EncodeOverlayNits(text_nits, output_transfer),
			text_coverage);
	return output;
}

float4 DrawPeakBrightness(float4 output, float2 pixel_position) {
	return DrawPeakBrightness(
			output,
			pixel_position,
			ResolveOutputTransfer());
}

float4 Main(float4 position : SV_Position, float2 texcoord : TexCoord) : SV_Target {
	float4 input = tex2D(ReShade::BackBuffer, texcoord);
	float3 bt709 = DecodeInput(input.rgb);
	float4 frame_state = tex2Dlod(
			FrameStateSampler,
			float4(1.0f / 10.0f, 0.5f, 0.0f, 0.0f));
	float peak_ramp = tex2Dlod(
			FrameStateSampler,
			float4(9.0f / 10.0f, 0.5f, 0.0f, 0.0f)).g;
	float white_clip = WhiteClipFromGradingPeak(frame_state.rgb);
	float3 color_temperature_adaptation = 1.0f.xxx;
	if (abs(COLOR_TEMPERATURE_KELVIN - 6500.0f) >= 0.5f) {
		color_temperature_adaptation = tex2Dlod(
				FrameStateSampler,
				float4(3.0f / 10.0f, 0.5f, 0.0f, 0.0f)).gba;
	}
	float boost_availability = frame_state.a * HAnSLocalAvailability(texcoord);
	bt709 = ApplyControls(
			bt709,
			boost_availability,
			frame_state.rgb,
			peak_ramp);
	if (HANS_DEBUG_VIEW != 0) {
		// HAnS debug values are normalized display-referred signals. Decode them
		// into the pipeline representation before the ordinary output path.
		bt709 = renodx::color::SRGBDecode(saturate(HAnSDebugColor(
				texcoord,
				boost_availability)));
	}
	if (SEPARATE_SCENE_UI_SCALING) {
		bt709 = PrepareOutputLinear(
				bt709,
				white_clip,
				color_temperature_adaptation,
				false);
		uint intermediate_transfer = ResolveInputTransfer();
		float intermediate_scaling_nits = ResolveInputScalingNits(
				intermediate_transfer);
		if (!IsSDROutputTransfer(ResolveSceneOutputTransfer())) {
			float scene_to_ui_scale = max(GAME_BRIGHTNESS_NITS, 1.0f)
					/ max(UI_BRIGHTNESS_NITS, 1.0f);
			if (UsesSDREotfEmulation(ResolveSceneOutputTransfer())) {
				bt709 = RemoveGammaCorrection(
						ApplyGammaCorrection(bt709) * scene_to_ui_scale);
			} else {
				bt709 *= scene_to_ui_scale;
			}
		}
		return float4(
				EncodeIntermediate(
						bt709,
						intermediate_transfer,
						intermediate_scaling_nits),
				input.a);
	}

	float4 output = float4(
			EncodeOutput(
					bt709,
					white_clip,
					color_temperature_adaptation),
			input.a);
	return DrawPeakBrightness(output, position.xy);
}

float4 PublishProcessedScene(
		float4 position : SV_Position,
		float2 texcoord : TexCoord) : SV_Target {
	float4 processed = tex2D(SplitIntermediateSampler, texcoord);
	if (!SEPARATE_SCENE_UI_SCALING) return processed;
	if (IsFloatRenderTarget()) return processed;
	if (!HasPresentationTargetMetadata()) {
		// The normalized target feeds a game true-output shader. Preserve the
		// scene only in the RGBA16F handoff, then give subsequent UI rendering a
		// transparent-black canvas whose alpha can become the UI coverage mask.
		return 0.0f.xxxx;
	}

	// A normalized swapchain is not a supported split handoff. Leave it
	// unchanged rather than applying final-target compositing semantics.
	return tex2D(ReShade::BackBuffer, texcoord);
}

float4 PresentOutput(
		float4 position : SV_Position,
		float2 texcoord : TexCoord) : SV_Target {
	float4 back_buffer = tex2D(ReShade::BackBuffer, texcoord);
	if (PIPELINE_DEBUG_VIEW == PIPELINE_DEBUG_SWAPCHAIN) return back_buffer;
	if (!SEPARATE_SCENE_UI_SCALING) return back_buffer;
	float4 intermediate_metadata = tex2Dlod(
			FrameStateSampler,
			float4(5.0f / 10.0f, 0.5f, 0.0f, 0.0f));
	float4 handoff_metadata = tex2Dlod(
			FrameStateSampler,
			float4(7.0f / 10.0f, 0.5f, 0.0f, 0.0f));
	uint handoff_frame = uint(handoff_metadata.r + 0.5f)
			| (uint(handoff_metadata.g + 0.5f) << 16u);
	uint previous_frame = FRAME_COUNT == 0u
			? 0xfffffffeu
			: FRAME_COUNT - 1u;
	bool current_or_inserted_frame = handoff_frame == FRAME_COUNT
			|| handoff_frame == previous_frame;
	bool valid_handoff = current_or_inserted_frame
			&& handoff_metadata.b == float(BUFFER_WIDTH)
			&& handoff_metadata.a == float(BUFFER_HEIGHT);
	if (!valid_handoff) return back_buffer;

	bool float_target = intermediate_metadata.b >= 0.5f;
	bool presentation_target = intermediate_metadata.a >= 0.5f;
	bool final_shader_target = !float_target && !presentation_target;
	if (!float_target && !final_shader_target) return back_buffer;

	float4 input = float_target
			? back_buffer
			: tex2D(SplitIntermediateSampler, texcoord);
	uint intermediate_transfer = uint(intermediate_metadata.r + 0.5f);
	float intermediate_scaling_nits = intermediate_metadata.g;
	uint output_transfer = ResolveOutputTransfer();
	float3 bt709 = DecodeIntermediate(
			input.rgb,
			intermediate_transfer,
			intermediate_scaling_nits);
	if (UsesSDREotfEmulation(output_transfer)) {
		bt709 = ApplyGammaCorrection(bt709);
	}

	float4 output = float4(
			EncodePresentation(
					bt709,
					UI_BRIGHTNESS_NITS,
					output_transfer),
			input.a);
	if (PIPELINE_DEBUG_VIEW == PIPELINE_DEBUG_SPLIT_INTERMEDIATE) {
		return float4(output.rgb, 1.0f);
	}
	if (final_shader_target) {
		// The target was cleared to transparent black by `PublishProcessedScene`.
		// The game then renders UI into it and its true output shader presents the
		// resulting UI buffer. It retains the insertion target's intermediate
		// transfer, so decode and re-encode it at the configured UI brightness
		// before blending both signals in the final presentation encoding.
		float ui_alpha = saturate(back_buffer.a);
		float3 ui_bt709 = DecodeIntermediate(
				back_buffer.rgb,
				intermediate_transfer,
				intermediate_scaling_nits);
		if (UsesSDREotfEmulation(output_transfer)) {
			ui_bt709 = ApplyGammaCorrection(ui_bt709);
		}
		float3 ui_encoded = EncodePresentation(
				ui_bt709,
				UI_BRIGHTNESS_NITS,
				output_transfer);
		output.rgb = ui_encoded + output.rgb * (1.0f - ui_alpha);
		output.a = 1.0f;
	}
	return DrawPeakBrightness(output, position.xy, output_transfer);
}

technique RenoFX <
#if RENOFX_ACTIVE_MENU_MODE == RENOFX_MENU_MODE_SDR
	ui_label = "RenoFX SDR Toolkit";
	ui_tooltip = "Processes SDR input with color grading. In split mode, select this technique in RenoDX Pipeline Insert and leave it disabled in ReShade's normal technique list.";
#else
	ui_label = "RenoFX HDR Toolkit";
	ui_tooltip = "Processes SDR or native HDR input with HDR expansion, color grading, tone mapping, and presentation. In split mode, select this technique in RenoDX Pipeline Insert and leave it disabled in ReShade's normal technique list.";
#endif
> {
	pass HAnSExtract {
		VertexShader = PostProcessVS;
		PixelShader = HAnSExtractFeatures;
		RenderTarget = HAnSFeatureTexture;
		GenerateMipmaps = false;
	}

	pass HAnSBlurHorizontal {
#if HANS_USE_COMPUTE
		ComputeShader = HAnSBoxBlurHorizontalCS;
		DispatchSizeX = (HANS_ANALYSIS_WIDTH + HANS_GROUP_SIZE - 1) / HANS_GROUP_SIZE;
		DispatchSizeY = (HANS_ANALYSIS_HEIGHT + HANS_GROUP_SIZE - 1) / HANS_GROUP_SIZE;
		DispatchSizeZ = 1;
#else
		VertexShader = PostProcessVS;
		PixelShader = HAnSBoxBlurHorizontal;
		RenderTarget = HAnSBlurHorizontalTexture;
#endif
		GenerateMipmaps = false;
	}

	pass HAnSBlurVertical {
#if HANS_USE_COMPUTE
		ComputeShader = HAnSBoxBlurVerticalCS;
		DispatchSizeX = (HANS_ANALYSIS_WIDTH + HANS_GROUP_SIZE - 1) / HANS_GROUP_SIZE;
		DispatchSizeY = (HANS_ANALYSIS_HEIGHT + HANS_GROUP_SIZE - 1) / HANS_GROUP_SIZE;
		DispatchSizeZ = 1;
#else
		VertexShader = PostProcessVS;
		PixelShader = HAnSBoxBlurVertical;
		RenderTarget = HAnSBlurTexture;
#endif
		GenerateMipmaps = false;
	}

	pass HAnSDilateHorizontal {
#if HANS_USE_COMPUTE
		ComputeShader = HAnSMaxHorizontalCS;
		DispatchSizeX = (HANS_ANALYSIS_WIDTH + HANS_GROUP_SIZE - 1) / HANS_GROUP_SIZE;
		DispatchSizeY = (HANS_ANALYSIS_HEIGHT + HANS_GROUP_SIZE - 1) / HANS_GROUP_SIZE;
		DispatchSizeZ = 1;
#else
		VertexShader = PostProcessVS;
		PixelShader = HAnSMaxHorizontal;
		RenderTarget = HAnSDilateHorizontalTexture;
#endif
		GenerateMipmaps = false;
	}

	pass HAnSDilateVertical {
#if HANS_USE_COMPUTE
		ComputeShader = HAnSMaxVerticalCS;
		DispatchSizeX = (HANS_ANALYSIS_WIDTH + HANS_GROUP_SIZE - 1) / HANS_GROUP_SIZE;
		DispatchSizeY = (HANS_ANALYSIS_HEIGHT + HANS_GROUP_SIZE - 1) / HANS_GROUP_SIZE;
		DispatchSizeZ = 1;
#else
		VertexShader = PostProcessVS;
		PixelShader = HAnSMaxVertical;
		RenderTarget = HAnSDilateTexture;
#endif
		GenerateMipmaps = false;
	}

	pass HAnSFuse {
		VertexShader = PostProcessVS;
		PixelShader = HAnSBuildMap;
		RenderTarget = HAnSMapTexture;
		GenerateMipmaps = false;
	}

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
		RenderTarget = SplitIntermediateTexture;
		GenerateMipmaps = false;
	}

	pass Publish {
		VertexShader = PostProcessVS;
		PixelShader = PublishProcessedScene;
		GenerateMipmaps = false;
	}
}

technique RenoFXOutput <
	ui_label = "RenoFX HDR Toolkit - Final Output";
	ui_tooltip = "Final output scaling and encoding for Separate Scene/UI Scaling. Enable this after all UI and other ReShade techniques, and keep it disabled when split mode is off.";
> {
	pass CachePresentationState {
		VertexShader = PostProcessVS;
		PixelShader = CacheOutputState;
		RenderTarget = OutputStateTexture;
		GenerateMipmaps = false;
	}

	pass Present {
		VertexShader = PostProcessVS;
		PixelShader = PresentOutput;
		GenerateMipmaps = false;
	}
}
