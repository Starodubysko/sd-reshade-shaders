// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Starodubysko (https://github.com/Starodubysko/sd-reshade-shaders)

#include "ReShade.fxh"

uniform int cTechnique <
    ui_type = "combo";
    ui_items = "Classic\0Sharp\0";
    ui_label = "Technique";
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
    ui_tooltip = "Size of the out-of-focus glow.";
> = 0.50;

// Target nits for scRGB and HDR10 (ITU-R BT.2408 default)
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3
    #ifndef SD_REFERENCE_WHITE
        #define SD_REFERENCE_WHITE 203.0
    #endif
#endif

#define SD_ORTON_WIDTH  (BUFFER_WIDTH / 4)
#define SD_ORTON_HEIGHT (BUFFER_HEIGHT / 4)

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

// Sign-preserving sRGB transfer, extended above 1 for HDR
float3 SrgbToLinear(float3 v)
{
    float3 a = abs(v);
    return sign(v) * lerp(pow((a + 0.055) / 1.055, 2.4), a / 12.92, step(a, 0.04045));
}

float3 LinearToSrgb(float3 l)
{
    float3 a = abs(l);
    return sign(l) * lerp(1.055 * pow(a, 1.0 / 2.4) - 0.055, a * 12.92, step(a, 0.0031308));
}

// BT.709 linear light, 1 = reference white
float3 ToLinear(float3 c)
{
#if BUFFER_COLOR_SPACE == 2   // scRGB
    return clamp(c, -65504.0, 65504.0) * (80.0 / max(SD_REFERENCE_WHITE, 1.0));
#elif BUFFER_COLOR_SPACE == 3 // HDR10 (PQ)
    float3 p = pow(saturate(c), 1.0 / 78.84375);
    float3 lin = pow(max((p - 0.8359375) / (18.8515625 - 18.6875 * p), 0.0), 1.0 / 0.1593017578125);
    return Bt2020ToBt709(lin * (10000.0 / max(SD_REFERENCE_WHITE, 1.0)));
#elif BUFFER_COLOR_SPACE == 4 // HLG (reference white is 0.265 scene light)
    float3 e = saturate(c);
    float3 hi = (exp((e - 0.55991073) / 0.17883277) + 0.28466892) / 12.0;
    return Bt2020ToBt709(lerp(hi, e * e * (1.0 / 3.0), step(e, 0.5)) * (1.0 / 0.265));
#else                         // SDR (sRGB)
    return SrgbToLinear(saturate(c));
#endif
}

#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
float3 FromLinear(float3 l)
{
#if BUFFER_COLOR_SPACE == 2   // scRGB
    return l * (max(SD_REFERENCE_WHITE, 1.0) / 80.0);
#elif BUFFER_COLOR_SPACE == 3 // HDR10 (PQ)
    float3 y = pow(max(Bt709ToBt2020(l) * (max(SD_REFERENCE_WHITE, 1.0) / 10000.0), 0.0), 0.1593017578125);
    return pow((0.8359375 + 18.8515625 * y) / (1.0 + 18.6875 * y), 78.84375);
#else                         // HLG
    float3 scene = max(Bt709ToBt2020(l) * 0.265, 0.0);
    float3 hi = 0.17883277 * log(max(12.0 * scene - 0.28466892, 1e-7)) + 0.55991073;
    return lerp(hi, sqrt(3.0 * scene), step(scene, 1.0 / 12.0));
#endif
}
#endif

// Blend domain: sRGB signal relative to reference white, unbounded above 1 in HDR
float3 ToSignal(float3 c)
{
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
    return LinearToSrgb(ToLinear(c));
#else
    return c;
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
        float2 offset = axis * ((i * w0 + (i + 1) * w1) / w);

        sum += (tex2Dlod(s, float4(texcoord + offset, 0.0, 0.0)).rgb
              + tex2Dlod(s, float4(texcoord - offset, 0.0, 0.0)).rgb) * w;
        wSum += 2.0 * w;
    }

    return sum / wSum;
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

    // Defocused layer in signal space
    float3 blurred = Screen(LinearToSrgb(max(tex2D(sOrtonA, texcoord).rgb, 0.0)));

    // Sharp technique uses local average exposure to preserve fine detail contrast;
    // 3 - 2t ensures C1 continuity at reference white
    float3 exposure = cTechnique == 0 ? Screen(v) : blurred;
    float3 gain = blurred * (3.0 - 2.0 * exposure);

#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
    // Scale out-of-gamut negative channels by the dominant channel gain
    float vMax = max(v.r, max(v.g, v.b));
    float gMax = v.r == vMax ? gain.r : (v.g == vMax ? gain.g : gain.b);
    gain = lerp(gain, gMax, step(v, 0.0));
#endif

    return float4(FromSignal(v * lerp(1.0, gain, saturate(cAmount))), src.a);
}

technique SD_Orton <
    ui_label = "SD Orton Effect";
    ui_tooltip = "Blends the image with an overexposed out-of-focus copy for a luminous glow, rich colors and deep shadows.";
>
{
    pass Prepass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_SD_Orton_Prepass;
        RenderTarget = SD_Orton_TexA;
    }
    pass BlurH
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_SD_Orton_BlurH;
        RenderTarget = SD_Orton_TexB;
    }
    pass BlurV
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_SD_Orton_BlurV;
        RenderTarget = SD_Orton_TexA;
    }
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_SD_Orton;
    }
}
