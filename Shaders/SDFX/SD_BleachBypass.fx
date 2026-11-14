// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Starodubysko (https://github.com/Starodubysko/sd-reshade-shaders)

#include "ReShade.fxh"

uniform int cTechnique <
    ui_type = "combo";
    ui_items = "Subtle\0Balanced\0Intense\0Color\0";
    ui_label = "Technique";
    ui_tooltip = "Subtle protects warm amber and skin tones while muting green and cyan hues with gentle shadow compression.\nBalanced deepens shadows and lower midtones with uniform desaturation and color darkening.\nIntense combines deep shadows, lifted upper midtones and strong desaturation.\nColor skips neutral contrast and applies only desaturation, color darkening and Tone to pair with SD Contrast.";
> = 0;

uniform float cAmount <
    ui_type = "slider";
    ui_min = 0.00;
    ui_max = 1.00;
    ui_step = 0.05;
    ui_label = "Amount";
    ui_tooltip = "Sets contrast and desaturation strength.\nCtrl+Click to enter values greater than 1.";
> = 0.50;

uniform int cTone <
    ui_type = "combo";
    ui_items = "Neutral\0Cool\0Warm\0Emerald\0";
    ui_label = "Tone";
    ui_tooltip = "Tints shadows and midtones while keeping pure black and reference white neutral.";
> = 0;

uniform float cToneAmount <
    ui_type = "slider";
    ui_min = 0.00;
    ui_max = 1.00;
    ui_step = 0.05;
    ui_label = "Tone Amount";
    ui_tooltip = "Sets Tone tint strength.\nCtrl+Click to enter values greater than 1.";
> = 0.50;

// Target nits for scRGB and HDR10 (ITU-R BT.2408 default)
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3
    #ifndef SD_REFERENCE_WHITE
        #define SD_REFERENCE_WHITE 203.0
    #endif
#endif

// ITU-R BT.709 and BT.2020 conversions (D65 white point)
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
float3 Bt709ToBt2020(float3 c)
{
    return float3(
        dot(c, float3(0.6274039, 0.3292830, 0.0433131)),
        dot(c, float3(0.0690973, 0.9195404, 0.0113623)),
        dot(c, float3(0.0163914, 0.0880133, 0.8955953))
    );
}

float3 Bt2020ToBt709(float3 c)
{
    return float3(
        dot(c, float3( 1.6604910, -0.5876411, -0.0728499)),
        dot(c, float3(-0.1245505,  1.1328999, -0.0083494)),
        dot(c, float3(-0.0181508, -0.1005789,  1.1187297))
    );
}
#endif

float3 ToBt709(float3 c)
{
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
    return Bt2020ToBt709(c);
#else
    return c;
#endif
}

// Guard prevents ps_5_0 log2(0) NaN while keeping zero inputs exact
float SafePow(float x, float e)
{
    return (x > 0.0) ? pow(max(x, 1e-30), e) : 0.0;
}

float3 SafePow(float3 x, float e)
{
    return float3(
        SafePow(x.r, e),
        SafePow(x.g, e),
        SafePow(x.b, e)
    );
}

// Sign-preserving slope-matched sRGB constants prevent the IEC shadow slope kink
float LinearToSrgb(float l)
{
    float a = abs(l);
    float s = (l >= 0.0) ? 1.0 : -1.0;
    float y = (a <= 0.003039935) ? (a * 12.9232102) : (1.055 * SafePow(a, 1.0 / 2.4) - 0.055);
    return s * y;
}

float SrgbToLinear(float v)
{
    float a = abs(v);
    float s = (v >= 0.0) ? 1.0 : -1.0;
    float y = (a <= 0.039285714) ? (a * (1.0 / 12.9232102)) : SafePow((a + 0.055) / 1.055, 2.4);
    return s * y;
}

#if BUFFER_COLOR_SPACE != 2 && BUFFER_COLOR_SPACE != 3 && BUFFER_COLOR_SPACE != 4
float3 LinearToSrgb(float3 l)
{
    return float3(LinearToSrgb(l.r), LinearToSrgb(l.g), LinearToSrgb(l.b));
}

float3 SrgbToLinear(float3 v)
{
    return float3(SrgbToLinear(v.r), SrgbToLinear(v.g), SrgbToLinear(v.b));
}
#endif

