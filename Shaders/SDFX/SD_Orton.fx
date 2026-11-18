// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Starodubysko (https://github.com/Starodubysko/sd-reshade-shaders)

#include "ReShade.fxh"

uniform int cTechnique <
    ui_type = "combo";
    ui_items = "Classic\0Sharp\0";
    ui_label = "Technique";
    ui_tooltip = "Classic overexposes the sharp image, softening fine detail into the glow.\nSharp overexposes only the blurred copy to keep fine detail crisp.";
> = 0;

uniform float cAmount <
    ui_type = "slider";
    ui_min = 0.00;
    ui_max = 1.00;
    ui_step = 0.05;
    ui_label = "Amount";
    ui_tooltip = "Sets the effect strength.";
> = 0.50;

uniform float cRadius <
    ui_type = "slider";
    ui_min = 0.00;
    ui_max = 1.00;
    ui_step = 0.05;
    ui_label = "Radius";
    ui_tooltip = "Sets the glow spread relative to screen height.";
> = 0.50;

// Target nits for scRGB and HDR10 (ITU-R BT.2408 default)
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3
    #ifndef SD_REFERENCE_WHITE
        #define SD_REFERENCE_WHITE 203.0
    #endif
#endif

#define SD_ORTON_WIDTH  ((BUFFER_WIDTH + 3) / 4)
#define SD_ORTON_HEIGHT ((BUFFER_HEIGHT + 3) / 4)

texture SD_Orton_TexA { Width = SD_ORTON_WIDTH; Height = SD_ORTON_HEIGHT; Format = RGBA16F; };
texture SD_Orton_TexB { Width = SD_ORTON_WIDTH; Height = SD_ORTON_HEIGHT; Format = RGBA16F; };
sampler sOrtonA { Texture = SD_Orton_TexA; };
sampler sOrtonB { Texture = SD_Orton_TexB; };

// IEEE range check scrubs NaN to 0 across D3D, OpenGL and Vulkan so blur passes never spread NaN
float SanitizeFinite(float x, float lo, float hi) { return (x >= lo) ? ((x <= hi) ? x : hi) : ((x < lo) ? lo : 0.0); }

float3 SanitizeFinite(float3 x, float lo, float hi) { return float3(SanitizeFinite(x.r, lo, hi), SanitizeFinite(x.g, lo, hi), SanitizeFinite(x.b, lo, hi)); }

#if BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
// Per-channel blending uses BT.709 primaries to match SDR
float3 Bt2020ToBt709(float3 c)
{
    return float3(dot(c, float3( 1.6604910, -0.5876411, -0.0728499)),
                  dot(c, float3(-0.1245505,  1.1328999, -0.0083494)),
                  dot(c, float3(-0.0181508, -0.1005789,  1.1187297)));
}

float3 Bt709ToBt2020(float3 c)
{
    return float3(dot(c, float3(0.6274039, 0.3292830, 0.0433131)),
                  dot(c, float3(0.0690973, 0.9195404, 0.0113623)),
                  dot(c, float3(0.0163914, 0.0880133, 0.8955953)));
}
#endif

// Guard 0 avoids Inf and NaN from pow()
float3 SafePow(float3 x, float e) { return x > 0.0 ? pow(max(x, 1e-30), e) : 0.0; }

// Sign-preserving slope-matched sRGB transfer, extended above 1 for HDR
float3 SrgbToLinear(float3 v)
{
    float3 a = abs(v);
    return (v >= 0.0 ? float3(1.0, 1.0, 1.0) : float3(-1.0, -1.0, -1.0)) * (a <= 0.039285714
        ? a * (1.0 / 12.9232102)
        : SafePow((a + 0.055) / 1.055, 2.4));
}

float3 LinearToSrgb(float3 l)
{
    float3 a = abs(l);
    return (l >= 0.0 ? float3(1.0, 1.0, 1.0) : float3(-1.0, -1.0, -1.0)) * (a <= 0.003039935
        ? a * 12.9232102
        : 1.055 * SafePow(a, 1.0 / 2.4) - 0.055);
}

