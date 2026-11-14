// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Starodubysko (https://github.com/Starodubysko/sd-reshade-shaders)

#include "ReShade.fxh"

uniform int cTechnique <
    ui_type = "combo";
    ui_items = "Luma\0RGB\0";
    ui_label = "Technique";
    ui_tooltip = "Luma darkens RGB uniformly to keep hue and saturation.\nRGB darkens each channel separately to increase saturation in shadows.";
> = 0;

uniform float cAmount <
    ui_type = "slider";
    ui_min = 0.00;
    ui_max = 1.00;
    ui_step = 0.05;
    ui_label = "Amount";
    ui_tooltip = "Ctrl+Click to enter values greater than 1.";
> = 0.50;

uniform float cRange <
    ui_type = "slider";
    ui_min = 0.00;
    ui_max = 1.00;
    ui_step = 0.05;
    ui_label = "Range";
    ui_tooltip = "Sets how far the effect extends from deep shadows toward midtones.";
> = 0.50;

uniform float cBlackPoint <
    ui_type = "slider";
    ui_min = 0.00;
    ui_max = 1.00;
    ui_step = 0.05;
    ui_label = "Black Point";
    ui_tooltip = "Lowers washed-out black levels to zero.\nHigh values clip near-black detail.";
> = 0.00;

// Target nits for scRGB and HDR10 (ITU-R BT.2408 default)
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3
    #ifndef SD_REFERENCE_WHITE
        #define SD_REFERENCE_WHITE 203.0
    #endif
#endif

#if BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
// Shadow range and per-channel darkening are defined on BT.709 primaries, as in SDR
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
float SafePow(float x, float e)
{
    return x > 0.0 ? pow(max(x, 1e-30), e) : 0.0;
}

float3 SafePow(float3 x, float e)
{
    return x > 0.0 ? pow(max(x, 1e-30), e) : 0.0;
}

// Sign-preserving sRGB transfer with slope-matched segments: the IEC 0.04045 / 12.92
// junction has a slope kink that sits inside the shadow range
float SrgbToLinear(float v)
{
    float a = abs(v);
    return (v >= 0.0 ? 1.0 : -1.0) * (a <= 0.039285714
        ? a * (1.0 / 12.9232102)
        : SafePow((a + 0.055) / 1.055, 2.4));
}

float3 SrgbToLinear(float3 v)
{
    float3 a = abs(v);
    return (v >= 0.0 ? 1.0 : -1.0) * (a <= 0.039285714
        ? a * (1.0 / 12.9232102)
        : SafePow((a + 0.055) / 1.055, 2.4));
}

float LinearToSrgb(float l)
{
    float a = abs(l);
    return (l >= 0.0 ? 1.0 : -1.0) * (a <= 0.003039935
        ? a * 12.9232102
        : 1.055 * SafePow(a, 1.0 / 2.4) - 0.055);
}

float3 LinearToSrgb(float3 l)
{
    float3 a = abs(l);
    return (l >= 0.0 ? 1.0 : -1.0) * (a <= 0.003039935
        ? a * 12.9232102
        : 1.055 * SafePow(a, 1.0 / 2.4) - 0.055);
}

// BT.709 linear light, 1 = reference white; SDR stays unclamped for float buffers
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
#elif BUFFER_COLOR_SPACE == 4 // HLG (0.265 scene light matches BT.2408 reference white)
    float3 e = saturate(c);
    float3 scene = e <= 0.5
        ? e * e * (1.0 / 3.0)
        : (exp((e - 0.55991073) / 0.17883277) + 0.28466892) * (1.0 / 12.0);
    return Bt2020ToBt709(scene * (1.0 / 0.265));
#else                         // SDR (sRGB)
    return SrgbToLinear(c);
#endif
}

