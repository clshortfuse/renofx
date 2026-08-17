# RenoFX HDR Toolkit Agent Guide

This repository contains a ReShade FX shader that grades SDR or native HDR input, optionally separates scene processing from final UI presentation, and supports RenoDX pipeline insertion.

The main implementation is `Shaders/RenoFXHDRToolkit.fx`.

## Core Representation

The processing pipeline uses **linear BT.709 RGB normalized to the configured input reference white** as its common internal representation.

- SDR input is treated as 100-nit reference white.
- HDR10 input is PQ-decoded to BT.2020 nits, converted to BT.709, and divided by `INPUT_SCALING_NITS`.
- scRGB input is linear BT.709, with `1.0 = 80 nits`, then normalized by `INPUT_SCALING_NITS`.
- Final HDR brightness is established during output encoding using `GAME_BRIGHTNESS_NITS` or `UI_BRIGHTNESS_NITS`.

Do not insert unexplained transfer encoding, gamut conversion, or nit scaling into the middle of the pipeline. Most grading and tone-mapping functions expect normalized linear BT.709 or an explicitly selected linear working space.

## High-Level Frame Flow

The original `RenoFX` frame flow consists of four passes. Six preceding
half-resolution HAnS passes imported from `Shaders/RenoFXHAnS.fx` build a
per-pixel highlight map. ReShade FX does not support runtime conditions on
individual passes, so Off bypasses HAnS output but cannot omit the scheduled
draws/dispatches. All HAnS shaders must return before texture sampling and
filtering when analysis is disabled:

1. `HAnSExtract` converts normalized linear BT.709 input to gamma 2.2 and packs minRGB, encoded BT.709 luma, and maxRGB into RGB. This follows the paper's display-referred method with modern BT.709 coefficients. Gamma encoding is not represented as a working space.
2. `HAnSBlurHorizontal` and `HAnSBlurVertical` apply the paper's moving average. D3D11/D3D12 run tiled 8x8 compute kernels with shared-memory halos; other APIs retain the pixel-pass fallback.
3. `HAnSDilateHorizontal` and `HAnSDilateVertical` apply a component-wise maximum filter with the same footprint and the same compute/fallback split.
4. `HAnSFuse` calculates positive local contrast, applies the $p=20$ sigmoid and absolute-intensity weighting, then stores the fused map in red and the three feature maps in GBA.

Feature extraction and fusion are fullscreen pixel passes. The four spatial
filters default to compute on D3D11/D3D12 and pixel shaders elsewhere;
`HANS_USE_COMPUTE=0` or `1` overrides that choice through ReShade's
preprocessor definitions. The filters are separable and process all three HAnS branches in one
packed RGB sample. `HANS_MAX_RADIUS` bounds the dynamic loops and compute tile
halos; analysis is at
half resolution, so `HANS_SIZE` is converted from source-pixel radius to
analysis texels.

`Main` combines `HAnSLocalAvailability(texcoord)` with the frame-global APL
availability and passes the product to `ApplyControls`. HAnS therefore affects
HDR Boost only; grading, Neutwo, gamut compression, and presentation remain
independent. Auto mode bypasses HAnS for HDR10/scRGB input. The analysis copy is
clamped and converted to sRGB, but the scene-processing source remains linear
and unclamped.

1. **`MeasureAveragePictureLevel`** calls `MeasureAPL`.
   - Decodes the back buffer with `DecodeInput`.
   - Measures normalized Yf brightness.
   - Writes `APLTexture` and generates its mip chain.
   - The last mip is later read as scene APL for the HDR Boost limiter.

2. **`BuildFrameState`** calls `CacheFrameState`.
   - Writes four frame-global records into `FrameStateTexture`.
   - Caches estimated peak white, APL-dependent boost availability, peak-overlay data, color-temperature adaptation, intermediate transfer/scaling metadata, target capabilities, and a frame/dimension handshake.

3. **`Composite`** calls `Main` into `SplitIntermediateTexture` (`RGBA16F`).
   - Decodes the source into normalized linear BT.709.
   - Applies HDR Boost and grading.
   - Applies tone mapping and color temperature as appropriate.
   - In normal mode, encodes directly for presentation.
   - In split mode, prepares and encodes a scene/UI intermediate instead of final display output.

4. **`Publish`** calls `PublishProcessedScene`.
   - In normal mode, publishes the processed result.
   - In split mode with a floating-point insertion target, runs/publishes the processed scene.
   - With a normalized insertion target, leaves the back buffer unchanged because extended values cannot safely pass through it; the final technique reads the `RGBA16F` handoff instead.

