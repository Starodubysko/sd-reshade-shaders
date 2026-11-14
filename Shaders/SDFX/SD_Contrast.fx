// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Starodubysko (https://github.com/Starodubysko/sd-reshade-shaders)

#include "ReShade.fxh"

uniform int cTechnique <
    ui_type = "combo";
    ui_items = "Contrast\0Soften\0";
    ui_label = "Technique";
    ui_tooltip = "Contrast darkens shadows and brightens highlights; pure black stays unchanged.\nSoften brightens shadows and lowers highlights without lifting pure black.";
> = 0;

uniform float cAmount <
    ui_type = "slider";
    ui_min = 0.00;
    ui_max = 1.00;
    ui_step = 0.05;
    ui_label = "Amount";
    ui_tooltip = "Ctrl+Click to enter values greater than 1.";
> = 0.50;

uniform float cPivot <
    ui_type = "slider";
    ui_min = 0.00;
    ui_max = 1.00;
    ui_step = 0.05;
    ui_label = "Pivot";
    ui_tooltip = "Sets the balance tone; Contrast darkens below it and brightens above it.\nHigher values darken midtones in Contrast and brighten midtones in Soften.";
> = 0.50;

uniform float cRgbMix <
    ui_type = "slider";
    ui_min = 0.00;
    ui_max = 1.00;
    ui_step = 0.05;
    ui_label = "Channel Mix";
    ui_tooltip = "0 keeps original color intensity.\n1 increases color intensity in Contrast and decreases it in Soften.";
> = 0.00;

// Target nits for scRGB and HDR10 (ITU-R BT.2408 default)
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3
    #ifndef SD_REFERENCE_WHITE
        #define SD_REFERENCE_WHITE 203.0
    #endif
#endif

// ITU-R BT.709 and BT.2020 matrices (D65 white point)
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
float3 Bt709ToBt2020(float3 c)
{
    return float3(
        dot(c, float3(0.6274039, 0.3292830, 0.0433131)),
        dot(c, float3(0.0690973, 0.9195404, 0.0113623)),
        dot(c, float3(0.0163914, 0.0880133, 0.8955953))
    );
}
#endif

#if BUFFER_COLOR_SPACE == 2
float3 Bt2020ToBt709(float3 c)
{
    return float3(
        dot(c, float3( 1.6604910, -0.5876411, -0.0728499)),
        dot(c, float3(-0.1245505,  1.1328999, -0.0083494)),
        dot(c, float3(-0.0181508, -0.1005789,  1.1187297))
    );
}
#endif

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

// Sign-preserving slope-matched sRGB transfer prevents IEC shadow slope kink
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
    float y = (a <= 0.039285714) ? (a / 12.9232102) : SafePow((a + 0.055) / 1.055, 2.4);
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
float3 ToWorkLinear(float3 c)
{
#if BUFFER_COLOR_SPACE == 2   // scRGB
    return Bt709ToBt2020(c * (80.0 / max(SD_REFERENCE_WHITE, 1.0)));
#elif BUFFER_COLOR_SPACE == 3 // HDR10 (PQ)
    float3 p = SafePow(saturate(c), 1.0 / 78.84375);
    float3 num = max(p - 0.8359375, 0.0);
    float3 den = max(18.8515625 - 18.6875 * p, 1e-6);
    float3 lin = SafePow(num / den, 1.0 / 0.1593017578125);
    return lin * (10000.0 / max(SD_REFERENCE_WHITE, 1.0));
#elif BUFFER_COLOR_SPACE == 4 // HLG (0.265 scene light matches BT.2408 reference white)
    float3 e = saturate(c);
    float3 hi = (exp((e - 0.55991073) / 0.17883277) + 0.28466892) / 12.0;
    float3 scene = float3(
        (e.r <= 0.5) ? (e.r * e.r * (1.0 / 3.0)) : hi.r,
        (e.g <= 0.5) ? (e.g * e.g * (1.0 / 3.0)) : hi.g,
        (e.b <= 0.5) ? (e.b * e.b * (1.0 / 3.0)) : hi.b
    );
    return scene * (1.0 / 0.265);
#else                         // SDR (sRGB)
    return SrgbToLinear(c);
#endif
}

