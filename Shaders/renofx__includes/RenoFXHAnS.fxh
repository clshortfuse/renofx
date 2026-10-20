// Reusable HAnS highlight-analysis include for RenoFXHDRToolkit.fx.
// Include it after the toolkit's input-decoding and working-space helpers.
// HANS_* options below are compile-time definitions, not ReShade UI uniforms.

#pragma once

// Analysis runs at half resolution. The maximum analysis radius of 12 texels
// therefore represents a 24-pixel radius in the source image.
#define HANS_ANALYSIS_WIDTH  (BUFFER_WIDTH / 2)
#define HANS_ANALYSIS_HEIGHT (BUFFER_HEIGHT / 2)
#define HANS_MAX_RADIUS 12
#define HANS_GROUP_SIZE 8
#define HANS_TILE_EXTENT (HANS_GROUP_SIZE + 2 * HANS_MAX_RADIUS)

#if __RENDERER__ >= 0xb000 && __RENDERER__ < 0xd000
	#define HANS_USE_COMPUTE 1
#else
	#define HANS_USE_COMPUTE 0
#endif

texture2D HAnSFeatureTexture {
	Width = HANS_ANALYSIS_WIDTH;
	Height = HANS_ANALYSIS_HEIGHT;
	Format = RGBA16F;
};
texture2D HAnSBlurHorizontalTexture {
	Width = HANS_ANALYSIS_WIDTH;
	Height = HANS_ANALYSIS_HEIGHT;
	Format = RGBA16F;
};
texture2D HAnSBlurTexture {
	Width = HANS_ANALYSIS_WIDTH;
	Height = HANS_ANALYSIS_HEIGHT;
	Format = RGBA16F;
};
texture2D HAnSDilateHorizontalTexture {
	Width = HANS_ANALYSIS_WIDTH;
	Height = HANS_ANALYSIS_HEIGHT;
	Format = RGBA16F;
};
texture2D HAnSDilateTexture {
	Width = HANS_ANALYSIS_WIDTH;
	Height = HANS_ANALYSIS_HEIGHT;
	Format = RGBA16F;
};
texture2D HAnSMapTexture {
	Width = HANS_ANALYSIS_WIDTH;
	Height = HANS_ANALYSIS_HEIGHT;
	Format = RGBA16F;
};

sampler2D HAnSFeatureSampler {
	Texture = HAnSFeatureTexture;
	MinFilter = POINT;
	MagFilter = POINT;
	MipFilter = POINT;
	AddressU = CLAMP;
	AddressV = CLAMP;
};
sampler2D HAnSBlurHorizontalSampler {
	Texture = HAnSBlurHorizontalTexture;
	MinFilter = POINT;
	MagFilter = POINT;
	MipFilter = POINT;
	AddressU = CLAMP;
	AddressV = CLAMP;
};
sampler2D HAnSBlurSampler {
	Texture = HAnSBlurTexture;
	MinFilter = POINT;
	MagFilter = POINT;
	MipFilter = POINT;
	AddressU = CLAMP;
	AddressV = CLAMP;
};
sampler2D HAnSDilateHorizontalSampler {
	Texture = HAnSDilateHorizontalTexture;
	MinFilter = POINT;
	MagFilter = POINT;
	MipFilter = POINT;
	AddressU = CLAMP;
	AddressV = CLAMP;
};
sampler2D HAnSDilateSampler {
	Texture = HAnSDilateTexture;
	MinFilter = POINT;
	MagFilter = POINT;
	MipFilter = POINT;
	AddressU = CLAMP;
	AddressV = CLAMP;
};
sampler2D HAnSMapSampler {
	Texture = HAnSMapTexture;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	MipFilter = POINT;
	AddressU = CLAMP;
	AddressV = CLAMP;
};

