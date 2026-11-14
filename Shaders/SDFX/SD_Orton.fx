// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Starodubysko (https://github.com/Starodubysko/sd-reshade-shaders)

#include "ReShade.fxh"

uniform int cTechnique <
    ui_type = "combo";
    ui_items = "Classic\0Sharp\0";
    ui_label = "Technique";
    ui_tooltip = "Classic softens the entire image into a dreamy glow.\nSharp preserves fine detail contrast.";
> = 0;

uniform float cAmount <
    ui_type = "slider";
    ui_min = 0.00;
    ui_max = 1.00;
    ui_step = 0.05;
    ui_label = "Amount";
> = 0.50;

uniform float cRadius <
    ui_type = "slider";
    ui_min = 0.00;
    ui_max = 1.00;
    ui_step = 0.05;
    ui_label = "Radius";
    ui_tooltip = "Controls the blur radius of the out-of-focus glow.";
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

#if BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
// Per-channel blending is defined on BT.709 primaries, as in SDR
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

// Sign-preserving slope-matched sRGB transfer, extended above 1 for HDR
float3 SrgbToLinear(float3 v)
{
    float3 a = abs(v);
    return (v >= 0.0 ? 1.0 : -1.0) * (a <= 0.039285714
        ? a * (1.0 / 12.9232102)
        : SafePow((a + 0.055) / 1.055, 2.4));
}

float3 LinearToSrgb(float3 l)
{
    float3 a = abs(l);
    return (l >= 0.0 ? 1.0 : -1.0) * (a <= 0.003039935
        ? a * 12.9232102
        : 1.055 * SafePow(a, 1.0 / 2.4) - 0.055);
}

// BT.709 linear light, 1 = reference white
float3 ToLinear(float3 c)
{
#if BUFFER_COLOR_SPACE == 2   // scRGB
    return clamp(c, -65504.0, 65504.0) * (80.0 / max(SD_REFERENCE_WHITE, 1.0));
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
    return SrgbToLinear(saturate(c));
#endif
}

#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
float3 FromLinear(float3 l)
{
#if BUFFER_COLOR_SPACE == 2   // scRGB
    return clamp(l * (max(SD_REFERENCE_WHITE, 1.0) / 80.0), -65504.0, 65504.0);
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

// Blend domain: sRGB signal relative to reference white, unbounded above 1 in HDR
float3 ToSignal(float3 c)
{
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
    return LinearToSrgb(ToLinear(c));
#else
    return clamp(c, -65504.0, 65504.0);
#endif
}

float3 FromSignal(float3 v)
{
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
    return FromLinear(SrgbToLinear(v));
#else
    return v;
#endif
}

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
    float sigma = BUFFER_HEIGHT * 0.25 * (0.005 + 0.030 * saturate(cRadius));
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

    return wSum > 1e-30 ? sum / wSum : 0.0;
}

void VS_Orton_RT(in uint id : SV_VertexID, out float4 position : SV_Position, out float2 texcoord : TEXCOORD)
{
    PostProcessVS(id, position, texcoord);
    if (cAmount <= 0.0)
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

    [branch]
    if (cAmount <= 0.0)
        return src;

    float3 v = ToSignal(src.rgb);

    // Defocused layer in signal space; rescale UV because ceil(W/4) x 4 may exceed BUFFER_WIDTH
    float2 rtUv = texcoord * (float2(BUFFER_WIDTH, BUFFER_HEIGHT) / (4.0 * float2(SD_ORTON_WIDTH, SD_ORTON_HEIGHT)));
    float3 blurred = Screen(LinearToSrgb(max(tex2D(sOrtonA, rtUv).rgb, 0.0)));

    // Sharp overexposes local blur to keep detail contrast; 3 - 2t keeps C1 continuity at 1
    float3 exposure = cTechnique == 0 ? Screen(v) : blurred;
    float3 gain = blurred * (3.0 - 2.0 * exposure);

#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
    // Scale negative wide-gamut channels by dominant linear gain so BT.2020 primaries stay in gamut
    float3 vLin = SrgbToLinear(v);
    float3 outPosLin = SrgbToLinear(max(v, 0.0) * lerp(1.0, gain, saturate(cAmount)));
    float vMaxLin = max(vLin.r, max(vLin.g, vLin.b));
    float outMaxLin = vLin.r == vMaxLin ? outPosLin.r : (vLin.g == vMaxLin ? outPosLin.g : outPosLin.b);
    float gMaxLin = vMaxLin > 0.0 ? outMaxLin * rcp(vMaxLin) : 1.0;
    return float4(FromLinear(outPosLin + min(vLin, 0.0) * gMaxLin), src.a);
#else
    return float4(FromSignal(v * lerp(1.0, gain, saturate(cAmount))), src.a);
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
