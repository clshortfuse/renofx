# HAnS Highlight Analysis Integration Plan

## Objective

Implement the paper **“Highlights Analysis System (HAnS) for Low Dynamic Range to High Dynamic Range Conversion of Cinematic LDR Content”** as a standalone ReShade FX module, then import it into `Shaders/RenoFXHDRToolkit.fx`.

The HAnS module will **not perform inverse tone mapping**. It will generate a per-pixel auxiliary map describing:

- whether a pixel is likely to belong to a highlight, and
- how strongly RenoFX should apply HDR Boost to that pixel.

The first integration should replace the current use of a single frame-wide APL value as the primary HDR Boost decision. The existing APL limiter may remain as an optional global safety multiplier, but HAnS will provide the local decision.

## Paper Algorithm Summary

HAnS assumes that cinematic LDR highlights are generally:

1. brighter than their local surroundings,
2. smaller than nearby diffuse bright structures, and
3. bright in at least one of three pixel-wise feature representations.

For normalized LDR RGB input $I(x)$, the paper extracts three features:

$$
I_{\min}(x)=\min(I_r,I_g,I_b)
$$

$$
I_{\text{luma}}(x)=0.2989I_r+0.5870I_g+0.1140I_b
$$

$$
I_{\max}(x)=\max(I_r,I_g,I_b)
$$

Each feature $I_f$ independently passes through the same Highlight Detection (HLD) procedure:

1. Apply a $k\times k$ moving-average filter:

$$
I_{f,lp}=H_k * I_f
$$

2. Dilate that low-pass result with a $k\times k$ maximum filter:

$$
I_{f,lpd}(x)=\max_{y\in\alpha_k(x)} I_{f,lp}(y)
$$

3. Extract positive local contrast:

$$
I_{f,lc}(x)=\max(I_f(x)-I_{f,lpd}(x),0)
$$

4. Soft-threshold the contrast with a sigmoid:

$$
g(I_{f,lc})=\frac{1}{1+e^{-p(I_{f,lc}-t)}}
$$

The paper fixes sigmoid steepness at $p=20$ and commonly uses a local-contrast threshold $t=0.2$ or $t=0.3$ for normalized LDR input. Both $k$ and $t$ are identified as artistic degrees of freedom.

5. Weight the result by the feature’s absolute intensity:

$$
M_f(x)=I_f(x)\,g(I_{f,lc}(x))
$$

6. Fuse all three feature maps with a pixel-wise maximum:

$$
M(x)=\max(M_{\min},M_{\text{luma}},M_{\max})
$$

The resulting $M(x)\in[0,1]$ is the HAnS Highlights Map. It is continuous, not merely a binary segmentation mask.

## Scope and Non-Goals

### In scope

- Faithful implementation of the paper’s minRGB, luma, and maxRGB branches.
- A separable moving-average filter.
- A separable grayscale dilation/max filter.
- Continuous local-contrast soft thresholding.
- A per-pixel highlight-confidence/boost map.
- Integration with RenoFX HDR Boost.
- Optional retention of frame APL as a global limiter.
- Debug visualizations for every major HAnS stage.
- Performance controls appropriate for real-time ReShade use.

### Out of scope for the first implementation

- HAnS’s example inverse-tone-mapping equations from Section IV of the paper.
- Object segmentation or connected-component analysis.
- Learned highlight detection.
- Temporal accumulation requiring motion vectors.
- Altering RenoFX tone mapping, color grading, output encoding, or gamut compression.
- Applying HAnS to native HDR as though it were normalized LDR without an explicit policy.

## Proposed File Structure

Create:

- `Shaders/RenoFXHAnS.fx` — resources, uniforms, HAnS shader functions, and reusable pass declarations/macros.

Modify:

- `Shaders/RenoFXHDRToolkit.fx` — import the HAnS module, schedule its passes before frame-state caching and scene processing, and sample its output during HDR Boost.
- `AGENT.md` — document the resulting HAnS resources, pass ordering, and HDR Boost integration after implementation.

The module should be imported with a preprocessor include rather than enabled as an independently ordered ReShade technique. Correct ordering relative to `BuildFrameState` and `Composite` is required, while ReShade users can reorder separate techniques. The included module can own textures, samplers, uniforms, pixel shaders, and pass-body macros; `RenoFXHDRToolkit.fx` should own the final technique order.

If ReShade FX rejects pass macros or they make diagnostics difficult, keep all HAnS resources and pixel shaders in `RenoFXHAnS.fx` and write the small pass declarations directly inside the `RenoFX` technique.