#if HANS_USE_COMPUTE
storage2D HAnSBlurHorizontalStorage {
	Texture = HAnSBlurHorizontalTexture;
};
storage2D HAnSBlurStorage {
	Texture = HAnSBlurTexture;
};
storage2D HAnSDilateHorizontalStorage {
	Texture = HAnSDilateHorizontalTexture;
};
storage2D HAnSDilateStorage {
	Texture = HAnSDilateTexture;
};

// ReShade FX/DXBC does not support multidimensional arrays. Keep both tiles
// flattened and calculate row-major indices explicitly.
groupshared float4 HAnSHorizontalTile[HANS_GROUP_SIZE * HANS_TILE_EXTENT];
groupshared float4 HAnSVerticalTile[HANS_TILE_EXTENT * HANS_GROUP_SIZE];
#endif

bool HAnSShouldAnalyze() {
	if (HANS_MODE == HANS_MODE_OFF) return false;
	uint input_transfer = ResolveInputTransfer();
	return input_transfer != INPUT_HDR10 && input_transfer != INPUT_SCRGB;
}

int HAnSRadius() {
	return min(HANS_MAX_RADIUS, max(1, int(floor(HANS_SIZE * 0.5f + 0.5f))));
}

float2 HAnSTexelSize() {
	return float2(
			1.0f / float(HANS_ANALYSIS_WIDTH),
			1.0f / float(HANS_ANALYSIS_HEIGHT));
}

float3 HAnSAnalysisColor(float3 linear_bt709) {
	return saturate(pow(linear_bt709, 1.0f / 2.2f));
}

float4 HAnSExtractFeatures(
		float4 position : SV_Position,
		float2 texcoord : TexCoord) : SV_Target {
	if (!HAnSShouldAnalyze()) return 0.0f.xxxx;

	// Paper thresholds are defined for normalized LDR data. Keep the selected
	// analysis representation bounded while preserving RenoFX's linear source.
	float3 bt709 = DecodeInput(tex2D(ReShade::BackBuffer, texcoord).rgb);
	float3 linear_bt709 = saturate(max(bt709, 0.0f));
	float3 analysis = HAnSAnalysisColor(linear_bt709);
	float minimum = min(analysis.r, min(analysis.g, analysis.b));
	// Match the paper's display-referred method using gamma-encoded RGB and
	// modern BT.709 luma coefficients.
	float luma = renodx::color::WorkingLuminance(analysis, SPACE_BT709);
	luma = saturate(luma);
	float maximum = max(analysis.r, max(analysis.g, analysis.b));
	return float4(minimum, luma, maximum, 1.0f);
}

float4 HAnSBoxBlurHorizontal(
		float4 position : SV_Position,
		float2 texcoord : TexCoord) : SV_Target {
	if (!HAnSShouldAnalyze()) return 0.0f.xxxx;
	int radius = HAnSRadius();
	float2 texel = HAnSTexelSize();
	float3 sum = 0.0f.xxx;
	float count = 0.0f;
	for (int offset = -HANS_MAX_RADIUS; offset <= HANS_MAX_RADIUS; offset++) {
		if (abs(offset) <= radius) {
			sum += tex2D(HAnSFeatureSampler, texcoord + float2(offset * texel.x, 0.0f)).rgb;
			count += 1.0f;
		}
	}
	return float4(sum / max(count, 1.0f), 1.0f);
}

float4 HAnSBoxBlurVertical(
		float4 position : SV_Position,
		float2 texcoord : TexCoord) : SV_Target {
	if (!HAnSShouldAnalyze()) return 0.0f.xxxx;
	int radius = HAnSRadius();
	float2 texel = HAnSTexelSize();
	float3 sum = 0.0f.xxx;
	float count = 0.0f;
	for (int offset = -HANS_MAX_RADIUS; offset <= HANS_MAX_RADIUS; offset++) {
		if (abs(offset) <= radius) {
			sum += tex2D(HAnSBlurHorizontalSampler, texcoord + float2(0.0f, offset * texel.y)).rgb;
			count += 1.0f;
		}
	}
	return float4(sum / max(count, 1.0f), 1.0f);
}