float3 FromWorkLinear(float3 l)
{
#if BUFFER_COLOR_SPACE == 2   // scRGB
    return clamp(Bt2020ToBt709(l) * (max(SD_REFERENCE_WHITE, 1.0) / 80.0), -65504.0, 65504.0);
#elif BUFFER_COLOR_SPACE == 3 // HDR10 (PQ)
    float3 bt2020 = saturate(l * (max(SD_REFERENCE_WHITE, 1.0) / 10000.0));
    float3 y = SafePow(bt2020, 0.1593017578125);
    float3 pq = SafePow((0.8359375 + 18.8515625 * y) / (1.0 + 18.6875 * y), 78.84375);
    return bt2020 > 0.0 ? pq : 0.0;
#elif BUFFER_COLOR_SPACE == 4 // HLG
    float3 scene = max(l * 0.265, 0.0);
    float3 lo = sqrt(3.0 * scene);
    float3 hi = 0.17883277 * log(max(12.0 * scene - 0.28466892, 1e-7)) + 0.55991073;
    return float3(
        (scene.r <= (1.0 / 12.0)) ? lo.r : hi.r,
        (scene.g <= (1.0 / 12.0)) ? lo.g : hi.g,
        (scene.b <= (1.0 / 12.0)) ? lo.b : hi.b
    );
#else                         // SDR (sRGB)
    return LinearToSrgb(l);
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

// Cancellation-free Mobius-warped algebraic sigmoid and exact inverse on sRGB signal [0, 1]
float CurveSignal(float s, float k, float p, bool isSoften)
{
    float denom = (1.0 - 2.0 * p) * s + p;
    float rcpDen = rcp(denom);
    float u = (1.0 - p) * s * rcpDen;
    float v = p * (1.0 - s) * rcpDen;
    float t = (s - p) * rcpDen;
    float absT = abs(t);

    // Denominators stay at least 1.0 to prevent movc 0/0 NaN on untaken SIMD lanes
    float edge;
    if (isSoften)
    {
        float d = sqrt(1.0 + 4.0 * k * u * v);
        edge = (2.0 * (1.0 + k) * u * v) * rcp(d * (d + absT));
    }
    else
    {
        float a = sqrt(1.0 + k) * absT;
        float b = sqrt(1.0 + k * t * t);
        edge = (2.0 * u * v) * rcp(b * (b + a));
    }

    float up = (t < 0.0) ? edge : (1.0 - edge);
    float vp = (t < 0.0) ? (1.0 - edge) : edge;
    return (p * up) * rcp(p * up + (1.0 - p) * vp);
}

// Diffuse [0, 1] runs in sRGB signal space; values above 1.0 use a C1 monotonic specular tail
float EvalCurve(float x, float k, float p, float m1, bool isSoften)
{
    if (x > 1.0)
    {
        float d = x - 1.0;
        float t = 1.0 + 2.5 * d;
        return x + (m1 - 1.0) * d * rcp(t * t);
    }
    float s = LinearToSrgb(saturate(x));
    return SrgbToLinear(CurveSignal(s, k, p, isSoften));
}

float4 PS_SD_Contrast(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float4 src = tex2D(ReShade::BackBuffer, texcoord);

    [branch]
    if (cAmount <= 0.0)
        return src;

    // FP16 bounds prevent Inf/NaN propagation
    float3 safeRgb = clamp(src.rgb, -65504.0, 65504.0);
    float3 lin = ToWorkLinear(safeRgb);

    bool isSoften = (cTechnique != 0);
    float amt = max(cAmount, 0.0);
    float k = 2.0 * amt * rcp(1.0 + amt);
    float p = 0.22 + 0.50 * saturate(cPivot);
    float m1 = isSoften ? (1.0 + k) : rcp(1.0 + k);
    float mixVal = saturate(cRgbMix);
    float minChan = min(lin.r, min(lin.g, lin.b));

    float lumaGain = m1;
    float3 lumaLin = lin;

    [branch]
    if (mixVal < 1.0 || minChan <= 0.0)
    {
        float yPos = max(WorkLuma(lin), 0.0);
        float meanSq = dot(lin, lin) * (1.0 / 3.0);
        float keyLin = sqrt(0.5 * meanSq + 0.5 * yPos * yPos);
        lumaGain = (keyLin > 1e-6) ? (EvalCurve(keyLin, k, p, m1, isSoften) * rcp(keyLin)) : m1;
        lumaLin = lin * lumaGain;

#if BUFFER_COLOR_SPACE != 2 && BUFFER_COLOR_SPACE != 3 && BUFFER_COLOR_SPACE != 4
        // C2 headroom limiter prevents SDR clipping while passing float values above 1.0 smoothly
        float cMax = max(lin.r, max(lin.g, lin.b));
        float ceiling = 1.0 + 2.0 * max(EvalCurve(max(cMax, 1.0), k, p, m1, isSoften) - 1.0, 0.0);
        float3 deltaAll = lumaLin - lin;
        float3 avail = max(ceiling - lin, 1e-12);
        float3 u = max(deltaAll, 0.0) * rcp(avail);
        float uMax = max(u.r, max(u.g, u.b));
        float3 un = (uMax > 0.0) ? (u * rcp(uMax)) : 0.0;
        float3 un2 = un * un;
        float U = uMax * sqrt(sqrt(dot(un2, un2)));
        const float t0 = 0.75;
        if (U > t0)
        {
            float e = (U - t0) * rcp(1.0 - t0);
            float gCap = t0 + (1.0 - t0) * ((e > 1e6) ? 1.0 : (e * rsqrt(1.0 + e * e)));
            lumaLin = lin + (gCap * rcp(U)) * deltaAll;
        }
#endif
    }

    float3 outLin = lumaLin;

    [branch]
    if (mixVal > 0.0)
    {
        float3 rgbLin = float3(
            (lin.r > 0.0) ? EvalCurve(lin.r, k, p, m1, isSoften) : (lin.r * lumaGain),
            (lin.g > 0.0) ? EvalCurve(lin.g, k, p, m1, isSoften) : (lin.g * lumaGain),
            (lin.b > 0.0) ? EvalCurve(lin.b, k, p, m1, isSoften) : (lin.b * lumaGain)
        );
        outLin = (mixVal < 1.0) ? lerp(lumaLin, rgbLin, mixVal) : rgbLin;
    }

    return float4(FromWorkLinear(outLin), src.a);
}

technique SD_Contrast <
    ui_label = "SD Contrast";
    ui_tooltip = "Increases or decreases midtone contrast without lifting pure black.";
>
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_SD_Contrast;
    }
}
