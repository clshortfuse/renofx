#include "ReShade.fxh"
#include "renofx__includes/color/RenoFXColor.fxh"

// Places other ReShade shaders in a temporary, normalized sRGB domain while
// retaining enough per-pixel scale information to restore the original HDR
// transfer and brightness afterward. Transfer and gamut helpers mirror the
// corresponding HDR10/scRGB paths in RenoFXHDRToolkit.fx.

#define INPUT_AUTO  0
#define INPUT_HDR10 1
#define INPUT_SCRGB 2

#define COLOR_SPACE_SCRGB    2
#define COLOR_SPACE_HDR10_PQ 3

#define FORMAT_RGBA16_FLOAT 10
#define FORMAT_RGB10A2      24

#ifndef RENOFX_SDR_COMPATIBILITY_GAMUT_COMPRESSION
	#define RENOFX_SDR_COMPATIBILITY_GAMUT_COMPRESSION 1
#endif

uniform uint INPUT_TRANSFER <
	ui_type = "combo";
	ui_category = "SDR Compatibility Sandwich";
	ui_items = "Auto\0HDR10\0scRGB\0";
	ui_label = "HDR Transfer";
	ui_tooltip = "Set the HDR mode used by the game.";
> = INPUT_AUTO;

uniform float INPUT_SCALING_NITS <
	ui_type = "slider";
	ui_category = "SDR Compatibility Sandwich";
	ui_min = 1.0;
	ui_max = 1000.0;
	ui_step = 1.0;
	ui_units = " nits";
	ui_label = "Input Scaling";
	ui_tooltip = "This setting will affect the exposure level of the SDR conversion.\nTry to match the brightness/paper white scale used by the game. For RenoDX mods, this wlll be one to one. For Native implementations, it will be highly variable, but 100-300 will be a typical range.";
> = 100.0;

uniform float MAX_INPUT_WHITE_NITS <
	ui_type = "slider";
	ui_category = "SDR Compatibility Sandwich";
	ui_min = 100.0;
	ui_max = 10000.0;
	ui_step = 1.0;
	ui_units = " nits";
	ui_label = "HDR Input Peak";
	ui_tooltip = "Match the peak nits the game outputs. This informs the tonemapper to make the curve more accurate.";
> = 10000.0;

texture2D BridgeScalesTexture {
	Width = BUFFER_WIDTH;
	Height = BUFFER_HEIGHT;
	Format = RG16F;
};

sampler2D BridgeScalesSampler {
	Texture = BridgeScalesTexture;
	MinFilter = POINT;
	MagFilter = POINT;
	MipFilter = POINT;
	AddressU = CLAMP;
	AddressV = CLAMP;
};

uint ResolveInputTransfer() {
	if (INPUT_TRANSFER != INPUT_AUTO) return INPUT_TRANSFER;

#if defined(BUFFER_COLOR_SPACE)
	if (BUFFER_COLOR_SPACE == COLOR_SPACE_SCRGB) return INPUT_SCRGB;
	if (BUFFER_COLOR_SPACE == COLOR_SPACE_HDR10_PQ) return INPUT_HDR10;
	// Unknown color-space metadata falls through to target-format detection.
#endif

#if defined(BUFFER_COLOR_FORMAT)
	if (BUFFER_COLOR_FORMAT == FORMAT_RGBA16_FLOAT) return INPUT_SCRGB;
	if (BUFFER_COLOR_FORMAT == FORMAT_RGB10A2) return INPUT_HDR10;
#elif defined(BUFFER_COLOR_BIT_DEPTH)
	if (BUFFER_COLOR_BIT_DEPTH == 16) return INPUT_SCRGB;
	if (BUFFER_COLOR_BIT_DEPTH == 10) return INPUT_HDR10;
#endif

	// This shader is only intended for HDR input. Prefer the common HDR10 path
	// when ReShade cannot provide transfer or format metadata.
	return INPUT_HDR10;
}

float ResolveInputScalingNits() {
	return max(INPUT_SCALING_NITS, 1.0f);
}

float3 DecodeInput(float3 input_color, uint transfer, float input_scaling_nits) {
	if (transfer == INPUT_HDR10) {
		return renodx::color::DecodeHDR10(input_color, input_scaling_nits, false);
	}
	// scRGB is linear BT.709 with 1.0 representing 80 nits.
	return renodx::color::DecodeScRGB(input_color, input_scaling_nits);
}

float3 EncodeInput(float3 bt709, uint transfer, float input_scaling_nits) {
	if (transfer == INPUT_HDR10) {
		return renodx::color::EncodeHDR10(bt709, input_scaling_nits, true);
	}
	return renodx::color::EncodeScRGB(bt709, input_scaling_nits);
}

float3 BT709AdaptiveStateD65() {
	return renodx::color::BT709ToLMS(float3(1.0f, 1.0f, 1.0f));
}