## Input-Domain Policy

The paper operates on normalized **LDR RGB image values in $[0,1]$**, not on absolute HDR nits. HAnS therefore needs a clearly defined analysis signal.

### Initial policy

For SDR input:

1. Read `ReShade::BackBuffer`.
2. Resolve the input transfer using the existing RenoFX logic.
3. Decode to normalized linear BT.709 with `DecodeInput`.
4. Re-encode to a normalized display-referred LDR signal for paper-compatible thresholds:
   - use `saturate(SRGBEncode(max(bt709, 0)))` for Linear or sRGB SDR input,
   - use the corresponding normalized encoded signal for explicit Gamma 2.2 or BT.1886 input, or convert all SDR modes to the common sRGB analysis signal for stable HAnS controls.
5. Clamp only the **analysis copy** to $[0,1]$; do not clamp the scene-processing source.

The preferred first implementation is a common sRGB analysis signal because the paper’s $t=0.2$–$0.3$ guidance is display-referred and this makes one threshold behave consistently across RenoFX input-transfer settings.

### HDR and unclamped-input policy

HAnS is designed for LDR-to-HDR conversion. Add a policy control with these modes:

- **Auto:** use HAnS for SDR input; return full HDR Boost availability for HDR10/scRGB input.
- **Off:** return full local availability and preserve current RenoFX HDR Boost behavior.

For upgraded SDR swapchains containing values above SDR white, clamp only HAnS’s analysis input to $[0,1]$. RenoFX must retain the unclamped source for actual processing.

## Texture and Sampler Design

Use packed RGB textures so all three paper features are processed in parallel:

- `HAnSFeatureTexture`
  - `R = minRGB`
  - `G = luma`
  - `B = maxRGB`
  - suggested format: `RGBA16F`
- `HAnSBlurHorizontalTexture`
  - packed horizontal box-filter result
  - suggested format: `RGBA16F`
- `HAnSBlurTexture`
  - packed completed 2D box-filter result
  - suggested format: `RGBA16F`
- `HAnSDilateHorizontalTexture`
  - packed horizontal maximum-filter result
  - suggested format: `RGBA16F`
- `HAnSDilateTexture`
  - packed completed 2D maximum-filter result
  - suggested format: `RGBA16F`
- `HAnSMapTexture`
  - `R = fused Highlights Map M`
  - optionally reserve `GBA` for debug branches or future confidence data
  - suggested format: `R16F` if ReShade render-target support is reliable; otherwise `RGBA16F`

All intermediate samplers should use:

- point sampling for explicit tap locations,
- clamped addressing,
- no mipmaps unless an approximation path explicitly uses them.

### Resolution strategy

Start with a configurable analysis scale:

- Full resolution for reference/quality validation.
- Half resolution as the expected default.
- Quarter resolution as a performance option.

Texture dimensions in ReShade FX are compile-time expressions. Prefer preprocessor configuration for scale if uniform-sized resources are unsupported. The final HAnS map must be sampled bilinearly in `Main` when analysis resolution is lower than output resolution.

The HAnS size parameter must represent an approximately constant source-image footprint. Convert the user-facing full-resolution diameter/radius to analysis-resolution texels before filtering.

## Pass Plan

Insert the HAnS passes at the beginning of the `RenoFX` technique, before APL measurement and `BuildFrameState`.

### Pass 1 — Extract packed features

Pixel shader: `HAnSExtractFeatures`

Input:

- `ReShade::BackBuffer`

Output:

- `HAnSFeatureTexture`

Work:

- Build the normalized LDR analysis signal.
- Calculate minRGB, paper luma, and maxRGB.
- Store all three in RGB.
- Return zeros when HAnS is disabled for the resolved input type.

Keep the paper’s luma coefficients for the faithful mode. A later optional mode may use BT.709 coefficients, but it must not silently replace the paper formulation.

### Pass 2 — Horizontal moving average

Pixel shader: `HAnSBoxBlurHorizontal`

Input:

- `HAnSFeatureTexture`

Output:

- `HAnSBlurHorizontalTexture`

Work:

- Compute a horizontal box average over the configured $k$ footprint.
- Process packed RGB channels together.
- Normalize by the number/weight of valid taps.
- Use clamped sampling so borders remain stable.

### Pass 3 — Vertical moving average

Pixel shader: `HAnSBoxBlurVertical`

Input:

- `HAnSBlurHorizontalTexture`

Output:

- `HAnSBlurTexture`

Work:

- Complete the separable $k\times k$ moving-average filter.

### Pass 4 — Horizontal dilation