float4 HAnSMaxHorizontal(
		float4 position : SV_Position,
		float2 texcoord : TexCoord) : SV_Target {
	if (!HAnSShouldAnalyze()) return 0.0f.xxxx;
	int radius = HAnSRadius();
	float2 texel = HAnSTexelSize();
	float3 result = 0.0f.xxx;
	for (int offset = -HANS_MAX_RADIUS; offset <= HANS_MAX_RADIUS; offset++) {
		if (abs(offset) <= radius) {
			result = max(result, tex2D(HAnSBlurSampler, texcoord + float2(offset * texel.x, 0.0f)).rgb);
		}
	}
	return float4(result, 1.0f);
}

float4 HAnSMaxVertical(
		float4 position : SV_Position,
		float2 texcoord : TexCoord) : SV_Target {
	if (!HAnSShouldAnalyze()) return 0.0f.xxxx;
	int radius = HAnSRadius();
	float2 texel = HAnSTexelSize();
	float3 result = 0.0f.xxx;
	for (int offset = -HANS_MAX_RADIUS; offset <= HANS_MAX_RADIUS; offset++) {
		if (abs(offset) <= radius) {
			result = max(result, tex2D(HAnSDilateHorizontalSampler, texcoord + float2(0.0f, offset * texel.y)).rgb);
		}
	}

	return float4(result, 1.0f);
}

#if HANS_USE_COMPUTE
int2 HAnSClampCoordinate(int2 coordinate) {
	return clamp(
			coordinate,
			int2(0, 0),
			int2(HANS_ANALYSIS_WIDTH - 1, HANS_ANALYSIS_HEIGHT - 1));
}

void HAnSLoadHorizontalTile(
		sampler2D source,
		uint3 group_id,
		uint3 group_thread_id,
		bool should_analyze) {
	uint linear_thread = group_thread_id.y * HANS_GROUP_SIZE
			+ group_thread_id.x;
	for (uint load = 0; load < 4; load++) {
		uint tile_index = linear_thread + load * HANS_GROUP_SIZE * HANS_GROUP_SIZE;
		uint tile_y = tile_index / HANS_TILE_EXTENT;
		uint tile_x = tile_index - tile_y * HANS_TILE_EXTENT;
		int2 source_coordinate = int2(
				int(group_id.x * HANS_GROUP_SIZE + tile_x) - HANS_MAX_RADIUS,
				int(group_id.y * HANS_GROUP_SIZE + tile_y));
		HAnSHorizontalTile[tile_y * HANS_TILE_EXTENT + tile_x] = should_analyze
				? tex2Dfetch(source, HAnSClampCoordinate(source_coordinate))
				: 0.0f.xxxx;
	}
}

void HAnSLoadVerticalTile(
		sampler2D source,
		uint3 group_id,
		uint3 group_thread_id,
		bool should_analyze) {
	uint linear_thread = group_thread_id.y * HANS_GROUP_SIZE
			+ group_thread_id.x;
	for (uint load = 0; load < 4; load++) {
		uint tile_index = linear_thread + load * HANS_GROUP_SIZE * HANS_GROUP_SIZE;
		uint tile_y = tile_index / HANS_GROUP_SIZE;
		uint tile_x = tile_index - tile_y * HANS_GROUP_SIZE;
		int2 source_coordinate = int2(
				int(group_id.x * HANS_GROUP_SIZE + tile_x),
				int(group_id.y * HANS_GROUP_SIZE + tile_y) - HANS_MAX_RADIUS);
		HAnSVerticalTile[tile_y * HANS_GROUP_SIZE + tile_x] = should_analyze
				? tex2Dfetch(source, HAnSClampCoordinate(source_coordinate))
				: 0.0f.xxxx;
	}
}