// BT.709 linear light, 1 = reference white
float3 ToLinear(float3 c)
{
    float3 s = SanitizeFinite(c, -65504.0, 65504.0);
#if BUFFER_COLOR_SPACE == 2   // scRGB
    return s * (80.0 / max(SD_REFERENCE_WHITE, 1.0));
#elif BUFFER_COLOR_SPACE == 3 // HDR10 (PQ)
    float3 p = SafePow(saturate(s), 1.0 / 78.84375);
    float3 lin = SafePow(max(p - 0.8359375, 0.0) / max(18.8515625 - 18.6875 * p, 1e-6), 1.0 / 0.1593017578125);
    return Bt2020ToBt709(lin * (10000.0 / max(SD_REFERENCE_WHITE, 1.0)));
#elif BUFFER_COLOR_SPACE == 4 // HLG (0.265 scene light matches BT.2408 reference white)
    float3 e = saturate(s);
    float3 scene = e <= 0.5
        ? e * e * (1.0 / 3.0)
        : (exp((e - 0.55991073) / 0.17883277) + 0.28466892) * (1.0 / 12.0);
    return Bt2020ToBt709(scene * (1.0 / 0.265));
#else                         // SDR (sRGB)
    return SrgbToLinear(saturate(s));
#endif
}

#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
float3 FromLinear(float3 l)
{
#if BUFFER_COLOR_SPACE == 2   // scRGB
    return SanitizeFinite(l * (max(SD_REFERENCE_WHITE, 1.0) / 80.0), -65504.0, 65504.0);
#elif BUFFER_COLOR_SPACE == 3 // HDR10 (PQ)
    float3 bt2020 = saturate(Bt709ToBt2020(l) * (max(SD_REFERENCE_WHITE, 1.0) / 10000.0));
    float3 y = SafePow(bt2020, 0.1593017578125);
    float3 pq = SafePow((0.8359375 + 18.8515625 * y) / (1.0 + 18.6875 * y), 78.84375);
    return bt2020 > 0.0 ? pq : 0.0;
#else                         // HLG
    float3 scene = max(Bt709ToBt2020(l) * 0.265, 0.0);
    return scene <= (1.0 / 12.0)
        ? sqrt(3.0 * scene)
        : 0.17883277 * log(max(12.0 * scene - 0.28466892, 1e-7)) + 0.55991073;
#endif
}
#endif

// Screen blend with itself, clamped at reference white
float3 Screen(float3 v)
{
    float3 s = saturate(v);
    return s * (2.0 - s);
}

// 4x4 box downsample in linear light
float4 PS_SD_Orton_Prepass(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    int2 base = int2(vpos.xy) * 4;
    int2 last = int2(BUFFER_WIDTH, BUFFER_HEIGHT) - 1;
    float3 sum = 0.0;

    [unroll]
    for (int y = 0; y < 4; y++)
    {
        [unroll]
        for (int x = 0; x < 4; x++)
            sum += ToLinear(tex2Dfetch(ReShade::BackBuffer, min(base + int2(x, y), last)).rgb);
    }

    return float4(sum * (1.0 / 16.0), 1.0);
}