Pixel shader: `HAnSMaxHorizontal`

Input:

- `HAnSBlurTexture`

Output:

- `HAnSDilateHorizontalTexture`

Work:

- Compute the component-wise horizontal maximum over the same configured footprint.

### Pass 5 — Vertical dilation

Pixel shader: `HAnSMaxVertical`

Input:

- `HAnSDilateHorizontalTexture`

Output:

- `HAnSDilateTexture`

Work:

- Complete the separable rectangular grayscale dilation.
- A rectangular structuring element is separable and matches the paper’s stated size-based neighborhood closely.

### Pass 6 — Local contrast, soft threshold, and fusion

Pixel shader: `HAnSBuildMap`

Inputs:

- `HAnSFeatureTexture`
- `HAnSDilateTexture`

Output:

- `HAnSMapTexture`

Work:

```text
local_contrast = max(features - dilated_blur, 0)
soft = 1 / (1 + exp(-steepness * (local_contrast - threshold)))
feature_maps = features * soft
M = max(feature_maps.r, feature_maps.g, feature_maps.b)
```

Use a numerically safe exponential input clamp if needed. Do not replace the sigmoid with `smoothstep` in the faithful path because its response differs from the paper.

The paper’s sigmoid has a nonzero output below threshold. If practical tests reveal weak full-frame activation, expose an optional normalized-sigmoid mode that remaps the sigmoid’s value at zero to zero while preserving one at the upper endpoint. Keep the unmodified paper equation as the reference mode.

### Existing pass order after HAnS

After these six passes, retain:

1. `MeasureAveragePictureLevel`
2. `BuildFrameState`
3. `Composite`
4. `Publish`

No HAnS pass should use `FrameStateTexture`; HAnS must be ready before that texture is built.

## Filter Implementation Strategy

A literal large-radius box blur and dilation with loops can be too expensive or exceed shader compiler limits. Implement in stages.

### Reference implementation

- Compile-time maximum radius.
- Uniform active radius within that bound.
- Explicit symmetric taps.
- Full separable blur and max filters.
- Used to validate the equations at modest radii.

### Optimized implementation

Evaluate these options in order:

1. **Linear-sampling paired taps for box blur** to reduce texture fetches.
2. **Reduced-resolution analysis** as the main cost reduction.
3. **Multi-pass fixed-radius decomposition** if users need footprints larger than the safe loop bound.
4. **Mip-assisted broad-average approximation** only as an explicitly labeled fast mode.
5. For dilation, use staged max filters with fixed radii rather than mip averaging; averaging cannot substitute for the paper’s maximum operation.

Do not silently make the blur and dilation use different effective sizes. Their shared $k$ is central to the paper’s relative-size behavior.

## Public Controls

Add a `HAnS Highlight Analysis` UI category with:

- `HANS_ENABLED`
  - Off / Auto SDR
- `HANS_SIZE`
  - user-facing full-resolution footprint
  - describes the largest highlight size expected to receive strong detection
- `HANS_LOCAL_CONTRAST_THRESHOLD`
  - default initially `0.2` or `0.25`
  - paper-guided range should include at least `0.0`–`0.5`
- `HANS_SIGMOID_STEEPNESS`
  - default `20`
  - may be hidden/advanced if strict paper behavior is preferred
- `HANS_ANALYSIS_SCALE`
  - compile-time preset or documented preprocessor option if runtime resizing is impossible
- `HANS_STRENGTH`
  - blends from legacy/full availability to HAnS control
- `HANS_FLOOR`
  - minimum local HDR Boost availability for non-detected pixels
- `HANS_RESPONSE_GAMMA`
  - shapes the continuous map before use, analogous to the paper’s $M^\gamma$ local-boost weighting
- `HANS_DEBUG_VIEW`
  - Off, Features, Blurred, Dilated, Local Contrast, Per-Feature Maps, Fused Map, Final Availability
- optional `HANS_KEEP_APL_LIMITER`
  - allows HAnS local confidence and APL global protection to be evaluated independently

Defaults should be conservative and should not unexpectedly disable most of HDR Boost before visual calibration is complete. During initial integration, use a nonzero floor and expose the fused-map debug view prominently.

## RenoFX HDR Boost Integration

### Current behavior

`ComputeAPLHDRBoostAvailability` produces one scalar per frame. It is stored in `FrameStateTexture` texel 0 alpha and passed to every pixel through `ApplyControls`. Consequently, every pixel receives the same HDR Boost availability.

### Proposed behavior

Keep frame-global APL availability separate from per-pixel HAnS confidence:

