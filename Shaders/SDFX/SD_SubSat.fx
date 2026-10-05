// SPDX-License-Identifier: CC-BY-NC-SA-4.0
// Copyright (c) 2026 Starodubysko (https://github.com/Starodubysko/sd-reshade-shaders)

#define SD_SUBSAT
#include "ReShade.fxh"

uniform int cTechnique <
    ui_type = "combo";
    ui_items = "Subtle\0Balanced\0Intense\0";
    ui_label = "Technique";
> = 0;

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

float4 PS_SD_SubSat(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float4 src = tex2D(ReShade::BackBuffer, texcoord);

    [branch]
    if (cAmount <= 0.0)
        return src;

    // FP16 bounds prevent Inf/NaN while preserving wide-gamut excursions
    float3 color = clamp(src.rgb, 0.0, 65504.0);
    float3 neg = clamp(src.rgb, -65504.0, 0.0);
    float cMax = max(color.r, max(color.g, color.b));
    float chroma = cMax - min(color.r, min(color.g, color.b));

    [branch]
    if (chroma <= 1e-7)
        return src;

    float rcpMax = rcp(cMax);
    float3 cNorm = color * rcpMax;
    float3 outColor;

    [branch]
    if (cTechnique == 0) // Subtle
    {
        float sat = chroma * rcpMax;
        float3 drop = (0.60 + 1.30 * (1.0 - cNorm)) * cAmount;
        outColor = color * rcp(1.0 + sat * drop);
    }
    else if (cTechnique == 1) // Balanced
    {
        float3 safeNorm = max(cNorm, 1e-7);
        float rootMean = (sqrt(cNorm.r) + sqrt(cNorm.g) + sqrt(cNorm.b)) * (1.0 / 3.0);
        float density = rootMean * rootMean;

        outColor = cMax * rcp(1.0 + 1.50 * cAmount * (1.0 - density))
                 * pow(safeNorm, 1.0 + 0.55 * cAmount);
    }
    else // Intense
    {
        float3 safeNorm = max(cNorm, 1e-7);
        float density = 3.0 / (1.0 / safeNorm.r + 1.0 / safeNorm.g + 1.0 / safeNorm.b);

        outColor = cMax * rcp(1.0 + 2.00 * cAmount * (1.0 - density))
                 * pow(safeNorm, 1.0 + 0.80 * cAmount);
    }

    float w = 1.0;
    [branch]
    if (cRolloff > 0.0)
        w = Rolloff(cMax);

    float gain = max(outColor.r, max(outColor.g, outColor.b)) * rcpMax;

    return float4(lerp(color, outColor, w) + neg * lerp(1.0, gain, w), src.a);
}

technique SD_SubSat <
    ui_label = "SD Subtractive Saturation";
    ui_tooltip = "Decreases luminance as chroma increases to keep saturated colors dense.";
>
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_SD_SubSat;
    }
}