// Linear working light normalized to reference white: BT.709 in SDR, BT.2020 in HDR
float3 ToWorkLinear(float3 encoded)
{
#if BUFFER_COLOR_SPACE == 2   // scRGB
    return Bt709ToBt2020(encoded * (80.0 / max(SD_REFERENCE_WHITE, 1.0)));
#elif BUFFER_COLOR_SPACE == 3 // HDR10 (PQ)
    float3 p = SafePow(saturate(encoded), 1.0 / 78.84375);
    float3 n = max(p - 0.8359375, 0.0) / max(18.8515625 - 18.6875 * p, 1e-6);
    float3 l = SafePow(n, 1.0 / 0.1593017578125);
    return l * (10000.0 / max(SD_REFERENCE_WHITE, 1.0));
#elif BUFFER_COLOR_SPACE == 4 // HLG (0.265 scene light matches BT.2408 reference white)
    float3 e = saturate(encoded);
    float3 hi = (exp((e - 0.55991073) / 0.17883277) + 0.28466892) * (1.0 / 12.0);
    float3 scene = float3(
        (e.r <= 0.5) ? (e.r * e.r * (1.0 / 3.0)) : hi.r,
        (e.g <= 0.5) ? (e.g * e.g * (1.0 / 3.0)) : hi.g,
        (e.b <= 0.5) ? (e.b * e.b * (1.0 / 3.0)) : hi.b
    );
    return scene * (1.0 / 0.265);
#else                         // SDR (sRGB)
    return SrgbToLinear(encoded);
#endif
}

float3 FromWorkLinear(float3 workLin)
{
#if BUFFER_COLOR_SPACE == 2   // scRGB
    return clamp(Bt2020ToBt709(workLin) * (max(SD_REFERENCE_WHITE, 1.0) / 80.0), -65504.0, 65504.0);
#elif BUFFER_COLOR_SPACE == 3 // HDR10 (PQ)
    float3 l = saturate(workLin * (max(SD_REFERENCE_WHITE, 1.0) / 10000.0));
    float3 y = SafePow(l, 0.1593017578125);
    float3 pq = SafePow((0.8359375 + 18.8515625 * y) / (1.0 + 18.6875 * y), 78.84375);
    // Keep pure zero exact instead of returning PQ's min sub-threshold floor
    return float3(
        (l.r > 0.0) ? pq.r : 0.0,
        (l.g > 0.0) ? pq.g : 0.0,
        (l.b > 0.0) ? pq.b : 0.0
    );
#elif BUFFER_COLOR_SPACE == 4 // HLG
    float3 scene = max(workLin, 0.0) * 0.265;
    float3 lo = sqrt(3.0 * scene);
    float3 hi = 0.17883277 * log(max(12.0 * scene - 0.28466892, 1e-7)) + 0.55991073;
    return float3(
        (scene.r <= (1.0 / 12.0)) ? lo.r : hi.r,
        (scene.g <= (1.0 / 12.0)) ? lo.g : hi.g,
        (scene.b <= (1.0 / 12.0)) ? lo.b : hi.b
    );
#else                         // SDR (sRGB)
    return LinearToSrgb(workLin);
#endif
}

float WorkLuma(float3 c)
{
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
    return dot(c, float3(0.2627, 0.6780, 0.0593));
#else
    return dot(c, float3(0.2126, 0.7152, 0.0722));
#endif
}

// Panchromatic silver weights (boosted red/blue vs Rec.709, transformed into BT.2020 in HDR)
float SilverLuma(float3 c)
{
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
    return dot(c, float3(0.422253, 0.390979, 0.186768));
#else
    return dot(c, float3(0.295000, 0.515000, 0.190000));
#endif
}

float Max3(float3 c)
{
    return max(c.r, max(c.g, c.b));
}

float Min3(float3 c)
{
    return min(c.r, min(c.g, c.b));
}

float EvalTail(float y, float m1, float k)
{
    float x = y - 1.0;
    return y + (m1 - 1.0) * (x / (1.0 + k * x));
}

// Analytical zero-limit slope keeps dim shadows positive and continuous below the key floor
float SlopeZero(float effAmt, int tech)
{
    if (tech == 3)
        return 1.0;
    if (tech == 0)
        return 1.0 - effAmt * 0.44;
    float d = (tech == 1) ? (1.55 * effAmt) : (2.65 * effAmt);
    return rcp(1.0 + d);
}

