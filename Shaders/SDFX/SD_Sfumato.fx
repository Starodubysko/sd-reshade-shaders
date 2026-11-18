// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Starodubysko (https://github.com/Starodubysko/sd-reshade-shaders)

#include "ReShade.fxh"

uniform int cMode <
    ui_type = "combo";
    ui_items = "Color\0Hybrid\0Depth\0";
    ui_label = "Mode";
    ui_tooltip = "Color blends all sharp edges across 3D contours, aliasing and surface detail.\nHybrid keeps full strength on 3D contours and half strength on surface detail.\nDepth limits blending to 3D contours.\nHybrid and Depth require the Generic Depth add-on.";
> = 0;

uniform float cAmount <
    ui_type = "slider";
    ui_min = 0.00;
    ui_max = 1.00;
    ui_step = 0.05;
    ui_label = "Amount";
    ui_tooltip = "Sets the blending strength along edges.";
> = 0.50;

uniform float cRadius <
    ui_category = "Advanced";
    ui_category_closed = true;
    ui_type = "slider";
    ui_min = 0.00;
    ui_max = 1.00;
    ui_step = 0.05;
    ui_label = "Radius";
    ui_tooltip = "Sets the stroke length along edges.\nScales with screen height for a consistent stroke width.";
> = 0.50;

uniform float cThreshold <
    ui_category = "Advanced";
    ui_category_closed = true;
    ui_type = "slider";
    ui_min = 0.00;
    ui_max = 1.00;
    ui_step = 0.05;
    ui_label = "Threshold";
    ui_tooltip = "Sets the minimum edge contrast that starts blending.\nLower values also blend fine detail and aliasing.";
> = 0.50;

uniform int cDebug <
    ui_category = "Advanced";
    ui_category_closed = true;
    ui_type = "combo";
    ui_items = "Off\0Edges\0Disparity\0";
    ui_label = "Debug View";
    ui_tooltip = "Edges shows the active blending mask.\nDisparity shows depth boundaries to verify depth alignment.\nActive even when Amount is 0.";
> = 0;

// Target nits for scRGB and HDR10 (ITU-R BT.2408 default)
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3
    #ifndef SD_REFERENCE_WHITE
        #define SD_REFERENCE_WHITE 203.0
    #endif
#endif

#ifndef RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN
    #define RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN 0
#endif
#ifndef RESHADE_DEPTH_INPUT_IS_REVERSED
    #define RESHADE_DEPTH_INPUT_IS_REVERSED 1
#endif
#ifndef RESHADE_DEPTH_INPUT_IS_MIRRORED
    #define RESHADE_DEPTH_INPUT_IS_MIRRORED 0
#endif
#ifndef RESHADE_DEPTH_INPUT_IS_LOGARITHMIC
    #define RESHADE_DEPTH_INPUT_IS_LOGARITHMIC 0
#endif
#ifndef RESHADE_DEPTH_MULTIPLIER
    #define RESHADE_DEPTH_MULTIPLIER 1
#endif
#ifndef RESHADE_DEPTH_INPUT_X_SCALE
    #define RESHADE_DEPTH_INPUT_X_SCALE 1
#endif
#ifndef RESHADE_DEPTH_INPUT_Y_SCALE
    #define RESHADE_DEPTH_INPUT_Y_SCALE 1
#endif
#ifndef RESHADE_DEPTH_INPUT_X_OFFSET
    #define RESHADE_DEPTH_INPUT_X_OFFSET 0
#endif
#ifndef RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET
    #define RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET 0
#endif
#ifndef RESHADE_DEPTH_INPUT_Y_OFFSET
    #define RESHADE_DEPTH_INPUT_Y_OFFSET 0
#endif
#ifndef RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET
    #define RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET 0
#endif