$$
A_{local}(x)=\operatorname{lerp}(1,\operatorname{lerp}(A_{floor},1,M(x)^\gamma),S)
$$

where:

- $M(x)$ is the fused HAnS map,
- $A_{floor}$ is the configured minimum local availability,
- $\gamma$ shapes highlight selectivity,
- $S$ is `HANS_STRENGTH`.

If retaining the APL limiter:

$$
A_{final}(x)=A_{APL}\cdot A_{local}(x)
$$

Otherwise:

$$
A_{final}(x)=A_{local}(x)
$$

Pass $A_{final}(x)$ into `ApplyControls`/`ApplyHDRBoost` instead of the frame-global scalar alone.

### Required code-flow changes

- Continue caching $A_{APL}$ in `FrameStateTexture` texel 0 alpha, or rename/document it explicitly as global availability.
- In `Main`, sample `HAnSMapTexture` at the current UV.
- Convert the map to local availability using the configured floor, response gamma, and strength.
- Multiply by cached APL availability only when the global limiter remains enabled.
- Pass final per-pixel availability to `ApplyControls`.
- Keep color grading independent of HAnS; only HDR Boost should consume HAnS output.

### Peak estimation

`EstimatePeakWhiteBT709` currently receives a scalar boost availability. The peak-overlay estimate is intended to show the configured possible peak independent of scene APL. Preserve that meaning by evaluating peak estimation at full local availability (`1.0`), not at an average HAnS value.

The white clip used by tone mapping needs a conservative value. Continue deriving it from full or frame-global maximum availability rather than per-pixel HAnS, because a single cached white clip must safely cover pixels where $M(x)$ approaches 1.

## Split-Pipeline Compatibility

HAnS must execute in the same inserted `RenoFX` permutation that processes the scene before UI composition.

Requirements:

- Analyze the scene back buffer before UI is added.
- Do not run HAnS again in `RenoFXOutput`.
- Do not store HAnS state in `FrameStateTexture` unless a later feature truly requires a scalar summary.
- Sample the map only while processing the matching source dimensions.
- If HAnS resources cannot follow custom insertion dimensions reliably, add a dimension-validity fallback that returns full local availability rather than suppressing HDR Boost.
- Preserve normal-mode and split-mode equivalence for scene pixels.

## Debug and Validation Plan

### Stage validation

Add debug views and verify:

1. minRGB emphasizes achromatic/clipped highlights.
2. maxRGB catches strongly colored lights.
3. luma lies between those behaviors.
4. moving average removes fine local structure.
5. dilation spreads the strongest local average across the candidate region.
6. positive subtraction suppresses broad diffuse bright areas.
7. the sigmoid smoothly prioritizes stronger local contrast.
8. multiplication by the original feature suppresses locally contrasting but dark structures.
9. max fusion preserves detections from all three branches.

### Synthetic tests

Use or create test images with:

- a small bright square on a dark field,
- a bright square narrower than $k$,
- a bright square equal to $k$,
- a bright region wider than $k$,
- white, red, green, and blue highlights,
- a broad diffuse gradient plus small specular points,
- blurred/out-of-focus highlights,
- bright UI-like flat rectangles to verify why pre-UI insertion matters.

Expected behavior follows the paper’s Figure 6 analysis: structures smaller than $k$ should be detected in proportion to size, local contrast, and intensity; structures equal to or larger than $k$ should be strongly suppressed.

### Pipeline matrix

Validate at minimum:

- SDR sRGB normal mode.
- SDR Linear input mode.
- SDR Gamma 2.2 and BT.1886 input modes.
- Upgraded SDR on HDR10 output.
- Upgraded SDR on scRGB output.
- Normal ReShade technique execution.
- RenoDX split scene/UI insertion with float target.
- RenoDX split path with normalized target and `SplitIntermediateTexture` handoff.
- Native HDR Auto fallback.
- HAnS disabled, which must reproduce legacy/full-availability behavior.

### Quality comparisons

Capture side-by-side results for:

- existing APL-only HDR Boost,
- HAnS-only local control,
- HAnS plus APL global limiter,
- multiple $k$ and $t$ settings.

Specifically inspect:

- diffuse white walls/clouds that should not become emissive,
- small light sources and specular reflections that should receive boost,
- colored neon/emissive elements,
- subtitles and HUD elements in split mode,
- halos or block boundaries caused by reduced-resolution analysis.

### Performance measurements

Measure GPU time at 1080p, 1440p, and 4K for full, half, and quarter resolution. Record texture-fetch count per pass and total transient memory. Establish a default that is practical at 4K before enabling HAnS by default.