float EvalCurve(float y, float effAmt, int tech)
{
    if (y <= 0.0)
        return 0.0;
    [branch]
    if (tech == 3)
        return y;

    float m1 = (tech == 0) ? (1.0 - effAmt * 0.44) : (1.0 - ((tech == 1) ? 0.50 : 0.60) * effAmt);
    [branch]
    if (y > 1.0)
        return EvalTail(y, m1, 0.75);

    float s = LinearToSrgb(y);
    float u = 1.0 - s;

    [branch]
    if (tech == 0) // Subtle: protective toe slope with gentle upper-mid contrast
    {
        float w = effAmt * 0.44;
        float p = 0.52;
        float k = 1.0 + 0.85 * effAmt;
        float sp = SafePow(s, k);
        float qp = (s < 1.0) ? SafePow(u * (p / (1.0 - p)), k) : 0.0;
        float sc = ((sp + qp) > 0.0) ? (sp / (sp + qp)) : 0.0;
        return SrgbToLinear(lerp(s, sc, w));
    }
    else [branch] if (tech == 1) // Balanced: rational toe darkening (D) with mild upper-mid slope reduction (B)
    {
        float B = 0.50 * effAmt;
        float D = 1.55 * effAmt;
        return SrgbToLinear(s * (1.0 + B * s * u) / (1.0 + D * u * u));
    }
    else // Intense: deep shadow toe (D) and upper-mid boost (M) with higher highlight slope flattening (B)
    {
        float B = 0.60 * effAmt;
        float D = 2.65 * effAmt;
        float M = 2.15 * effAmt;
        float denom = 1.0 + D * (0.50 * u * u + 0.50 * u * u * u);
        return SrgbToLinear(s * (1.0 + B * s * u + M * s * s * u * u) / denom);
    }
}

float Overdrive(float x)
{
    return (x <= 1.0) ? x : (1.0 + 0.40 * ((x - 1.0) / (x - 0.60)));
}

float3 ApplyToneCast(float3 cWork, float yWork, float effTone, int toneMode)
{
    if (toneMode == 0 || yWork <= 0.0)
        return cWork;

    float s = LinearToSrgb(saturate(yWork));
    float3 shadowTint;
    float3 midTint;
    float shExp = 1.65;
    float wMidScale = 0.70;
    float wShScale = 0.92;

    // Luminance-normalized BT.709 shadow and midtone multipliers (transformed to BT.2020 in HDR)
    if (toneMode == 1) // Cool: steel cobalt-cyan tint
    {
        shadowTint = float3(0.78427, 1.01743, 1.46256);
        midTint    = float3(0.93448, 1.00558, 1.13763);
    }
    else if (toneMode == 2) // Warm: selenium-amber tint
    {
        shadowTint = float3(1.22587, 0.97291, 0.60321);
        midTint    = float3(1.07260, 0.99315, 0.85411);
    }
    else // Emerald: cyan-green shadow tint (all modes taper to 1.0 at reference white and above)
    {
        shadowTint = float3(0.61937, 1.11060, 1.02517);
        midTint    = float3(1.00291, 1.01274, 0.86525);
        shExp = 2.10;
        wMidScale = 0.65;
        wShScale = 0.90;
    }

#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
    shadowTint = Bt709ToBt2020(shadowTint);
    midTint    = Bt709ToBt2020(midTint);
#endif

    float u = 1.0 - s;
    float wSh = SafePow(u, shExp);
    float wMid = 4.0 * s * u * u;
    float3 combined = lerp(float3(1.0, 1.0, 1.0), midTint, saturate(wMid * wMidScale));
    combined = lerp(combined, shadowTint, saturate(wSh * wShScale));
    return cWork * lerp(float3(1.0, 1.0, 1.0), combined, effTone);
}

// Smooth C1 cap above 0.86 prevents overdrive desaturation from hard-clipping at 1.0
float SoftCap86(float x)
{
    return (x <= 0.86) ? x : (0.86 + 0.14 * ((x - 0.86) / (x - 0.72)));
}