[numthreads(HANS_GROUP_SIZE, HANS_GROUP_SIZE, 1)]
void HAnSBoxBlurHorizontalCS(
		uint3 dispatch_thread_id : SV_DispatchThreadID,
		uint3 group_id : SV_GroupID,
		uint3 group_thread_id : SV_GroupThreadID) {
	bool should_analyze = HAnSShouldAnalyze();
	HAnSLoadHorizontalTile(
			HAnSFeatureSampler,
			group_id,
			group_thread_id,
			should_analyze);
	barrier();

	if (should_analyze
			&& dispatch_thread_id.x < HANS_ANALYSIS_WIDTH
			&& dispatch_thread_id.y < HANS_ANALYSIS_HEIGHT) {
		int radius = HAnSRadius();
		float3 sum = 0.0f.xxx;
		for (int offset = -HANS_MAX_RADIUS; offset <= HANS_MAX_RADIUS; offset++) {
			if (abs(offset) <= radius) {
				sum += HAnSHorizontalTile[
						group_thread_id.y * HANS_TILE_EXTENT
						+ group_thread_id.x + HANS_MAX_RADIUS + offset].rgb;
			}
		}
		float count = float(radius * 2 + 1);
		tex2Dstore(
				HAnSBlurHorizontalStorage,
				dispatch_thread_id.xy,
				float4(sum / count, 1.0f));
	}
}

[numthreads(HANS_GROUP_SIZE, HANS_GROUP_SIZE, 1)]
void HAnSBoxBlurVerticalCS(
		uint3 dispatch_thread_id : SV_DispatchThreadID,
		uint3 group_id : SV_GroupID,
		uint3 group_thread_id : SV_GroupThreadID) {
	bool should_analyze = HAnSShouldAnalyze();
	HAnSLoadVerticalTile(
			HAnSBlurHorizontalSampler,
			group_id,
			group_thread_id,
			should_analyze);
	barrier();

	if (should_analyze
			&& dispatch_thread_id.x < HANS_ANALYSIS_WIDTH
			&& dispatch_thread_id.y < HANS_ANALYSIS_HEIGHT) {
		int radius = HAnSRadius();
		float3 sum = 0.0f.xxx;
		for (int offset = -HANS_MAX_RADIUS; offset <= HANS_MAX_RADIUS; offset++) {
			if (abs(offset) <= radius) {
				sum += HAnSVerticalTile[
						(group_thread_id.y + HANS_MAX_RADIUS + offset)
								* HANS_GROUP_SIZE
						+ group_thread_id.x].rgb;
			}
		}
		float count = float(radius * 2 + 1);
		tex2Dstore(
				HAnSBlurStorage,
				dispatch_thread_id.xy,
				float4(sum / count, 1.0f));
	}
}

[numthreads(HANS_GROUP_SIZE, HANS_GROUP_SIZE, 1)]
void HAnSMaxHorizontalCS(
		uint3 dispatch_thread_id : SV_DispatchThreadID,
		uint3 group_id : SV_GroupID,
		uint3 group_thread_id : SV_GroupThreadID) {
	bool should_analyze = HAnSShouldAnalyze();
	HAnSLoadHorizontalTile(
			HAnSBlurSampler,
			group_id,
			group_thread_id,
			should_analyze);
	barrier();

	if (should_analyze
			&& dispatch_thread_id.x < HANS_ANALYSIS_WIDTH
			&& dispatch_thread_id.y < HANS_ANALYSIS_HEIGHT) {
		int radius = HAnSRadius();
		float3 result = 0.0f.xxx;
		for (int offset = -HANS_MAX_RADIUS; offset <= HANS_MAX_RADIUS; offset++) {
			if (abs(offset) <= radius) {
				result = max(
						result,
						HAnSHorizontalTile[
								group_thread_id.y * HANS_TILE_EXTENT
								+ group_thread_id.x + HANS_MAX_RADIUS + offset].rgb);
			}
		}
		tex2Dstore(
				HAnSDilateHorizontalStorage,
				dispatch_thread_id.xy,
				float4(result, 1.0f));
	}
}