// Store only the two required per-pixel scales: gamut in R, Neutwo in G.
// Gamut compression must happen first so Neutwo's peak uses the compressed input.
float4 ComputeBridgeScales(float3 input_color, uint transfer) {
	float input_scaling_nits = ResolveInputScalingNits();
	float3 bt709 = DecodeInput(input_color, transfer, input_scaling_nits);
	float gamut_scale = 1.0f;
	#if RENOFX_SDR_COMPATIBILITY_GAMUT_COMPRESSION
		float3 adaptive_state_lms = BT709AdaptiveStateD65();
		gamut_scale = renodx::color::ComputeGamutCompressionScaleBT709AdaptiveD65(
				bt709,
				adaptive_state_lms,
				1.0f);
		bt709 = renodx::color::GamutCompressBT709AdaptiveD65(
				bt709,
				adaptive_state_lms,
				gamut_scale);
	#endif

	float maximum = max(bt709.r, max(bt709.g, bt709.b));
	float input_white_nits = max(MAX_INPUT_WHITE_NITS, 100.0f);
	float clip = max(input_white_nits / input_scaling_nits, 1.0f);
	float tone_scale = 1.0f;
	if (clip > 1.0f && maximum > 1e-6f) {
		tone_scale = renodx::tonemap::NeutwoMaxChannelScale(bt709, 1.0f, clip);
	}
	return float4(gamut_scale, tone_scale, 0.0f, 1.0f);
}

// RGB is the temporary linear BT.709 signal after gamut compression and
// Neutwo. Input reference scaling is inverted separately in the after pass.
float4 DecodeAndToneMap(
		float3 input_color,
		uint transfer,
		float2 bridge_scales) {
	float input_scaling_nits = ResolveInputScalingNits();
	float3 bt709 = DecodeInput(input_color, transfer, input_scaling_nits);
	#if RENOFX_SDR_COMPATIBILITY_GAMUT_COMPRESSION
		bt709 = renodx::color::GamutCompressBT709AdaptiveD65(
				bt709,
				BT709AdaptiveStateD65(),
				bridge_scales.x);
	#endif
	return float4(bt709 * bridge_scales.y, bridge_scales.y);
}

float4 CacheBridgeScalesPS(
		float4 position : SV_Position,
		float2 texcoord : TexCoord) : SV_Target {
	uint transfer = ResolveInputTransfer();
	float4 source = tex2D(ReShade::BackBuffer, texcoord);
	return ComputeBridgeScales(source.rgb, transfer);
}

float4 ConvertToSRGBPS(
		float4 position : SV_Position,
		float2 texcoord : TexCoord) : SV_Target {
	uint transfer = ResolveInputTransfer();
	float4 source = tex2D(ReShade::BackBuffer, texcoord);
	float2 bridge_scales = tex2D(BridgeScalesSampler, texcoord).rg;
	float4 converted = DecodeAndToneMap(source.rgb, transfer, bridge_scales);
	return float4(renodx::color::SRGBEncode(converted.rgb), source.a);
}

float4 RestoreDetectedTransferPS(
		float4 position : SV_Position,
		float2 texcoord : TexCoord) : SV_Target {
	uint transfer = ResolveInputTransfer();
	float input_scaling_nits = ResolveInputScalingNits();
	float4 source = tex2D(ReShade::BackBuffer, texcoord);
	float2 bridge_scales = tex2D(BridgeScalesSampler, texcoord).rg;
	float3 restored = renodx::color::SRGBDecode(source.rgb) / max(bridge_scales.y, 1e-8f);
	#if RENOFX_SDR_COMPATIBILITY_GAMUT_COMPRESSION
		restored = renodx::color::GamutDecompressBT709AdaptiveD65(
				restored,
				BT709AdaptiveStateD65(),
				bridge_scales.x);
	#endif
	return float4(EncodeInput(restored, transfer, input_scaling_nits), source.a);
}

technique RenoFXHDRtoSDR <
	ui_label = "RenoFX SDR Compatibility Sandwich (Before)";
	ui_tooltip = "Enable before the ReShade shaders that need a temporary SDR/sRGB-compatible signal. Enable the matching After technique after those shaders to restore HDR.";
> {
	pass CacheBridgeScales {
		VertexShader = PostProcessVS;
		PixelShader = CacheBridgeScalesPS;
		RenderTarget = BridgeScalesTexture;
		GenerateMipmaps = false;
	}

	pass ConvertToSRGB {
		VertexShader = PostProcessVS;
		PixelShader = ConvertToSRGBPS;
		GenerateMipmaps = false;
	}
}

technique RenoFXSDRtoHDR <
	ui_label = "RenoFX SDR Compatibility Sandwich (After)";
	ui_tooltip = "Enable after the ReShade shaders processed the temporary sRGB signal. It reverses Neutwo, optionally reverses cached BT.709 gamut compression, and restores the detected input transfer using the same input reference scale.";
> {
	pass RestoreDetectedTransfer {
		VertexShader = PostProcessVS;
		PixelShader = RestoreDetectedTransferPS;
		GenerateMipmaps = false;
	}
}