float4 PS_SD_BleachBypass(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float4 src = tex2D(ReShade::BackBuffer, texcoord);
    float rawAmt = clamp(cAmount, 0.0, 65504.0);
    int toneMode = clamp(cTone, 0, 3);
    float rawToneAmt = clamp(cToneAmount, 0.0, 65504.0);
    float effTone = (toneMode != 0 && rawToneAmt > 0.0) ? Overdrive(rawToneAmt) : 0.0;

    [branch]
    if (rawAmt <= 0.0 && effTone <= 0.0)
        return src;

    int tech = clamp(cTechnique, 0, 3);
    float effAmt = Overdrive(rawAmt);

    float3 workLin = ToWorkLinear(clamp(src.rgb, -65504.0, 65504.0));
    float3 pos = max(workLin, 0.0);
    float3 neg = workLin - pos;

    float gain = 1.0;
    float desat = 0.0;
    float3 outWork = pos;

    [branch]
    if (rawAmt > 0.0)
    {
        // Evaluate key norm and saturation in shared BT.709 basis for SDR/HDR chromatic parity,
        // normalized by dominant scale to avoid FP32 overflow or subnormal flush
        float3 pos709 = ToBt709(pos);
        float yPos = WorkLuma(pos);
        float keyScale = max(yPos, max(abs(pos709.r), max(abs(pos709.g), abs(pos709.b))));
        float3 pn = (keyScale > 0.0) ? (pos709 / keyScale) : 0.0;
        float yn = (keyScale > 0.0) ? (yPos / keyScale) : 0.0;
        float key = keyScale * sqrt(0.5 * dot(pn, pn) * (1.0 / 3.0) + 0.5 * yn * yn);

        [branch]
        if (tech != 3)
        {
            float targetKey = EvalCurve(key, effAmt, tech);
            gain = (key > 1e-12) ? (targetKey / key) : SlopeZero(effAmt, tech);
        }

        float3 contrasted = pos * gain;
        float3 c709 = max(ToBt709(contrasted), 0.0);
        float c7Max = Max3(c709);
        float c7Min = Min3(c709);
        float chroma7 = c7Max - c7Min;
        float sat = (c7Max > 1e-12) ? saturate(chroma7 / c7Max) : 0.0;

        float sLuma = LinearToSrgb(saturate(yPos * gain));
        float mSilver = SilverLuma(contrasted);

        float darken;

        [branch]
        if (tech == 0) // Subtle: asymmetric BT.709 hue gate protecting warm amber/skin tones
        {
            float invChroma = (chroma7 > 1e-5 * c7Max) ? rcp(chroma7) : 0.0;
            float warmHue = saturate((c709.r - c709.g) * invChroma) * saturate((c709.r - c709.b) * invChroma);
            float greenHue = saturate((c709.g - c709.b) * invChroma) * saturate((c709.g - c709.r) * invChroma + 0.15);
            float hueMod = 1.0 - 0.42 * warmHue + 0.18 * greenHue;

            desat = saturate(0.58 * hueMod * effAmt * (1.0 - 0.16 * smoothstep(0.65, 1.0, sLuma)));
            darken = 1.0 - 0.14 * effAmt * sat * (1.0 - 0.40 * warmHue);
        }
        else [branch] if (tech == 2) // Intense: strong desaturation and darkening with highlight protection
        {
            desat = SoftCap86(0.86 * effAmt * (1.0 - 0.14 * smoothstep(0.78, 1.0, sLuma)));
            darken = max(1.0 - 0.30 * effAmt * sat * (1.0 - 0.40 * smoothstep(0.55, 1.0, sLuma)), 0.52);
        }
        else // Balanced (1) and Color (3) share uniform desaturation and highlight-protected darkening
        {
            desat = saturate(0.68 * effAmt * (1.0 - 0.22 * smoothstep(0.65, 1.0, sLuma)));
            darken = max(1.0 - 0.20 * effAmt * sat * (1.0 - 0.55 * smoothstep(0.45, 1.0, sLuma)), 0.60);
        }

        // Darken saturated colors alongside desaturation so high-chroma hues remain dense
        outWork = lerp(contrasted, mSilver * darken, desat);
    }

    [branch]
    if (effTone > 0.0)
        outWork = ApplyToneCast(outWork, WorkLuma(outWork), effTone, toneMode);

#if BUFFER_COLOR_SPACE != 2 && BUFFER_COLOR_SPACE != 3 && BUFFER_COLOR_SPACE != 4
    // Saturation-gated SDR headroom compression preserves neutral white 1.0 exactly and keeps a C1 tail
    float inMax = Max3(pos);
    float ceiling = 1.0;
    [branch]
    if (inMax > 1.0)
        ceiling = EvalCurve(inMax, effAmt, tech);

    float outMax = Max3(outWork);
    float outMin = Min3(outWork);
    float outSat = (outMax > 1e-12) ? saturate((outMax - outMin) / outMax) : 0.0;
    float cap = ceiling * (1.0 - 0.06 * outSat * saturate(max(effAmt, effTone)));
    float over = max(outMax - cap, 0.0);
    if (over > 0.0)
    {
        float span = ceiling - cap;
        float t = (span > 1e-7) ? (cap + span * (over / (over + span))) : ceiling;
        outWork *= (t / outMax);
    }
#endif

    // Scale negative out-of-gamut scRGB channels proportionally with contrast and remaining saturation
    return float4(FromWorkLinear(outWork + neg * (gain * (1.0 - desat))), src.a);
}

technique SD_BleachBypass <
    ui_label = "SD Bleach Bypass";
    ui_tooltip = "Increases contrast, deepens shadows and mutes color for a bleach-bypass film look.";
>
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_SD_BleachBypass;
    }
}