The `RenoFXOutput` technique runs after downstream UI and other effects:

1. **`CachePresentationState`** calls `CacheOutputState` and publishes authoritative output-transfer metadata for the next inserted draw.
2. **`Present`** calls `PresentOutput`, validates the handoff, combines the correct scene/UI source, applies deferred gamma correction, performs final gamut compression and output encoding, and draws the optional peak overlay.

## Transfer Resolution and Encoding

### Input

`ResolveInputTransfer` uses an explicit `INPUT_TRANSFER` first. Auto mode prefers `BUFFER_COLOR_SPACE`, then format/bit-depth heuristics, and otherwise falls back to sRGB.

`DecodeInput` converts the selected encoding to normalized linear BT.709:

- Linear: passthrough.
- sRGB: `SRGBDecode`.
- Gamma 2.2 / BT.1886: sign-preserving power decode.
- HDR10: PQ decode, BT.2020-to-BT.709 conversion, then input-reference normalization.
- scRGB: conversion from the 80-nit scRGB scale to the configured input scale.

`EncodeIntermediate` and `DecodeIntermediate` form a matched pair for split mode. Their HDR10 path intentionally preserves signed floating-point components via `PQEncodeSafe` and `PQDecodeSafe`.

### Output

`ResolveOutputTransfer` uses an explicit `OUTPUT_TRANSFER` first, then color-space metadata, then target format/bit-depth heuristics, and finally sRGB.

`ResolveSceneOutputTransfer` is important for inserted permutations. If final-target metadata is unavailable, it reads `OutputStateTexture`; its fallback is HDR10 while split mode is active.

Final output is divided into two stages:

1. `PrepareOutputLinear` applies Neutwo tone mapping, optional SDR EOTF emulation, and color-temperature adaptation while still in linear BT.709.
2. `EncodePresentation` applies output-gamut compression and encodes Linear, sRGB, Gamma 2.2, BT.1886, HDR10/PQ, or scRGB using the supplied reference-white nits.

Keep this separation intact: scene processing should not depend on the final display encoding unless the operation explicitly models display behavior.

## HDR Boost and Grading

`ApplyControls` coordinates inverse tone mapping and color grading.

### HDR Boost

- `HDRBoostChannel` provides the per-channel expansion curve.
- `ApplyHDRBoostShaping` applies it in BT.709, BT.2020, AP1, or LMS.
- `ApplyHDRBoostYf` provides a luminance-only path that preserves RGB ratios.
- `ComputeAPLHDRBoostAvailability` reduces boost as scene APL rises.
- `ApplyHDRBoostGamutExpansion` blends between brightness-only expansion and the selected working-space result.

### Grading

- `ApplyBrightnessGradingShaping` handles highlights, shadows, contrast, and flare.
- `ApplyColorGrading` handles saturation, highlight saturation, and blowout.
- `ApplyGradingYf` provides the luminance-preserving grading path.
- Global saturation can use OKLab or working-space Yf depending on `SATURATION_SPACE`.

When HDR Boost and brightness grading use the same non-Yf space with full gamut expansion, `ApplyCombinedBrightnessShaping` chains both and performs LMS hue restoration only once. Preserve this optimization and its color behavior when changing either stage.

## Hue Restoration

Brightness transforms in LMS can alter hue. `RestoreLMSHue` restores source hue direction in a MacLeod-Boynton-style chromaticity representation while respecting the CIE 170-2 observer boundary.

The restoration path is intentionally limited to `SPACE_LMS` by `RestoreWorkingHue`. Other working spaces return the transformed value unchanged. `LMS_HUE_RESTORE_STRENGTH` is a compile-time override.

## Peak Estimation and Tone Mapping

`EstimatePeakWhiteBT709` evaluates configured maximum input white through HDR Boost and brightness grading. The result is cached in grading space and used for:

- highlight saturation and blowout behavior,
- deriving Neutwo's white clip,
- the optional estimated-peak overlay.

`ApplyNeutwo` supports per-channel working spaces, Yf, and brightest-channel modes. For HDR output, its target peak is `TONEMAP_PEAK_NITS / GAME_BRIGHTNESS_NITS`. SDR EOTF emulation modifies the effective tone-map peak so tone mapping and later gamma correction remain consistent.

## Gamut Compression

`ApplyGamutCompression` runs immediately before presentation encoding. It targets BT.709 or BT.2020 and uses Stockman-Sharpe LMS plus MacLeod-Boynton chromaticity geometry.

