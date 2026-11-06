// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Starodubysko (https://github.com/Starodubysko/sd-reshade-shaders)

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
    ui_tooltip = "Decreases the effect gradually toward bright areas.\nAt 1, reference white and specular highlights remain unchanged.";
> = 0.00;

// Target nits for scRGB and HDR10 (ITU-R BT.2408 default)
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3
    #ifndef SD_REFERENCE_WHITE
        #define SD_REFERENCE_WHITE 203.0
    #endif
#endif

#if BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
// Convert to BT.709 so in-gamut primaries keep a zero minimum channel
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

float3 Decode(float3 c)
{
#if BUFFER_COLOR_SPACE == 2   // scRGB
    return sqrt(max(c, 0.0));
#elif BUFFER_COLOR_SPACE == 3 // HDR10 (PQ)
    float3 p = pow(saturate(c), 1.0 / 78.84375);
    float3 lin = pow(max((p - 0.8359375) / (18.8515625 - 18.6875 * p), 0.0), 1.0 / 0.1593017578125);
    return sqrt(max(Bt2020ToBt709(lin), 0.0));
#elif BUFFER_COLOR_SPACE == 4 // HLG
    float3 e = saturate(c);
    float3 hi = (exp((e - 0.55991073) / 0.17883277) + 0.28466892) / 12.0;
    float3 scene = lerp(hi, e * e * (1.0 / 3.0), step(e, 0.5));
    return sqrt(max(Bt2020ToBt709(scene), 0.0));
#else                         // SDR (sRGB)
    return c;
#endif
}

float3 Encode(float3 w)
{
#if BUFFER_COLOR_SPACE == 2   // scRGB
    return w * w;
#elif BUFFER_COLOR_SPACE == 3 // HDR10 (PQ)
    float3 y = pow(max(Bt709ToBt2020(w * w), 0.0), 0.1593017578125);
    return pow((0.8359375 + 18.8515625 * y) / (1.0 + 18.6875 * y), 78.84375);
#elif BUFFER_COLOR_SPACE == 4 // HLG
    float3 scene = max(Bt709ToBt2020(w * w), 0.0);
    float3 hi = 0.17883277 * log(max(12.0 * scene - 0.28466892, 1e-7)) + 0.55991073;
    return lerp(hi, sqrt(3.0 * scene), step(scene, 1.0 / 12.0));
#else                         // SDR (sRGB)
    return w;
#endif
}

float Level(float cMax)
{
#if BUFFER_COLOR_SPACE == 2   // scRGB
    return cMax * sqrt(80.0 / max(SD_REFERENCE_WHITE, 1.0));
#elif BUFFER_COLOR_SPACE == 3 // HDR10 (PQ)
    return cMax * sqrt(10000.0 / max(SD_REFERENCE_WHITE, 1.0));
#elif BUFFER_COLOR_SPACE == 4 // HLG
    return cMax * sqrt(1.0 / 0.265);
#else                         // SDR (sRGB)
    return cMax;
#endif
}

float4 PS_SD_Polarizer(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float4 src = tex2D(ReShade::BackBuffer, texcoord);

    [branch]
    if (cAmount <= 0.0)
        return src;

    // FP16 bound prevents Inf/NaN
    float3 color = min(src.rgb, 65504.0);
    float3 work = Decode(color);
    float cMax = max(work.r, max(work.g, work.b));
    float cMin = min(work.r, min(work.g, work.b));
    float chroma = cMax - cMin;

    // Relative chroma bound absorbs matrix rounding on neutrals; cMin guard preserves wide-gamut negatives
    [branch]
    if (chroma <= 1e-5 * cMax || cMin <= 1e-7)
        return src;

    float level = Level(cMax);
    float rcpMax = rcp(cMax);
    float rcpChroma = rcp(chroma);
    float sat = chroma * rcpMax;
    float veil = cMin * rcpMax;

    float warmth = max(work.r - max(work.g, work.b), 0.0) * rcpChroma;
    float wSpec = 1.0 - 0.70 * warmth;

    float s2 = sat * sat;
    float s4 = s2 * s2;
    float gate = (s4 * rcp(s4 + 0.008653650625)) * (veil * veil) * wSpec * smoothstep(0.0, 0.30, level); // 0.305^4 toe

    float2 x = float2(1.90, 3.14) * (cAmount * gate);
    float2 d = x * rcp(1.0 + x);

    float3 invT = (cMax - work) * rcpChroma;
    float3 outColor = Encode(work - cMin * (d.x + (d.y - d.x) * invT));

    float w = 1.0 - saturate(cRolloff) * smoothstep(0.0, 1.0, level);

    return float4(lerp(color, outColor, w), src.a);
}

technique SD_Polarizer <
    ui_label = "SD Polarizer";
    ui_tooltip = "Darkens and saturates washed-out colors while keeping hues and neutral tones unchanged.";
>
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_SD_Polarizer;
    }
}
