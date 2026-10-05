// SPDX-License-Identifier: CC-BY-NC-SA-4.0
// Copyright (c) 2026 Starodubysko (https://github.com/Starodubysko/sd-reshade-shaders)

#define SD_COLDENSITY
#include "ReShade.fxh"

uniform float cAmount <
    ui_type = "slider";
    ui_min = 0.00;
    ui_max = 1.00;
    ui_step = 0.05;
    ui_label = "Amount";
    ui_tooltip = "Ctrl+Click to enter values greater than 1.";
> = 0.50;

uniform float cRolloff <
    ui_type = "slider";
    ui_min = 0.00;
    ui_max = 1.00;
    ui_step = 0.05;
    ui_label = "Rolloff";
    ui_tooltip = "Decreases the effect gradually in bright areas.\nAt 1, it bypasses reference white and specular highlights.";
> = 0.00;

// Target nits for scRGB and HDR10 (ITU-R BT.2408 default)
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3
    #ifndef SD_REFERENCE_WHITE
        #define SD_REFERENCE_WHITE 203.0
    #endif
#endif

float Rolloff(float cMax)
{
#if BUFFER_COLOR_SPACE == 2   // scRGB
    float level = sqrt(cMax * (80.0 / max(SD_REFERENCE_WHITE, 1.0)));
#elif BUFFER_COLOR_SPACE == 3 // HDR10 (PQ)
    float p = pow(saturate(cMax), 1.0 / 78.84375);
    float nits = 10000.0 * pow(max((p - 0.8359375) / (18.8515625 - 18.6875 * p), 0.0), 1.0 / 0.1593017578125);
    float level = sqrt(nits * (1.0 / max(SD_REFERENCE_WHITE, 1.0)));
#elif BUFFER_COLOR_SPACE == 4 // HLG
    float safeCMax = min(cMax, 16.0);
    float scene = safeCMax <= 0.5
        ? safeCMax * safeCMax * (1.0 / 3.0)
        : (exp((safeCMax - 0.55991073) / 0.17883277) + 0.28466892) / 12.0;
    float level = sqrt(scene / 0.265);
#else                         // SDR (sRGB)
    float level = cMax;
#endif

    return 1.0 - saturate(cRolloff) * smoothstep(0.0, 1.0, level);
}

float4 PS_SD_ColDensity(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float4 src = tex2D(ReShade::BackBuffer, texcoord);

    [branch]
    if (cAmount <= 0.0)
        return src;

    // Symmetric FP16 clamp prevents Inf/NaN while preserving negative wide-gamut coordinates
    float3 safeSrc = clamp(src.rgb, -65504.0, 65504.0);
    float3 color = max(safeSrc, 0.0);
    float cMax = max(color.r, max(color.g, color.b));
    float chroma = cMax - min(color.r, min(color.g, color.b));

    [branch]
    if (chroma <= 1e-7)
        return src;

    float rcpMax = rcp(cMax);
    float mean = (color.r + color.g + color.b) * (1.0 / 3.0);
    float rawDrop = chroma * rcpMax * (0.20 + 0.75 * (1.0 - mean * rcpMax));

    float k1 = 1.0 - rawDrop;
    float effDrop = (cAmount <= 1.0)
        ? rawDrop * cAmount
        : 1.0 - (k1 * k1) / (k1 + rawDrop * (cAmount - 1.0));

    float rolloff = 1.0;
    [branch]
    if (cRolloff > 0.0)
        rolloff = Rolloff(cMax);

    return float4(safeSrc * (1.0 - effDrop * rolloff), src.a);
}

technique SD_ColDensity <
    ui_label = "SD Color Density";
    ui_tooltip = "Darkens saturated colors by scaling RGB uniformly to keep hues and neutral tones unchanged.";
>
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_SD_ColDensity;
    }
}