## Implementation Phases

### Phase 1 — Faithful module and debug output

- Create `Shaders/RenoFXHAnS.fx`.
- Add packed feature extraction.
- Add separable moving average.
- Add separable dilation.
- Add sigmoid weighting and max fusion.
- Add direct fused-map debug visualization.
- Use modest radius limits and prioritize correctness.

Exit criterion: synthetic patterns match the behavior predicted by the paper.

### Phase 2 — RenoFX integration

- Import the HAnS module.
- Insert HAnS passes before `MeasureAveragePictureLevel` and `BuildFrameState`.
- Sample the map in `Main`.
- Compute per-pixel HDR Boost availability.
- Keep grading, tone mapping, and presentation unchanged.
- Preserve an Off path that reproduces previous behavior.

Exit criterion: HAnS affects only HDR Boost and works in normal and split modes.

### Phase 3 — Input policy and native-HDR safeguards

- Implement Auto SDR / Off behavior.
- Standardize the normalized analysis signal across SDR transfer modes.
- Verify upgraded unclamped SDR handling.
- Add invalid-resource/dimension fallback behavior.

Exit criterion: no accidental native-HDR suppression and stable controls across SDR inputs.

### Phase 4 — Optimization

- Add half/quarter-resolution options.
- Reduce box-filter fetch count with paired linear samples where exact weighting permits.
- Evaluate staged fixed-radius filters for larger $k$.
- Select texture formats based on actual ReShade backend compatibility.
- Remove unnecessary intermediate channels only after debug validation.

Exit criterion: acceptable 4K GPU time without materially changing the fused map.

### Phase 5 — Calibration and defaults

- Test cinematic/game scenes containing diffuse bright areas, colored lights, and specular highlights.
- Choose defaults for size, threshold, floor, strength, and response gamma.
- Decide whether APL remains enabled by default as a global safety limiter.
- Update UI tooltips and repository documentation.

Exit criterion: defaults improve highlight selectivity without visibly flattening ordinary bright detail.

## Risks and Mitigations

### Large filter cost

Risk: box blur plus dilation requires four neighborhood-filter passes.

Mitigation: pack all three features into RGB, use separable filters, default to reduced resolution, and cap radius in the reference path.

### Reduced-resolution halos or missed tiny highlights

Risk: downsampling changes relative size and can blur small candidates.

Mitigation: preserve full-resolution feature weighting/final fusion if needed, use bilinear upsampling, scale $k$ correctly, and keep a full-resolution quality mode.

### Paper thresholds do not transfer directly to linear game buffers

Risk: $t=0.2$–$0.3$ was selected for normalized LDR image values.

Mitigation: analyze a common display-referred sRGB copy and expose debug views and threshold controls.

### False positives from UI

Risk: small bright HUD elements satisfy HAnS’s definition.

Mitigation: run HAnS at the RenoDX scene insertion point before UI; document that non-split mode cannot distinguish scene highlights from UI already present in the back buffer.

### False negatives for broad emissive objects

Risk: HAnS intentionally suppresses bright structures at or above size $k$.

Mitigation: expose $k$, retain a configurable HDR Boost floor, and optionally blend HAnS with a brightness-only signal in a later non-faithful mode.

### Native HDR misuse

Risk: paper assumptions and thresholds are invalid for absolute HDR input.

Mitigation: Auto mode bypasses HAnS on HDR10/scRGB input and returns full local availability.

### Temporal flicker

Risk: small changes near the sigmoid threshold may make the map shimmer.

Mitigation: first tune scale, threshold, and sigmoid response. Add temporal stabilization only after spatial correctness is established; without motion vectors, temporal blending must be optional and conservative to avoid trails.

## Open Decisions Before Coding

1. Whether `HANS_SIZE` should be expressed as diameter, radius, or percentage of image height. Percentage of image height is the most resolution-independent UI, while the shader can convert it to analysis texels.
2. Whether the first version should use full resolution for strict validation or half resolution for immediate practicality.
3. Whether the APL limiter remains enabled by default after HAnS integration.
4. The default HDR Boost floor for non-highlight pixels.
5. Whether explicit Gamma 2.2/BT.1886 SDR inputs are converted to a common sRGB analysis signal or analyzed in their original encoded form.
6. Whether debug intermediates remain compiled in release mode or are gated by a preprocessor option.
7. Maximum supported filter radius on the lowest targeted ReShade shader model/backend.

None of these decisions blocks the module architecture. Implement the faithful map first, expose enough diagnostics to compare choices, and calibrate the integration afterward.