[numthreads(HANS_GROUP_SIZE, HANS_GROUP_SIZE, 1)]
void HAnSMaxVerticalCS(
		uint3 dispatch_thread_id : SV_DispatchThreadID,
		uint3 group_id : SV_GroupID,
		uint3 group_thread_id : SV_GroupThreadID) {
	bool should_analyze = HAnSShouldAnalyze();
	HAnSLoadVerticalTile(
			HAnSDilateHorizontalSampler,
			group_id,
			group_thread_id,
			should_analyze);
	barrier();

	if (should_analyze
			&& dispatch_thread_id.x < HANS_ANALYSIS_WIDTH
			&& dispatch_thread_id.y < HANS_ANALYSIS_HEIGHT) {
		int radius = HAnSRadius();
		float3 result = 0.0f.xxx;
		for (int offset = -HANS_MAX_RADIUS; offset <= HANS_MAX_RADIUS; offset++) {
			if (abs(offset) <= radius) {
				result = max(
						result,
						HAnSVerticalTile[
								(group_thread_id.y + HANS_MAX_RADIUS + offset)
										* HANS_GROUP_SIZE
								+ group_thread_id.x].rgb);
			}
		}
		tex2Dstore(
				HAnSDilateStorage,
				dispatch_thread_id.xy,
				float4(result, 1.0f));
	}
}
#endif

float3 HAnSFeatureMaps(float2 texcoord) {
	float3 features = tex2D(HAnSFeatureSampler, texcoord).rgb;
	float3 dilated = tex2D(HAnSDilateSampler, texcoord).rgb;
	float3 local_contrast = max(features - dilated, 0.0f);
	float3 soft = rcp(1.0f + exp(clamp(
			-20.0f * (local_contrast - HANS_LOCAL_CONTRAST_THRESHOLD),
			-20.0f,
			20.0f)));
	return features * soft;
}

float4 HAnSBuildMap(
		float4 position : SV_Position,
		float2 texcoord : TexCoord) : SV_Target {
	if (!HAnSShouldAnalyze()) return float4(1.0f, 1.0f, 1.0f, 1.0f);
	float3 feature_maps = HAnSFeatureMaps(texcoord);
	float fused = max(feature_maps.r, max(feature_maps.g, feature_maps.b));
	return float4(fused, feature_maps);
}

float HAnSLocalAvailability(float2 texcoord) {
	if (!HAnSShouldAnalyze()) return 1.0f;
	float map = saturate(tex2D(HAnSMapSampler, texcoord).r);
	float shaped = pow(map, max(HANS_RESPONSE_GAMMA, 0.1f));
	float selected = lerp(saturate(HANS_FLOOR * 0.01f), 1.0f, shaped);
	return lerp(1.0f, selected, saturate(HANS_STRENGTH * 0.01f));
}

float3 HAnSDebugColor(float2 texcoord, float final_availability) {
	if (HANS_DEBUG_VIEW == 1) return tex2D(HAnSFeatureSampler, texcoord).rgb;
	if (HANS_DEBUG_VIEW == 2) return tex2D(HAnSBlurSampler, texcoord).rgb;
	if (HANS_DEBUG_VIEW == 3) return tex2D(HAnSDilateSampler, texcoord).rgb;
	if (HANS_DEBUG_VIEW == 4) {
		return max(
				tex2D(HAnSFeatureSampler, texcoord).rgb
				- tex2D(HAnSDilateSampler, texcoord).rgb,
				0.0f);
	}
	if (HANS_DEBUG_VIEW == 5) return tex2D(HAnSMapSampler, texcoord).gba;
	if (HANS_DEBUG_VIEW == 6) return tex2D(HAnSMapSampler, texcoord).rrr;
	if (HANS_DEBUG_VIEW == 7) return final_availability.xxx;
	return 0.0f.xxx;
}

