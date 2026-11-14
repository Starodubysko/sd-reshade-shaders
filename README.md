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

Requires ReShade 5.2+ for automatic HDR color space detection, earlier versions default to SDR.

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

https://github.com/user-attachments/assets/7471b9e5-27ae-4964-8480-599a793afb22

</td></tr></table>

<details>
<summary>Details</summary>

`SD_Umbra` applies a smooth shadow curve in linear light, measuring darkness by the brightest RGB channel:
- Shadows gain depth while keeping near-black detail visible unless Black Point is raised.
- Saturated colors are judged by their strongest channel, so bright primaries like pure blue are not mistaken for shadows.
- Midtones above the threshold, reference white and HDR highlights remain unchanged.

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

https://github.com/user-attachments/assets/b868903e-82e5-4611-a44c-76bea4166aa5

</td></tr></table>

<details>
<summary>Details</summary>

`SD_Contrast` adjusts contrast across shadows, midtones and highlights around a balance tone using exact inverse curves, complementing `SD_Umbra` by acting on the full tonal range after black levels are clean:
- Pure black, neutral balance tones and neutral reference white stay unchanged in SDR and HDR; in Soften, near-black shadows above pure black brighten.
- Bright HDR highlights above reference white smoothly rejoin untouched peak brightness with no hard transition.
- A smooth headroom limiter in SDR and positive `BT.2020` working transforms in HDR prevent channel clipping and wide-gamut negative values.
- Place `SD_Umbra` above `SD_Contrast` when pairing both shaders. Putting `SD_Contrast` first lets `Soften` lift washed-out black levels above `Black Point` and lets `Contrast` push near-black detail into clipping; beware that stacking heavy shadow darkening across both shaders in 8-bit SDR also reduces deep-shadow gradient steps.

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

https://github.com/user-attachments/assets/c894299f-5d62-437f-ad53-29c77e8c5b7c

</td></tr></table>

<details>
<summary>Details</summary>

Polarizing filters cut surface glare to reveal the underlying colors.
`SD_Polarizer` offers a simple RGB approximation of this effect by decreasing
the weakest channel and scaling the others proportionally:
- Partially saturated colors respond the most, gaining depth and contrast.
- Near-neutral colors, deep shadows and red-dominant hues darken less to avoid gray highlights, clipped shadows and muddy warm shades.
- Neutral tones and fully saturated colors remain unchanged.

**Controls**

- **Amount** sets the effect strength.
- **Rolloff** decreases the effect gradually toward bright areas. At 1, reference white and specular highlights remain unchanged.

</details>

### `SD_SubSat`

> Subtractive saturation that decreases brightness as saturation increases to keep colors dense.

<table><tr><td width="560">

https://github.com/user-attachments/assets/68ea9190-5141-4e03-a42e-bfc74a2f559b

</td></tr></table>

<details>
<summary>Details</summary>

Unlike conventional saturation, which pushes RGB channels apart without
dimming them, `SD_SubSat` darkens weaker channels to separate colors and avoid
clipping. Mixed hues shift slightly toward the dominant primary while strength
stays consistent across shadows and highlights.

**Techniques**

- **Subtle** (default) uses gentle rational compression without power curves for a natural response on midtones and skin.
- **Balanced** combines square-root mean density with moderate channel darkening for deeper overall contrast.
- **Intense** applies harmonic mean density with a steeper curve for strong color separation.

**Controls**

- **Amount** sets the effect strength.
- **Rolloff** decreases the effect gradually toward bright areas. At 1, reference white and specular highlights remain unchanged.

</details>

### `SD_ColDensity`

> Darkens saturated colors by scaling RGB uniformly to keep hues and neutral tones unchanged.

<table><tr><td width="560">

https://github.com/user-attachments/assets/74c73669-dff3-4afc-a36e-294a5d12da18

</td></tr></table>

<details>
<summary>Details</summary>

Strength scales with saturation and closeness to primary colors while keeping
channel ratios intact. At Amount 1:
- Primaries (red, green, blue) darken by 70%.
- Secondaries (yellow, cyan, magenta) darken by 45%, keeping mixed hues from getting too dark.
- Neutral tones (white, gray, pure black) remain unchanged.

**Controls**

- **Amount** sets the effect strength.
- **Rolloff** decreases the effect gradually toward bright areas. At 1, reference white and specular highlights remain unchanged.

</details>

### `SD_BleachBypass`

