### ReShade shaders I missed having or was curious enough to make ✨

[![ReShade](https://img.shields.io/badge/ReShade-5.2+-E76F51.svg)](https://reshade.me)
[![Compatibility](https://img.shields.io/badge/Compatibility-SDR%20%26%20HDR-2EA043.svg)](#hdr-notes)
[![License](https://img.shields.io/badge/License-MPL%202.0-0969DA.svg)](LICENSE)

> [!NOTE]
> Developed with LLM assistance and verified mathematically in HDR,
> since I don't have a compatible monitor. If you spot any quirks across different
> setups, have suggestions or feedback, feel free to open an
> [issue](https://github.com/Starodubysko/sd-reshade-shaders/issues) or
> [pull request](https://github.com/Starodubysko/sd-reshade-shaders/pulls) =)

[Installation](#installation) · [Shaders](#shaders) · [Load Order](#load-order) · [HDR Notes](#hdr-notes) · [Support](#support)

## Installation

Requires ReShade 5.2+ for automatic HDR color space detection; earlier versions default to SDR.

### RHI

[**RHI**](https://theultraplace.com/tools/rhi/) bundles this pack alongside dozens of other curated shader packs and keeps it updated automatically:

1. Open **Shaders & Addons → Global Shaders** and enable **SD Shaders by Starodubysko** under **Extra**.
2. By default, RHI checks downloaded packs on every launch, pulls repository updates and syncs changed files into managed game folders.

### Manual

1. Clone or [download](https://github.com/Starodubysko/sd-reshade-shaders/archive/refs/heads/main.zip) this repository.
2. Copy `Shaders/SDFX` or individual `.fx` files into `reshade-shaders/Shaders`
   in your ReShade installation, usually inside the game folder.

In the game, open the ReShade overlay (Home tab), enable the shaders and arrange them using the [load order](#load-order). Reload the effects if the game was already running.

## Shaders

### `SD_Umbra`

> Deepens shadows and lowers washed-out black levels while keeping midtones and highlights unchanged.

<table><tr><td width="560">

https://github.com/user-attachments/assets/ae2ffb47-6025-473f-96a3-54f65bbbc4ad

</td></tr></table>

<details>
<summary>Details</summary>

`SD_Umbra` applies a smooth shadow curve in linear light, measuring darkness by the brightest RGB channel:
- Shadows gain depth while keeping near-black detail visible unless Black Point is raised.
- Saturated colors are judged by their strongest channel, so bright primaries like pure blue are not mistaken for shadows.
- Midtones above the threshold, reference white and HDR highlights stay unchanged.

**Techniques**

- **Luma** (default) darkens RGB uniformly to keep hue and saturation.
- **RGB** darkens each channel separately to increase saturation in shadows.

**Controls**

- **Amount** sets the effect strength.
- **Range** sets how far the effect extends from deep shadows toward midtones.
- **Black Point** lowers washed-out black levels to zero. High values clip near-black detail.

</details>

### `SD_Contrast`

> Increases or decreases midtone contrast without lifting pure black.

<table><tr><td width="560">

https://github.com/user-attachments/assets/1fea9e25-1edc-48ea-a046-4ee0b6d65c2f

</td></tr></table>

<details>
<summary>Details</summary>

`SD_Contrast` adjusts contrast around a balance tone using exact inverse curves, complementing `SD_Umbra` across the full tonal range after black levels are clean:
- Pure black, neutral balance tones and neutral reference white stay unchanged in SDR and HDR; in Soften, near-black shadows above pure black brighten.
- HDR highlights above reference white rejoin peak brightness smoothly.
- A smooth headroom limiter in SDR and positive `BT.2020` working transforms in HDR prevent channel clipping and wide-gamut negative values.
- Place `SD_Umbra` above `SD_Contrast` when pairing both shaders. Putting `SD_Contrast` first lets `Soften` lift washed-out black levels above `Black Point` and lets `Contrast` push near-black detail into clipping; stacking heavy shadow darkening across both shaders in 8-bit SDR also reduces deep-shadow gradient steps.

**Techniques**

- **Contrast** (default) darkens shadows and brightens highlights while keeping pure black unchanged.
- **Soften** brightens shadows and lowers highlights without lifting pure black.

**Controls**

- **Amount** sets the curve strength.
- **Pivot** sets the balance tone between shadows and highlights. Higher values darken midtones in Contrast and brighten midtones in Soften.
- **Channel Mix** blends between keeping original color intensity (0) and separate channel scaling (1), increasing color intensity in Contrast and decreasing it in Soften.

</details>

### `SD_Polarizer`

> Darkens and saturates washed-out colors while keeping hues and neutral tones unchanged.

<table><tr><td width="560">

https://github.com/user-attachments/assets/6a2b70bf-a109-4f0e-9d35-0a5970c158ca

</td></tr></table>

<details>
<summary>Details</summary>

Polarizing filters cut surface glare to reveal underlying colors.
`SD_Polarizer` approximates this effect in RGB by reducing
the weakest channel and scaling the others proportionally:
- Partially saturated colors respond the most, gaining depth and contrast.
- Near-neutral colors, deep shadows and red-dominant hues darken less to avoid gray highlights, clipped shadows and muddy warm shades.
- Neutral tones and fully saturated colors stay unchanged.

**Controls**

- **Amount** sets the effect strength.
- **Rolloff** reduces the effect toward bright areas. At 1, reference white and specular highlights stay unchanged.

</details>

### `SD_SubSat`

> Decreases brightness as saturation increases to keep colors dense.

<table><tr><td width="560">

https://github.com/user-attachments/assets/c07a32f7-1c46-4899-8efa-cc02711badd3

</td></tr></table>

<details>
<summary>Details</summary>

Unlike conventional saturation, which pushes RGB channels apart without
dimming them, `SD_SubSat` darkens weaker channels to separate colors and avoid
clipping while keeping transitions across hue boundaries smooth. Mixed hues
shift slightly toward the dominant primary and strength stays consistent across
shadows and highlights.

**Techniques**

- **Subtle** (default) uses rational compression without power curves for a natural response on midtones and skin.
- **Balanced** pairs deeper rational compression with moderate power-curve channel darkening for higher contrast.
- **Intense** steepens the high-saturation response with stronger channel separation.

**Controls**

- **Amount** sets the effect strength.
- **Rolloff** reduces the effect toward bright areas. At 1, neutral reference white and intense highlights stay unchanged.

</details>

### `SD_ColDensity`

> Darkens saturated colors by scaling RGB uniformly to keep hues and neutral tones unchanged.

<table><tr><td width="560">

https://github.com/user-attachments/assets/eef75d72-5522-4e97-85a0-1a0f3ad80b5b

</td></tr></table>

<details>
<summary>Details</summary>

Strength scales with saturation and closeness to primary colors while keeping
channel ratios intact. At Amount 1:
- Primaries (red, green, blue) darken by 70%.
- Secondaries (yellow, cyan, magenta) darken by 45%, keeping mixed hues from getting too dark.
- Neutral tones (white, gray, pure black) stay unchanged.

**Controls**

- **Amount** sets the effect strength.
- **Rolloff** reduces the effect toward bright areas. At 1, reference white and specular highlights stay unchanged.

</details>

### `SD_BleachBypass`

> Emulates bleach-bypass film processing for deeper shadows, higher contrast and muted color.

<table><tr><td width="560">

https://github.com/user-attachments/assets/a957ff8c-a365-438a-b7fa-dc7be39bb770

</td></tr></table>

<details>
<summary>Details</summary>

Skipping the bleach bath leaves metallic silver alongside color dyes, increasing tonal contrast while muting color. `SD_BleachBypass` models this look in linear working light while keeping shadows clean and highlights smooth:
- Pure black stays exact (though raised in-game black levels above zero still receive contrast and tint) and neutral reference white (1.0 in SDR, 203 nits default in HDR) stays unchanged in brightness and hue.
- HDR highlights above reference white extend smoothly; bright SDR colors compress near clipping limits.

**Techniques**

- **Subtle** (default) protects amber and skin tones while muting green and cyan hues with gentle shadow compression.
- **Balanced** deepens shadows and lower midtones with uniform desaturation and color darkening.
- **Intense** combines deep shadows, lifted upper midtones and strong desaturation; when stacked after `SD_Umbra` and `SD_Contrast`, subtle 8-bit deep-shadow bands may appear (`Subtle` or `Color` preserves finer shadow steps).
- **Color** skips neutral gray contrast so gray values pass untouched under Neutral tone; applies only desaturation, color darkening and optional Tone to pair after `SD_Contrast`.

**Controls**

- **Amount** sets the bleach contrast and desaturation strength.
- **Tone** leaves colors untinted at Neutral (default) or applies Cool (steel blue), Warm (amber) or Emerald (cyan-green) to shadows and midtones while keeping pure black unchanged and reference white plus brighter highlights neutral.
- **Tone Amount** sets Tone strength independently of Amount.

</details>

### `SD_Orton`

> Blends the image with an overexposed out-of-focus copy for a luminous glow and deep shadows.

<table><tr><td width="560">

https://github.com/user-attachments/assets/961f72ac-f691-4770-b89d-6411d1c1acbe

</td></tr></table>

<details>
<summary>Details</summary>

Michael Orton stacked two overexposed slides of the same scene, one sharp and
one out of focus. `SD_Orton` emulates this by blurring a copy in linear light
and multiplying it with the sharp image:
- Bright areas glow into their surroundings, while broad shadows deepen and colors gain density.
- Flat bright regions at or above reference white stay unchanged.
- Small highlights on dark backgrounds dim as the blurred surroundings suppress isolated points.

**Techniques**

- **Classic** (default) overexposes every pixel of the sharp image, softening fine detail into the glow.
- **Sharp** overexposes only the blurred copy, keeping fine detail crisp under the same tonal response.

**Controls**

- **Amount** sets the effect strength.
- **Radius** sets the glow spread relative to screen height.

</details>

### `SD_Sfumato`

> Smooths harsh digital edges along contours for a softer, more painterly look without blurring out detail.

<table><tr><td width="560">

https://github.com/user-attachments/assets/6f433070-4611-4876-8c99-a0191a87667b

</td></tr></table>

<details>
<summary>Details</summary>

Named after the Renaissance technique of blending tones without harsh outlines, `SD_Sfumato` estimates edge direction from a smoothed structure tensor and blends colors along each contour in perceptual space. Symmetric cross-contour sampling softens stair-steps, oversharpened seams and hard pixel transitions without shifting contours or spreading HDR highlight halos:
- Blends along contours instead of blurring uniformly across pixels, leaving areas below `Threshold` unchanged while keeping contour position and width intact.
- **Hybrid** and **Depth** modes require ReShade's **Generic Depth** add-on.
- Place after sharpening and before depth of field, grain and dithering to smooth the contour aliasing and oversharpened seams that sharpening brings out without re-sharpening the result.

**Modes**

- **Color** (default) blends all sharp edges across 3D contours, aliasing and surface detail.
- **Hybrid** keeps full strength on 3D contours and half strength on surface detail.
- **Depth** limits blending to 3D contours.

**Controls**

- **Amount** sets the blending strength along edges.
- **Advanced / Radius** sets the stroke length along edges relative to screen height.
- **Advanced / Threshold** sets the minimum edge contrast that starts blending. Lower values also blend fine detail and aliasing while higher values limit blending to major contours.
- **Advanced / Debug View** selects `Off` (default), `Edges` (blending mask) or `Disparity` (depth boundary preview, active even when `Amount` is `0`).

</details>

## Load Order

ReShade lists shaders alphabetically rather than by processing order, placing all other SD shaders above `SD_Umbra` by default. Reorder them top-to-bottom as shown below, keeping AutoHDR shaders, input calibration (gamma or black-level fixes) and base exposure adjustments at the top above `SD_Umbra`:

| Order | Shaders | Why |
| :--- | :--- | :--- |
| 1 | [`SD_Umbra`](#sd_umbra) | Sets pure-black floor before later contrast or color curves stretch washed-out shadows |
| 2 | [`SD_Contrast`](#sd_contrast) | Balances exposure before color passes scale individual RGB channels |
| 3 | [`SD_Polarizer`](#sd_polarizer), [`SD_SubSat`](#sd_subsat), [`SD_ColDensity`](#sd_coldensity) | Works on settled tonal balance; put `SD_Polarizer` above `SD_SubSat` |
| 4 | [`SD_BleachBypass`](#sd_bleachbypass) | Feeds finalized tone and color into glow (`Color` pairs below `SD_Contrast`) |
| 5 | [`SD_Orton`](#sd_orton) | Reads final highlights and darks so downstream passes do not skew blur falloff |
| 6 | Sharpening (like `lilium__rcas_hdr`) | Recovers micro-texture softened by `SD_Orton` |
| 7 | [`SD_Sfumato`](#sd_sfumato) | Smooths contour aliasing and sharpening halos without getting re-sharpened |
| 8 | Finishing passes (DoF, lens, grain, dithering) | Stops optical blur, film grain or noise from steering edge detection |
| 9 | SDR-only effects | Clamps to `[0, 1]` at the end instead of clipping HDR peaks and wide gamut early |

## HDR Notes

Both SDR and HDR are supported, with ReShade detecting the active color space
and shaders adapting automatically.

In scRGB and HDR10, all shaders target the ITU-R BT.2408 default of 203 nits.
To match a custom reference white, set `SD_REFERENCE_WHITE=203.0`
(replacing `203.0` with your target nits) in ReShade's Preprocessor definitions.
HLG maps reference white to `0.265` scene linear light per ITU-R BT.2408.

## Support

Thanks for stopping by! If you have the means and feel like
supporting my questionable tinkering financially, you can chip in here:

- [**Tip Jar**](https://send.monobank.ua/jar/3maQ1jeZKB) (Card, Apple Pay, Google Pay)
- **Solana** (SOL, USDC, USDT):
  ```text
  FRavTdSuQ2czFqMsuj7xW9QNJdJoUxx3rMWhdmQDRh3G
  ```

## License

[MPL 2.0](LICENSE) © 2026 Starodubysko