float3 FromLinear(float3 l)
{
#if BUFFER_COLOR_SPACE == 2   // scRGB
    return clamp(l * (max(SD_REFERENCE_WHITE, 1.0) / 80.0), -65504.0, 65504.0);
#elif BUFFER_COLOR_SPACE == 3 // HDR10 (PQ)
    float3 bt2020 = saturate(Bt709ToBt2020(l) * (max(SD_REFERENCE_WHITE, 1.0) / 10000.0));
    float3 y = SafePow(bt2020, 0.1593017578125);
    float3 pq = SafePow((0.8359375 + 18.8515625 * y) / (1.0 + 18.6875 * y), 78.84375);
    return bt2020 > 0.0 ? pq : 0.0;
#elif BUFFER_COLOR_SPACE == 4 // HLG
    float3 scene = max(Bt709ToBt2020(l) * 0.265, 0.0);
    return scene <= (1.0 / 12.0)
        ? sqrt(3.0 * scene)
        : 0.17883277 * log(max(12.0 * scene - 0.28466892, 1e-7)) + 0.55991073;
#else                         // SDR (sRGB)
    return LinearToSrgb(l);
#endif
}

// Darkening weight: 1 at signal 0, 0 at the ceiling with zero first and second derivatives
float Weight(float s, float p, float rcpP)
{
    float u = saturate((p - s) * rcpP);
    return (u * u * u) * (u * (6.0 * u - 15.0) + 10.0);
}

float3 Weight(float3 s, float p, float rcpP)
{
    float3 u = saturate((p - s) * rcpP);
    return (u * u * u) * (u * (6.0 * u - 15.0) + 10.0);
}

float4 PS_SD_Umbra(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float4 src = tex2D(ReShade::BackBuffer, texcoord);

    [branch]
    if (cAmount <= 0.0 && cBlackPoint <= 0.0)
        return src;

    // FP16 bounds prevent Inf/NaN
    float3 safeRgb = clamp(src.rgb, -65504.0, 65504.0);

    // Shadow ceiling in sRGB signal relative to reference white
    float p = 0.20 + 0.50 * saturate(cRange);

    // Gate on the dominant channel so saturated colors cannot pass as shadows
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
    float3 lin = ToLinear(safeRgb);
    float cMax = max(lin.r, max(lin.g, lin.b));

    [branch]
    if (cMax >= SrgbToLinear(p))
        return src;

    float cPos = max(cMax, 0.0);
    float sPos = LinearToSrgb(cPos);
#else
    float sMax = max(safeRgb.r, max(safeRgb.g, safeRgb.b));

    [branch]
    if (sMax >= p)
        return src;

    float3 lin = ToLinear(safeRgb);
    float cPos = max(max(lin.r, max(lin.g, lin.b)), 0.0);
    float sPos = max(sMax, 0.0);
#endif

    // Linear-light gain 1 - k * w rises from 1 - k at pure black to 1 at the ceiling; gain that
    // grows with level keeps per-channel darkening below or equal to the uniform result
    float rcpP = rcp(p);
    float k = 1.0 - rcp(1.0 + 2.5 * clamp(cAmount, 0.0, 65504.0));

    // Black Point offset scaled by w pulls dark tones down to 0 and joins smoothly at p
    float b = min(clamp(cBlackPoint, 0.0, 65504.0) * 0.08, 0.5 * p);
    float wb = Weight(b, p, rcpP);
    float beta = SrgbToLinear(b) * (rcp(wb) - k);

    float w = Weight(sPos, p, rcpP);

    // Uniform linear gain; clamping cPos avoids 0 * Inf at pure black when beta == 0
    float gain = max(1.0 - (k + beta * rcp(max(cPos, 1e-12))) * w, 0.0);
    float3 outLin = lin * gain;

    [branch]
    if (cTechnique == 1) // RGB
    {
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
        float3 sig = LinearToSrgb(max(lin, 0.0));
#else
        float3 sig = max(safeRgb, 0.0);
#endif
        float3 wc = Weight(sig, p, rcpP);

        // Negative wide-gamut channels follow the uniform gain
        float3 rgbLin = max(max(lin, 0.0) * (1.0 - k * wc) - beta * wc, 0.0) + min(lin, 0.0) * gain;

        // Fades to the uniform result over the upper half of the range so chromatic gradients stay C1
        float t = saturate((p - sPos) * rcpP * 2.0);
        outLin = lerp(outLin, rgbLin, t * t * (3.0 - 2.0 * t));
    }

    return float4(FromLinear(outLin), src.a);
}

technique SD_Umbra <
    ui_label = "SD Umbra";
    ui_tooltip = "Deepens shadows and lowers washed-out black levels while keeping midtones and highlights unchanged.";
>
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_SD_Umbra;
    }
}