The compressor:

1. Fast-paths colors already inside the target RGB triangle.
2. Clamps against the CIE 170-2 observer boundary.
3. Finds the ray intersection with the target gamut triangle.
4. Uses a Neutwo-derived soft scale outside the target.
5. Converts back to linear BT.709 while approximately preserving brightness.

Avoid ordinary RGB clipping before this stage; negative components can carry valid wide-gamut color information.

## Split Scene/UI Mode

`SEPARATE_SCENE_UI_SCALING` enables the RenoDX insertion workflow.

- `Main` processes the scene before UI composition.
- Scene brightness is converted into the UI reference scale using `GAME_BRIGHTNESS_NITS / UI_BRIGHTNESS_NITS`.
- If SDR EOTF emulation is enabled, scaling is performed in the corrected domain and then reversed so final correction occurs only once.
- `SplitIntermediateTexture` preserves extended values between adjacent passes.
- `FrameStateTexture` texels 2 and 3 describe and validate the intermediate handoff.
- `PresentOutput` rejects stale frames, mismatched dimensions, and unsafe normalized-target handoffs.
- `RenoFXOutput` must remain after UI and other ReShade techniques and should only be enabled for split mode.

Be especially careful with `FRAME_COUNT`: inserted and final permutations can observe adjacent frame-count values. The handshake intentionally accepts the current or immediately previous frame while still requiring matching dimensions.

## Persistent Texture Layouts

### `FrameStateTexture` (4x1 RGBA32F)

- **Texel 0:** estimated peak white in grading space (`RGB`), APL-dependent HDR Boost availability (`A`).
- **Texel 1:** estimated overlay peak nits (`R`), Bradford color-temperature adaptation (`GBA`).
- **Texel 2:** intermediate transfer (`R`), intermediate scaling nits (`G`), float-target flag (`B`), authoritative presentation-target metadata flag (`A`).
- **Texel 3:** packed frame count low/high halves (`RG`), buffer width/height (`BA`).

### `OutputStateTexture` (1x1 RGBA32F)

Stores resolved final output transfer, packed frame count, and a validity flag for inserted permutations.

### `SplitIntermediateTexture` (buffer-sized RGBA16F)

Carries the processed scene or downstream scene/UI composite without clipping extended or signed values.

### HAnS textures (half-resolution RGBA16F)

- `HAnSFeatureTexture`: minimum component, luminance, and maximum component from the selected HAnS analysis space in RGB.
- `HAnSBlurHorizontalTexture` / `HAnSBlurTexture`: separable moving-average intermediates.
- `HAnSDilateHorizontalTexture` / `HAnSDilateTexture`: separable maximum-filter intermediates.
- `HAnSMapTexture`: fused map in red and per-feature maps in GBA.

If these layouts change, update every writer, reader, UV coordinate, and explanatory comment together.

## Important Invariants

Future changes should preserve these invariants:

- Internal scene data is linear BT.709 unless a function explicitly names another working space or transfer.
- Transfer functions are sign-preserving where intermediate floating-point data may be signed.
- HDR10 presentation uses BT.2020 PQ with absolute nits; scRGB uses linear BT.709 with `1.0 = 80 nits`.
- Final gamut compression occurs before output encoding.
- Tone mapping is applied once, before final presentation encoding.
- SDR EOTF emulation is skipped for SDR output and for input already decoded as Gamma 2.2 or BT.1886.
- Normal and split paths should produce equivalent scene processing; split mode differs only in scene/UI scaling, handoff, and deferred presentation.
- Alpha is preserved through all image passes.
- Frame-state texture packing must stay exactly representable and synchronized with its readers.
- Neutral control defaults should avoid unnecessary transforms and preserve the source appearance.

## Safe Change Checklist

When modifying the shader:

1. Identify the expected input and output representation of every touched function.
2. Trace both normal mode and split mode; do not validate only `Main`.
3. Check SDR, HDR10, and scRGB transfer paths.
4. Check explicit and Auto transfer resolution, including unknown insertion metadata.
5. Preserve matched encode/decode pairs for intermediate data.
6. Re-evaluate peak estimation if HDR Boost, brightness grading, tone mapping, or reference scaling changes.
7. Re-evaluate gamut behavior if a transform introduces negative RGB components.
8. Update texture-layout comments and all readers when cached state changes.
9. Keep expensive frame-global calculations in `CacheFrameState` rather than repeating them per pixel when possible.
10. Preserve pass ordering and the `RenoFX`/`RenoFXOutput` responsibilities.