texture SD_Sfumato_TexA { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
texture SD_Sfumato_TexB { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
texture SD_Sfumato_TexC { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler sSD_SfumatoA { Texture = SD_Sfumato_TexA; };
sampler sSD_SfumatoB { Texture = SD_Sfumato_TexB; };
sampler sSD_SfumatoC { Texture = SD_Sfumato_TexC; };
sampler sSD_Sfumato_Depth { Texture = ReShade::DepthBufferTex; AddressU = CLAMP; AddressV = CLAMP; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; };

// IEEE range check scrubs NaN to 0 across D3D, OpenGL and Vulkan
float SanitizeFinite(float x, float lo, float hi) { return (x >= lo) ? ((x <= hi) ? x : hi) : ((x < lo) ? lo : 0.0); }

float3 SanitizeFinite(float3 x, float lo, float hi) { return float3(SanitizeFinite(x.r, lo, hi), SanitizeFinite(x.g, lo, hi), SanitizeFinite(x.b, lo, hi)); }

// ITU-R BT.709 and BT.2020 matrices (D65 white point)
#if BUFFER_COLOR_SPACE == 2
float3 Bt709ToBt2020(float3 c)
{
    return float3(dot(c, float3(0.6274039, 0.3292830, 0.0433131)),
                  dot(c, float3(0.0690973, 0.9195404, 0.0113623)),
                  dot(c, float3(0.0163914, 0.0880133, 0.8955953)));
}

float3 Bt2020ToBt709(float3 c)
{
    return float3(dot(c, float3( 1.6604910, -0.5876411, -0.0728499)),
                  dot(c, float3(-0.1245505,  1.1328999, -0.0083494)),
                  dot(c, float3(-0.0181508, -0.1005789,  1.1187297)));
}
#endif

#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
// Guard 0 avoids log2(0) NaN while keeping zero inputs exact
float3 SafePow(float3 x, float e) { return x > 0.0 ? pow(max(x, 1e-30), e) : 0.0; }

// Sign-preserving slope-matched sRGB transfer avoids the IEC shadow slope kink

float3 LinearToSrgb(float3 l)
{
    float3 a = abs(l);
    return (l >= 0.0 ? float3(1.0, 1.0, 1.0) : float3(-1.0, -1.0, -1.0)) * (a <= 0.003039935
        ? a * 12.9232102
        : 1.055 * SafePow(a, 1.0 / 2.4) - 0.055);
}

float3 SrgbToLinear(float3 v)
{
    float3 a = abs(v);
    return (v >= 0.0 ? float3(1.0, 1.0, 1.0) : float3(-1.0, -1.0, -1.0)) * (a <= 0.039285714
        ? a * (1.0 / 12.9232102)
        : SafePow((a + 0.055) / 1.055, 2.4));
}

// Linear BT.2020 working light normalized to reference white
float3 ToWorkLinear(float3 c)
{
#if BUFFER_COLOR_SPACE == 2   // scRGB
    return Bt709ToBt2020(c * (80.0 / max(SD_REFERENCE_WHITE, 1.0)));
#elif BUFFER_COLOR_SPACE == 3 // HDR10 (PQ)
    float3 p = SafePow(saturate(c), 1.0 / 78.84375);
    return SafePow(max(p - 0.8359375, 0.0) / max(18.8515625 - 18.6875 * p, 1e-6), 1.0 / 0.1593017578125) * (10000.0 / max(SD_REFERENCE_WHITE, 1.0));
#else                         // HLG (0.265 scene light matches BT.2408 reference white)
    float3 e = saturate(c);
    float3 scene = e <= 0.5
        ? e * e * (1.0 / 3.0)
        : (exp((e - 0.55991073) / 0.17883277) + 0.28466892) * (1.0 / 12.0);
    return scene * (1.0 / 0.265);
#endif
}

float3 FromWorkLinear(float3 l)
{
#if BUFFER_COLOR_SPACE == 2   // scRGB
    return SanitizeFinite(Bt2020ToBt709(l) * (max(SD_REFERENCE_WHITE, 1.0) / 80.0), -65504.0, 65504.0);
#elif BUFFER_COLOR_SPACE == 3 // HDR10 (PQ)
    float3 bt2020 = saturate(l * (max(SD_REFERENCE_WHITE, 1.0) / 10000.0));
    float3 y = SafePow(bt2020, 0.1593017578125);
    float3 pq = SafePow((0.8359375 + 18.8515625 * y) / (1.0 + 18.6875 * y), 78.84375);
    return bt2020 > 0.0 ? pq : 0.0;
#else                         // HLG
    float3 scene = max(l * 0.265, 0.0);
    return scene <= (1.0 / 12.0)
        ? sqrt(3.0 * scene)
        : 0.17883277 * log(max(12.0 * scene - 0.28466892, 1e-7)) + 0.55991073;
#endif
}
#endif

// C1 perceptual compression above 1.0; 2.99609375 cap stays below 3.0 after RGBA16F rounding
float3 CompressSignal(float3 s)
{
    float3 a = abs(s);
    float3 d = max(a - 1.0, 0.0);
    float3 y = min(1.0 + d * rcp(1.0 + 0.5 * d), 2.99609375);
    return (a <= 1.0) ? s : ((s >= 0.0) ? y : -y);
}

// 1.999 cap prevents division by zero at the a = 3.0 asymptote during rational inversion
float3 DecompressSignal(float3 u)
{
    float3 a = abs(u);
    float3 d = min(max(a - 1.0, 0.0), 1.999);
    float3 y = 1.0 + d * rcp(1.0 - 0.5 * d);
    return (a <= 1.0) ? u : ((u >= 0.0) ? y : -y);
}

// SDR works directly in sRGB signal space without redundant SrgbToLinear/LinearToSrgb round-trips
float3 EncodeSignal(float3 c)
{
    float3 safeRgb = SanitizeFinite(c, -65504.0, 65504.0);
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
    return CompressSignal(LinearToSrgb(ToWorkLinear(safeRgb)));
#else
    return CompressSignal(safeRgb);
#endif
}

float3 DecodeSignal(float3 u)
{
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
    return FromWorkLinear(SrgbToLinear(DecompressSignal(u)));
#else
    return DecompressSignal(u);
#endif
}

float3 FetchSignal(int2 pos)
{
    int2 p = clamp(pos, int2(0, 0), int2(BUFFER_WIDTH - 1, BUFFER_HEIGHT - 1));
    return EncodeSignal(tex2Dfetch(ReShade::BackBuffer, p).rgb);
}

// Mirrors ReShade::GetLinearizedDepth coordinate mapping while precomputing affine steps once per pixel
void MapDepthCoords(float2 uv, out float2 tc, out float2 stepX, out float2 stepY)
{
    float sx = (RESHADE_DEPTH_INPUT_X_SCALE != 0) ? (float)RESHADE_DEPTH_INPUT_X_SCALE : 1.0;
    float sy = (RESHADE_DEPTH_INPUT_Y_SCALE != 0) ? (float)RESHADE_DEPTH_INPUT_Y_SCALE : 1.0;
    tc = uv;
#if RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN
    tc.y = 1.0 - tc.y;
    float dirY = -1.0;
#else
    float dirY = 1.0;
#endif
#if RESHADE_DEPTH_INPUT_IS_MIRRORED
    tc.x = 1.0 - tc.x;
    float dirX = -1.0;
#else
    float dirX = 1.0;
#endif
    tc.x /= sx;
    tc.y /= sy;
#if RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET
    tc.x -= RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET * BUFFER_RCP_WIDTH;
#else
    tc.x -= RESHADE_DEPTH_INPUT_X_OFFSET / 2.000000001;
#endif
#if RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET
    tc.y += RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET * BUFFER_RCP_HEIGHT;
#else
    tc.y += RESHADE_DEPTH_INPUT_Y_OFFSET / 2.000000001;
#endif
    stepX = float2(dirX * BUFFER_RCP_WIDTH / sx, 0.0);
    stepY = float2(0.0, dirY * BUFFER_RCP_HEIGHT / sy);
}

float FetchDisparity(float2 tc)
{
    float depth = tex2Dlod(sSD_Sfumato_Depth, float4(tc, 0.0, 0.0)).x * RESHADE_DEPTH_MULTIPLIER;
#if RESHADE_DEPTH_INPUT_IS_LOGARITHMIC
    const float C = 0.01;
    depth = (exp(SanitizeFinite(depth, 0.0, 1.0) * log(C + 1.0)) - 1.0) / C;
#endif
#if !RESHADE_DEPTH_INPUT_IS_REVERSED
    depth = 1.0 - depth;
#endif
    return SanitizeFinite(depth, 0.0, 1.0);
}

// 2e-5 floor suppresses D16_UNORM single-LSB quantization steps; 4e-5 guards empty buffers
float RelLap(float dc, float d0, float d1)
{
    return max(abs(d0 + d1 - 2.0 * dc) - 2e-5, 0.0) * rcp(max(dc, max(d0, d1)) + 4e-5);
}

// Intersects 1-px and 2-px stride Laplacians across 5x5 to reject 0.50x upscaled tilted planes while keeping DLSS jitter immunity
float EvalDepthCliff(float2 uv)
{
    float2 tc0, dx, dy;
    MapDepthCoords(uv, tc0, dx, dy);

    float d[49];
    [unroll]
    for (int y = -3; y <= 3; ++y)
    {
        [unroll]
        for (int x = -3; x <= 3; ++x)
        {
            int idx = (y + 3) * 7 + (x + 3);
            // Outer corners are never referenced by 5x5 cross or 3x3 2-stride Laplacians
            d[idx] = (abs(y) == 3 && abs(x) == 3) ? 0.0 : FetchDisparity(tc0 + x * dx + y * dy);
        }
    }

    float maxDisp1 = 0.0;
    float maxDisp2 = 0.0;
    [unroll]
    for (int iy = 1; iy <= 5; ++iy)
    {
        [unroll]
        for (int ix = 1; ix <= 5; ++ix)
        {
            int cIdx = iy * 7 + ix;
            float dc = d[cIdx];
            maxDisp1 = max(maxDisp1, max(RelLap(dc, d[cIdx - 1], d[cIdx + 1]), RelLap(dc, d[cIdx - 7], d[cIdx + 7])));

            if (iy >= 2 && iy <= 4 && ix >= 2 && ix <= 4)
                maxDisp2 = max(maxDisp2, max(RelLap(dc, d[cIdx - 2], d[cIdx + 2]), RelLap(dc, d[cIdx - 14], d[cIdx + 14])));
        }
    }

    float dispStep = min(maxDisp1, maxDisp2);
    float thr = SanitizeFinite(cThreshold, 0.0, 1.0);
    // 0.038 floor rejects C0 surface creases even at minimum Threshold
    float thrD = lerp(0.038, 0.56, thr * thr);
    return smoothstep(thrD, thrD * 1.35 + 0.03, dispStep);
}

float MaxCh(float3 v) { return max(v.r, max(v.g, v.b)); }

float4 PS_SD_Sfumato_Prepass(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float3 uC = FetchSignal(int2(vpos.xy));
    int mode = clamp(cMode, 0, 2);
    float depthW = 1.0;

    [branch]
    if (mode != 0)
        depthW = EvalDepthCliff(texcoord);

    return float4(uC, depthW);
}

float4 FetchPrepass(int2 pos)
{
    int2 p = clamp(pos, int2(0, 0), int2(BUFFER_WIDTH - 1, BUFFER_HEIGHT - 1));
    return tex2Dfetch(sSD_SfumatoA, p);
}

// Di Zenzo multichannel structure tensor keeps isoluminant chroma edges oriented
float4 PS_SD_Sfumato_Structure(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    int2 pos = int2(vpos.xy);
    float4 c  = FetchPrepass(pos);
    float4 l  = FetchPrepass(pos + int2(-1,  0));
    float4 r  = FetchPrepass(pos + int2( 1,  0));
    float4 u  = FetchPrepass(pos + int2( 0, -1));
    float4 d  = FetchPrepass(pos + int2( 0,  1));
    float4 ul = FetchPrepass(pos + int2(-1, -1));
    float4 ur = FetchPrepass(pos + int2( 1, -1));
    float4 dl = FetchPrepass(pos + int2(-1,  1));
    float4 dr = FetchPrepass(pos + int2( 1,  1));

    // Weber-weighted normalization preserves shadowed edges without amplifying dark compression noise
    float3 peak3 = max(abs(c.rgb), max(max(abs(l.rgb), abs(r.rgb)), max(abs(u.rgb), abs(d.rgb))));
    float scale = 0.25 * rcp(0.28 + 0.72 * MaxCh(peak3));

    // Sobel scaled so a unit step reads 1.0 on both adjacent pixels
    float3 gx = (2.0 * (r.rgb - l.rgb) + (ur.rgb - ul.rgb) + (dr.rgb - dl.rgb)) * scale;
    float3 gy = (2.0 * (d.rgb - u.rgb) + (dl.rgb - ul.rgb) + (dr.rgb - ur.rgb)) * scale;
    float depthW = max(c.a, max(max(l.a, r.a), max(u.a, d.a)));

    return float4(dot(gx, gx), dot(gy, gy), dot(gx, gy), depthW);
}

// Nine bilinear taps at 1.3 px approximate a sigma 1.3 Gaussian so stair-step aliasing resolves into one coherent orientation
// Depth weight takes the tap maximum so the silhouette gate covers the whole stroke footprint under DLSS and TAA jitter
float4 PS_SD_Sfumato_Smooth(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float2 o = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT) * 1.3;
    float3 sum = 0.0;
    float depthW = 0.0;
    [unroll]
    for (int y = -1; y <= 1; ++y)
    {
        [unroll]
        for (int x = -1; x <= 1; ++x)
        {
            float w = ((x != 0) ? 1.05 : 1.0) * ((y != 0) ? 1.05 : 1.0);
            float4 tap = tex2Dlod(sSD_SfumatoB, float4(texcoord + float2(x, y) * o, 0.0, 0.0));
            sum += tap.xyz * w;
            depthW = max(depthW, tap.w);
        }
    }
    return float4(sum * (1.0 / 9.61), depthW);
}

// Minor eigenvector of the structure tensor; branch pair keeps the half-angle vector well conditioned at every orientation
float2 FlowTangentFromDelta(float3 j, float dlt)
{
    float2 g = (j.x >= j.y) ? float2(j.x - j.y + dlt, 2.0 * j.z) : float2(2.0 * j.z, j.y - j.x + dlt);
    float len2 = dot(g, g);
    g = (len2 > 1e-20) ? g * rsqrt(len2) : float2(1.0, 0.0);
    return float2(-g.y, g.x);
}

float2 FlowTangent(float3 j)
{
    return FlowTangentFromDelta(j, sqrt((j.x - j.y) * (j.x - j.y) + 4.0 * j.z * j.z));
}

void VS_SD_Sfumato_RT(in uint id : SV_VertexID, out float4 position : SV_Position, out float2 texcoord : TEXCOORD)
{
    PostProcessVS(id, position, texcoord);
    int dbg = clamp(cDebug, 0, 2);
    if ((!(cAmount > 0.0) && dbg == 0) || dbg == 2)
        position = float4(2.0, 2.0, 0.0, 1.0);
}

float4 EncodeDebugVis(float vis, float alpha)
{
#if BUFFER_COLOR_SPACE == 2 || BUFFER_COLOR_SPACE == 3 || BUFFER_COLOR_SPACE == 4
    return float4(FromWorkLinear(SrgbToLinear(float3(vis, vis, vis))), alpha);
#else
    return float4(vis, vis, vis, alpha);
#endif
}

float4 PS_SD_Sfumato(float4 vpos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{
    float4 src = tex2D(ReShade::BackBuffer, texcoord);
    int dbg = clamp(cDebug, 0, 2);
    float amt = SanitizeFinite(cAmount, 0.0, 1.0);

    [branch]
    if (amt <= 0.0 && dbg == 0)
        return src;

    [branch]
    if (dbg == 2)
    {
        // Un-dilated 5-tap center disparity step exposes 1-2px depth misalignment without running flow passes
        float2 tc0, dx, dy;
        MapDepthCoords(texcoord, tc0, dx, dy);
        float dc = FetchDisparity(tc0);
        float relX = RelLap(dc, FetchDisparity(tc0 - dx), FetchDisparity(tc0 + dx));
        float relY = RelLap(dc, FetchDisparity(tc0 - dy), FetchDisparity(tc0 + dy));
        return EncodeDebugVis(saturate(max(relX, relY) * 0.85), src.a);
    }

    float4 tens = tex2Dlod(sSD_SfumatoC, float4(texcoord, 0.0, 0.0));
    float3 j = tens.xyz;
    float dlt = sqrt((j.x - j.y) * (j.x - j.y) + 4.0 * j.z * j.z);
    float l1 = 0.5 * (j.x + j.y + dlt);
    float l2 = 0.5 * (j.x + j.y - dlt);
    float strength  = sqrt(max(l1, 0.0));
    float coherence = saturate((l1 - l2) * rcp(max(l1 + l2, 0.0) + 1e-6));

    // Squared Threshold curve spreads control from fine texture and aliasing steps up to major contours only
    float thr = SanitizeFinite(cThreshold, 0.0, 1.0);
    float tE  = lerp(0.012, 0.36, thr * thr);

    int mode = clamp(cMode, 0, 2);
    float depthGate = smoothstep(0.05, 0.45, tens.a);
    float modeW = (mode == 0) ? 1.0 : ((mode == 1) ? lerp(0.5, 1.0, depthGate) : depthGate);

    // 0.40 floor lets corners and isolated specks join neighboring strokes instead of standing out unblended
    float edgeMask = smoothstep(tE, tE * 2.0 + 0.02, strength) * (0.40 + 0.60 * smoothstep(0.10, 0.45, coherence)) * modeW;

    [branch]
    if (dbg == 1)
        return EncodeDebugVis(edgeMask, src.a);

    [branch]
    if (edgeMask <= 0.0)
        return float4(SanitizeFinite(src.rgb, -65504.0, 65504.0), src.a);

    float3 uCenter = EncodeSignal(src.rgb);

    // Stroke length and cross offset scale with screen height so the look matches across resolutions
    float r = SanitizeFinite(cRadius, 0.0, 1.0);
    float scale = BUFFER_HEIGHT * (1.0 / 1440.0);
    float strokeLen = scale * (1.0 + 5.0 * r);
    int n = min((int)ceil(strokeLen), 10);
    float2 rcpSize = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);
    float2 stepUv = (strokeLen / n) * rcpSize;
    float2 crossUv = (scale * (0.20 + 0.40 * r)) * rcpSize;
    float kStep = -2.0 / (n * n);
    float2 t0 = FlowTangentFromDelta(j, dlt);

    // Lockstep bidirectional LIC traces both half-strokes in one loop, shifting each side across the contour
    // so the kernel stays point-symmetric and softens the edge profile by a sub-pixel amount without moving it
    float3 sum = uCenter;
    float wSum = 1.0;
    float2 dirPos = t0,  pPos = texcoord;
    float2 dirNeg = -t0, pNeg = texcoord;

    [loop]
    for (int i = 1; i <= n; ++i)
    {
        pPos += dirPos * stepUv;
        pNeg += dirNeg * stepUv;

        float2 tPos = FlowTangent(tex2Dlod(sSD_SfumatoC, float4(pPos, 0.0, 0.0)).xyz);
        float2 tNeg = FlowTangent(tex2Dlod(sSD_SfumatoC, float4(pNeg, 0.0, 0.0)).xyz);
        dirPos = (dot(tPos, dirPos) < 0.0) ? -tPos : tPos;
        dirNeg = (dot(tNeg, dirNeg) < 0.0) ? -tNeg : tNeg;

        float wt = exp(kStep * (i * i));
        sum += (tex2Dlod(sSD_SfumatoA, float4(pPos + float2(-dirPos.y, dirPos.x) * crossUv, 0.0, 0.0)).rgb
              + tex2Dlod(sSD_SfumatoA, float4(pNeg + float2(-dirNeg.y, dirNeg.x) * crossUv, 0.0, 0.0)).rgb) * wt;
        wSum += 2.0 * wt;
    }
    float3 stroke = sum * rcp(wSum);

    // Restrains HDR highlight streaks that would otherwise lift neighbors far above reference white
    float liftHdr   = max(MaxCh(stroke) - max(1.0, MaxCh(uCenter)), 0.0);
    float haloGuard = rcp(1.0 + 12.0 * liftHdr * liftHdr);

    // Concave Amount response makes the default clearly visible while 1.0 still reaches full strength
    float w = amt * (2.0 - amt) * edgeMask * haloGuard;
    return float4(DecodeSignal(lerp(uCenter, stroke, w)), src.a);
}

technique SD_Sfumato <
    ui_label = "SD Sfumato";
    ui_tooltip = "Smooths harsh digital edges along contours for a softer, more painterly look without blurring out detail.";
>
{
    pass Prepass
    {
        VertexShader = VS_SD_Sfumato_RT;
        PixelShader = PS_SD_Sfumato_Prepass;
        RenderTarget = SD_Sfumato_TexA;
    }
    pass Structure
    {
        VertexShader = VS_SD_Sfumato_RT;
        PixelShader = PS_SD_Sfumato_Structure;
        RenderTarget = SD_Sfumato_TexB;
    }
    pass Smooth
    {
        VertexShader = VS_SD_Sfumato_RT;
        PixelShader = PS_SD_Sfumato_Smooth;
        RenderTarget = SD_Sfumato_TexC;
    }
    pass Stroke
    {
        VertexShader = PostProcessVS;
        PixelShader = PS_SD_Sfumato;
    }
}
