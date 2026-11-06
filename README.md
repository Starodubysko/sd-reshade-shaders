### ReShade shaders I missed having or was curious enough to make ✨

[![ReShade](https://img.shields.io/badge/ReShade-5.2+-E76F51.svg)](https://reshade.me)
[![Compatibility](https://img.shields.io/badge/Compatibility-SDR%20%26%20HDR-2EA043.svg)](#hdr-notes)
[![License](https://img.shields.io/badge/License-MPL%202.0-0969DA.svg)](LICENSE)

> [!NOTE]
> Developed with LLM assistance and verified mathematically. Since I don't have an HDR monitor,
> if you spot any quirks across different setups, have suggestions or some feedback on the code,
> feel free to open an [issue](https://github.com/Starodubysko/sd-reshade-shaders/issues) or
> [pull request](https://github.com/Starodubysko/sd-reshade-shaders/pulls) =)

[Installation](#installation) · [Shaders](#shaders) · [HDR Notes](#hdr-notes) · [Support](#support)

## Installation

Requires ReShade 5.2+ for automatic HDR color space detection, earlier versions default to SDR.

1. Clone or [download](https://github.com/Starodubysko/sd-reshade-shaders/archive/refs/heads/main.zip) this repository.
2. Copy `Shaders/SDFX` or individual `.fx` files into `reshade-shaders/Shaders`
   in your ReShade installation, usually inside the game folder.
3. Open the in-game overlay (Home tab) and enable the shaders.
   Reload the effects if the game was already running.

## Shaders

### `SD_SubSat`

> Subtractive saturation that decreases brightness as saturation increases to keep colors dense.

https://github.com/user-attachments/assets/68ea9190-5141-4e03-a42e-bfc74a2f559b

<details>
<summary>Details</summary>

Unlike conventional saturation, which pushes RGB channels apart without
dimming them, `SD_SubSat` darkens weaker channels to separate colors and avoid
clipping. Mixed hues shift slightly toward the dominant primary, and the effect
stays consistent across shadows and highlights.

**Techniques**

- **Subtle** (default) uses gentle rational compression without power curves for a natural response on midtones and skin.
- **Balanced** combines square-root mean density with moderate channel darkening for deeper overall contrast.
- **Intense** applies harmonic mean density with a steeper curve for strong color separation.

**Controls**

- **Amount** sets the effect strength. Use `Ctrl+Click` to enter values greater than 1.
- **Rolloff** decreases the effect gradually toward bright areas. At 1, reference white and specular highlights remain unchanged.

</details>

### `SD_ColDensity`

> Darkens saturated colors by scaling RGB uniformly to keep hues and neutral tones unchanged.

https://github.com/user-attachments/assets/74c73669-dff3-4afc-a36e-294a5d12da18

<details>
<summary>Details</summary>

Strength scales with saturation and closeness to primary colors while keeping
channel ratios intact. At Amount 1:
- Primaries (red, green, blue) darken by 70%.
- Secondaries (yellow, cyan, magenta) darken by 45%, keeping mixed hues from getting too dark.
- Neutral tones (white, gray, black) remain unchanged.

**Controls**

- **Amount** sets the effect strength. Use `Ctrl+Click` to enter values greater than 1.
- **Rolloff** decreases the effect gradually toward bright areas. At 1, reference white and specular highlights remain unchanged.

</details>

### `SD_Polarizer`

> Darkens and saturates washed-out colors while keeping hues and neutral tones unchanged.

https://github.com/user-attachments/assets/c894299f-5d62-437f-ad53-29c77e8c5b7c

<details>
<summary>Details</summary>

Polarizing filters cut surface glare to reveal the rich colors beneath.
`SD_Polarizer` offers a simple RGB approximation of this effect by decreasing
the weakest channel and scaling the others proportionally:
- Partially saturated colors respond the most, gaining depth and contrast.
- Near-neutral colors, deep shadows and red-dominant hues darken less to avoid gray highlights, crushed blacks and muddy warm shades.
- Neutral tones and fully saturated colors remain unchanged.

**Controls**

- **Amount** sets the effect strength. Use `Ctrl+Click` to enter values greater than 1.
- **Rolloff** decreases the effect gradually toward bright areas. At 1, reference white and specular highlights remain unchanged.

</details>

### `SD_Orton`

> Blends the image with an overexposed out-of-focus copy for a luminous glow, rich colors and deep shadows.

https://github.com/user-attachments/assets/4e8a4aaa-5ca0-4838-ae19-57f82383f995

<details>
<summary>Details</summary>

Michael Orton stacked two overexposed slides of the same scene, one sharp and
one out of focus. `SD_Orton` emulates this by blurring a copy in linear light
and multiplying it with the sharp image:
- Bright areas glow into their surroundings, while broad shadows deepen and colors gain density.
- Flat bright regions, reference white and HDR highlights above it remain unchanged.
- Small highlights on dark backgrounds dim by design, as the blurred surroundings suppress isolated points.

**Techniques**

- **Classic** (default) overexposes every pixel of the sharp image, dissolving fine detail into a dreamy glow.
- **Sharp** overexposes the local average instead, so fine detail keeps its contrast under the same tonal response.

**Controls**

- **Amount** sets the effect strength.
- **Radius** sets the size of the glow.

</details>

## HDR Notes

Both SDR and HDR are supported, with ReShade detecting the active color space
and shaders adapting automatically.

- Place these shaders above SDR-only effects in the load order, as legacy ones
  often clamp values to `[0, 1]`, clipping HDR highlights and wide-gamut colors.
- Rolloff and `SD_Orton` target the ITU-R BT.2408 default of 203 nits.
  To match a custom reference white in scRGB or HDR10,
  set `SD_REFERENCE_WHITE <nits>` in ReShade's Preprocessor definitions.

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