float3 Blur(sampler s, float2 texcoord, float2 axis)
{
    // Sigma spans 0.5% to 3.5% of screen height, in quarter-resolution texels
    float sigma = BUFFER_HEIGHT * 0.25 * (0.005 + 0.030 * SanitizeFinite(cRadius, 0.0, 1.0));
    float k = -0.5 / (sigma * sigma);
    int n = (int)ceil(3.0 * sigma);

    float3 sum = tex2Dlod(s, float4(texcoord, 0.0, 0.0)).rgb;
    float wSum = 1.0;

    // Paired taps use bilinear filtering to fetch two weights at once
    [loop]
    for (int i = 1; i <= n; i += 2)
    {
        float w0 = exp(k * i * i);
        float w1 = exp(k * (i + 1) * (i + 1));
        float w = w0 + w1;
        if (w <= 0.0)
            break;
        float2 offset = axis * ((i * w0 + (i + 1) * w1) / w);

        sum += (tex2Dlod(s, float4(texcoord + offset, 0.0, 0.0)).rgb
              + tex2Dlod(s, float4(texcoord - offset, 0.0, 0.0)).rgb) * w;
        wSum += 2.0 * w;
    }

    return sum * rcp(wSum);
}

void VS_Orton_RT(in uint id : SV_VertexID, out float4 position : SV_Position, out float2 texcoord : TEXCOORD)
{
    PostProcessVS(id, position, texcoord);
    if (!(cAmount > 0.0))
        position = float4(2.0, 2.0, 0.0, 1.0);
}

float4 PS_SD_Orton_BlurH(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    return float4(Blur(sOrtonA, texcoord, float2(1.0 / SD_ORTON_WIDTH, 0.0)), 1.0);
}

float4 PS_SD_Orton_BlurV(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    return float4(Blur(sOrtonB, texcoord, float2(0.0, 1.0 / SD_ORTON_HEIGHT)), 1.0);
}

float4 PS_SD_Orton(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float4 src = tex2D(ReShade::BackBuffer, texcoord);
    float amt = SanitizeFinite(cAmount, 0.0, 1.0);

    [branch]
    if (amt <= 0.0)
        return src;

#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
    float3 vLin = ToLinear(src.rgb);
    float3 v = LinearToSrgb(vLin);
#else
    float3 v = SanitizeFinite(src.rgb, -65504.0, 65504.0);
#endif

    // Rescale UV because ceil(W / 4) * 4 may exceed BUFFER_WIDTH
    float2 rtUv = texcoord * (float2(BUFFER_WIDTH, BUFFER_HEIGHT) / (4.0 * float2(SD_ORTON_WIDTH, SD_ORTON_HEIGHT)));
    float3 blurred = Screen(LinearToSrgb(max(tex2D(sOrtonA, rtUv).rgb, 0.0)));

    // Sharp overexposes local blur to keep detail contrast; 3 - 2t keeps C1 continuity at 1
    float3 exposure = clamp(cTechnique, 0, 1) == 0 ? Screen(v) : blurred;
    float3 gain = blurred * (3.0 - 2.0 * exposure);

#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
    // Smooth positive-sum gain avoids channel-crossing jumps while keeping BT.2020 primaries in gamut
    float3 outPosLin = SrgbToLinear(max(v, 0.0) * lerp(1.0, gain, amt));
    float3 posLin = max(vLin, 0.0);
    float linGain = (outPosLin.r + outPosLin.g + outPosLin.b) * rcp(max(posLin.r + posLin.g + posLin.b, 1e-30));
    return float4(FromLinear(outPosLin + min(vLin, 0.0) * linGain), src.a);
#else
    return float4(v * lerp(1.0, gain, amt), src.a);
#endif
}

technique SD_Orton <
    ui_label = "SD Orton Effect";
    ui_tooltip = "Blends the image with an overexposed out-of-focus copy for a luminous glow and deep shadows.";
>
{
    pass Prepass
    {
        VertexShader = VS_Orton_RT;
        PixelShader = PS_SD_Orton_Prepass;
        RenderTarget = SD_Orton_TexA;
    }
    pass BlurH
    {
        VertexShader = VS_Orton_RT;
        PixelShader = PS_SD_Orton_BlurH;
        RenderTarget = SD_Orton_TexB;
    }
    pass BlurV
    {
        VertexShader = VS_Orton_RT;
        PixelShader = PS_SD_Orton_BlurV;
        RenderTarget = SD_Orton_TexA;
    }
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_SD_Orton;
    }
}