> Emulates bleach-bypass film processing for deeper shadows, higher contrast and muted color.

<table><tr><td width="560">

https://github.com/user-attachments/assets/38efd368-54ce-402b-a524-eccc5621f6ab

</td></tr></table>

<details>
<summary>Details</summary>

Skipping the bleach bath leaves metallic silver alongside color dyes, increasing tonal contrast while muting color. `SD_BleachBypass` models this look in linear working light while keeping shadows clean and highlights smooth:
- Pure black stays exact (though raised in-game black levels above zero still receive contrast and tint) and neutral reference white (1.0 in SDR, 203 nits default in HDR) stays unchanged in brightness and hue.
- Bright HDR highlights above reference white extend smoothly with no hard seam; bright colors at high contrast compress gradually in SDR to avoid channel clipping.

**Techniques**

- **Subtle** (default) protects warm amber and skin tones while muting green and cyan hues with gentle shadow compression.
- **Balanced** deepens shadows and lower midtones with uniform desaturation and color darkening.
- **Intense** combines deep shadows, lifted upper midtones and strong desaturation; when stacked after `SD_Umbra` and `SD_Contrast`, subtle 8-bit deep-shadow bands may appear (`Subtle` or `Color` preserves finer shadow steps).
- **Color** skips neutral gray contrast so gray values pass untouched under Neutral tone; applies only desaturation, color darkening and optional Tone so contrast comes from `SD_Contrast` upstream.

**Controls**

- **Amount** sets the bleach contrast and desaturation strength.
- **Tone** leaves colors untinted at Neutral (default) or applies Cool (steel blue), Warm (amber) or Emerald (cyan-green) to shadows and midtones while keeping pure black unchanged and reference white plus brighter highlights neutral.
- **Tone Amount** sets the Tone tint strength independently of Amount.

</details>

### `SD_Orton`

> Blends the image with an overexposed out-of-focus copy for a luminous glow and deep shadows.

<table><tr><td width="560">

https://github.com/user-attachments/assets/4e8a4aaa-5ca0-4838-ae19-57f82383f995

</td></tr></table>

<details>
<summary>Details</summary>

Michael Orton stacked two overexposed slides of the same scene, one sharp and
one out of focus. `SD_Orton` emulates this by blurring a copy in linear light
and multiplying it with the sharp image:
- Bright areas glow into their surroundings, while broad shadows deepen and colors gain density.
- Flat bright regions at or above reference white remain unchanged.
- Small highlights on dark backgrounds dim as the blurred surroundings suppress isolated points.

**Techniques**

- **Classic** (default) overexposes every pixel of the sharp image, dissolving fine detail into a dreamy glow.
- **Sharp** overexposes the local average instead, so fine detail keeps its contrast under the same tonal response.

**Controls**

- **Amount** sets the effect strength.
- **Radius** sets the blur radius of the glow.

</details>

## Load Order

ReShade lists shaders alphabetically rather than by processing order, placing all other SD shaders above `SD_Umbra` by default. Reorder them top-to-bottom as shown below, keeping AutoHDR shaders, input calibration (gamma or black-level fixes) and base exposure adjustments at the top above `SD_Umbra`:

| Order | Shaders | Role in stack |
| :--- | :--- | :--- |
| 1 | [`SD_Umbra`](#sd_umbra) | Sets shadow depth and black levels before overall contrast |
| 2 | [`SD_Contrast`](#sd_contrast) | Adjusts tonal contrast before color passes |
| 3 | [`SD_Polarizer`](#sd_polarizer), [`SD_SubSat`](#sd_subsat), [`SD_ColDensity`](#sd_coldensity) | Adjusts color saturation and density after tonal balance (`SD_Polarizer` first when paired with `SD_SubSat`) |
| 4 | [`SD_BleachBypass`](#sd_bleachbypass) | Deepens shadows, adds contrast and mutes color before glow (`Color` pairs downstream of `SD_Contrast`) |
| 5 | [`SD_Orton`](#sd_orton) | Applies spatial glow after tone and color passes so they do not alter blur falloff |
| 6 | Sharpening (like `lilium__rcas_hdr`) | Sharpens edges and detail after glow passes |
| 7 | Finishing passes (DoF, lens, grain, dithering) | Applies optical, grain and dithering effects after tonal passes |
| 8 | SDR-only effects | Legacy `[0, 1]` effects go last to prevent HDR highlight and wide-gamut clipping |

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
