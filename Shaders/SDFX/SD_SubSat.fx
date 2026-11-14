// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Starodubysko (https://github.com/Starodubysko/sd-reshade-shaders)

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
    ui_tooltip = "Decreases the effect gradually toward bright areas.\nAt 1, reference white and specular highlights remain unchanged.";
> = 0.00;

// Target nits for scRGB and HDR10 (ITU-R BT.2408 default)
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3
    #ifndef SD_REFERENCE_WHITE
        #define SD_REFERENCE_WHITE 203.0
    #endif
#endif

#if BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
// Per-channel saturation math runs in BT.709 so wide-gamut primaries behave like SDR
float3 Bt2020ToBt709(float3 c)
{
    return float3(
        dot(c, float3( 1.6604910, -0.5876411, -0.0728499)),
        dot(c, float3(-0.1245505,  1.1328999, -0.0083494)),
        dot(c, float3(-0.0181508, -0.1005789,  1.1187297))
    );
}

float3 Bt709ToBt2020(float3 c)
{
    return float3(
        dot(c, float3(0.6274039, 0.3292830, 0.0433131)),
        dot(c, float3(0.0690973, 0.9195404, 0.0113623)),
        dot(c, float3(0.0163914, 0.0880133, 0.8955953))
    );
}
#endif

// Guard 0 avoids Inf/NaN from pow()
float3 SafePow(float3 x, float e)
{
    return x > 0.0 ? pow(max(x, 1e-30), e) : 0.0;
}

#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
// Sign-preserving slope-matched sRGB transfer, extended above 1 for HDR
float3 LinearToSrgb(float3 l)
{
    float3 a = abs(l);
    return (l >= 0.0 ? 1.0 : -1.0) * (a <= 0.003039935
        ? a * 12.9232102
        : 1.055 * SafePow(a, 1.0 / 2.4) - 0.055);
}

float3 SrgbToLinear(float3 v)
{
    float3 a = abs(v);
    return (v >= 0.0 ? 1.0 : -1.0) * (a <= 0.039285714
        ? a * (1.0 / 12.9232102)
        : SafePow((a + 0.055) / 1.055, 2.4));
}

float3 ToLinear(float3 c)
{
#if BUFFER_COLOR_SPACE == 2   // scRGB
    return c * (80.0 / max(SD_REFERENCE_WHITE, 1.0));
#elif BUFFER_COLOR_SPACE == 3 // HDR10 (PQ)
    float3 p = SafePow(saturate(c), 1.0 / 78.84375);
    float3 num = max(p - 0.8359375, 0.0);
    float3 den = max(18.8515625 - 18.6875 * p, 1e-6);
    float3 lin = SafePow(num / den, 1.0 / 0.1593017578125);
    return Bt2020ToBt709(lin * (10000.0 / max(SD_REFERENCE_WHITE, 1.0)));
#else                         // HLG (0.265 scene light matches BT.2408 reference white)
    float3 e = saturate(c);
    float3 scene = e <= 0.5
        ? e * e * (1.0 / 3.0)
        : (exp((e - 0.55991073) / 0.17883277) + 0.28466892) * (1.0 / 12.0);
    return Bt2020ToBt709(scene * (1.0 / 0.265));
#endif
}

float3 FromLinear(float3 lin)
{
#if BUFFER_COLOR_SPACE == 2   // scRGB
    return clamp(lin * (max(SD_REFERENCE_WHITE, 1.0) / 80.0), -65504.0, 65504.0);
#elif BUFFER_COLOR_SPACE == 3 // HDR10 (PQ)
    float3 bt2020 = saturate(Bt709ToBt2020(lin) * (max(SD_REFERENCE_WHITE, 1.0) / 10000.0));
    float3 y = SafePow(bt2020, 0.1593017578125);
    float3 pq = SafePow((0.8359375 + 18.8515625 * y) / (1.0 + 18.6875 * y), 78.84375);
    return bt2020 > 0.0 ? pq : 0.0;
#else                         // HLG
    float3 scene = max(Bt709ToBt2020(lin) * 0.265, 0.0);
    return scene <= (1.0 / 12.0)
        ? sqrt(3.0 * scene)
        : 0.17883277 * log(max(12.0 * scene - 0.28466892, 1e-7)) + 0.55991073;
#endif
}
#endif

float4 PS_SD_SubSat(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float4 src = tex2D(ReShade::BackBuffer, texcoord);

    [branch]
    if (cAmount <= 0.0)
        return src;

    float amt = min(cAmount, 65504.0);
    // FP16 bounds prevent Inf/NaN
    float3 safeSrc = clamp(src.rgb, -65504.0, 65504.0);

#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
    float3 lin = ToLinear(safeSrc);
    float3 work = LinearToSrgb(lin);
    float3 negLin = min(lin, 0.0);
#else
    float3 work = safeSrc;
    float3 neg = min(work, 0.0);
#endif

    float3 color = max(work, 0.0);
    float cMax = max(color.r, max(color.g, color.b));
    float chroma = cMax - min(color.r, min(color.g, color.b));

    [branch]
    if (chroma <= max(1e-7, 1e-5 * cMax))
        return float4(safeSrc, src.a);

    float w = 1.0 - saturate(cRolloff) * smoothstep(0.0, 1.0, cMax);
    [branch]
    if (w <= 0.0)
        return float4(safeSrc, src.a);

    float rcpMax = rcp(cMax);
    float3 cNorm = color * rcpMax;
    float3 outColor;

    [branch]
    if (cTechnique == 0) // Subtle
    {
        float sat = chroma * rcpMax;
        float3 drop = (0.60 + 1.30 * (1.0 - cNorm)) * amt;
        outColor = color * rcp(1.0 + sat * drop);
    }
    else [branch] if (cTechnique == 1) // Balanced
    {
        float3 safeNorm = max(cNorm, 1e-7);
        float rootMean = (sqrt(cNorm.r) + sqrt(cNorm.g) + sqrt(cNorm.b)) * (1.0 / 3.0);
        float density = rootMean * rootMean;

        outColor = cMax * rcp(1.0 + 1.50 * amt * (1.0 - density))
                 * SafePow(safeNorm, 1.0 + 0.55 * amt);
    }
    else // Intense
    {
        float3 safeNorm = max(cNorm, 1e-7);
        float density = 3.0 / (1.0 / safeNorm.r + 1.0 / safeNorm.g + 1.0 / safeNorm.b);

        outColor = cMax * rcp(1.0 + 2.00 * amt * (1.0 - density))
                 * SafePow(safeNorm, 1.0 + 0.80 * amt);
    }

    float3 resWork = lerp(color, outColor, w);

#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
    // Scale out-of-gamut negative linear channels uniformly so wide-gamut primaries keep hue
    float3 outPosLin = SrgbToLinear(resWork);
    float cMaxLin = max(lin.r, max(lin.g, lin.b));
    float linGain = max(outPosLin.r, max(outPosLin.g, outPosLin.b)) * rcp(max(cMaxLin, 1e-30));
    return float4(FromLinear(outPosLin + negLin * linGain), src.a);
#else
    float gain = max(outColor.r, max(outColor.g, outColor.b)) * rcpMax;
    return float4(resWork + neg * lerp(1.0, gain, w), src.a);
#endif
}

technique SD_SubSat <
    ui_label = "SD Subtractive Saturation";
    ui_tooltip = "Decreases brightness as saturation increases to keep colors dense.";
>
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_SD_SubSat;
    }
}
