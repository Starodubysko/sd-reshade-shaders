### ReShade shaders I missed having or was curious enough to make ✨

[![ReShade](https://img.shields.io/badge/ReShade-5.2+-E76F51.svg)](https://reshade.me)
[![Compatibility](https://img.shields.io/badge/Compatibility-SDR%20%26%20HDR-2EA043.svg)](#hdr-notes)
[![License](https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-0969DA.svg)](LICENSE)

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

<details open>
<summary><a id="sd_subsat"></a><b><code>SD_SubSat</code></b></summary>

> Subtractive saturation that decreases luminance as chroma increases to keep saturated colors dense.

https://github.com/user-attachments/assets/95eee1c1-689a-4eff-afdc-38e75074fabc

Conventional saturation pushes RGB channels apart without darkening them, so
saturated areas look brighter and clip first. `SD_SubSat` applies subtractive
color behavior: as chroma increases, it decreases luminance to keep colors
deep without clipping. Attenuating weaker channels separates colors and shifts
mixed hues slightly toward the dominant primary. Strength depends on channel
ratios rather than brightness, darkening consistently across shadows and
highlights unless Rolloff is raised.

**Techniques**

- **Subtle** (default) uses gentle rational compression without power curves for a natural response on midtones and skin.
- **Balanced** combines square-root mean density with moderate color separation for deeper overall contrast.
- **Intense** applies harmonic mean density with steep channel suppression for strong color separation.

**Controls**

- **Amount** sets the effect strength. Use `Ctrl+Click` to enter values greater than 1 if needed.
- **Rolloff** decreases the effect gradually toward bright areas. At 1, reference white and specular highlights remain unchanged.

</details>
<details open>
<summary><a id="sd_coldensity"></a><b><code>SD_ColDensity</code></b></summary>

> Darkens saturated colors by scaling RGB uniformly to keep hues and neutral tones unchanged.

https://github.com/user-attachments/assets/e451fc16-aaba-4325-8a0b-be355977d6ea

`SD_ColDensity` multiplies each RGB vector by a uniform scalar factor, preserving
channel ratios and hue. Attenuation scales with chroma and proximity to pure
primaries. At Amount 1:
- Pure primaries (red, green, blue) lose 70% of their RGB value.
- Secondaries (yellow, cyan, magenta) lose 45%, keeping composite colors from over-darkening.
- Neutral tones (white, gray, black) remain unchanged.

**Controls**

- **Amount** sets the effect strength. Values greater than 1 (`Ctrl+Click`) darken smoothly, so colors never become black.
- **Rolloff** decreases the effect gradually toward bright areas. At 1, reference white and specular highlights remain unchanged.

</details>

## HDR Notes

Both SDR and HDR are supported, with ReShade detecting the active color space
and shaders adapting automatically.

- Place these shaders above SDR-only effects in the load order. Legacy shaders
  often clamp values to `[0, 1]`, clipping HDR highlights and wide-gamut colors.
- Rolloff targets 203 nits (ITU-R BT.2408 default).
  To adjust for a custom reference white (paper white),
  set `SD_REFERENCE_WHITE <nits>` in ReShade's Preprocessor definitions
  (applies to scRGB and HDR10).
- Compared to SDR, the effect is generally milder in scRGB and HDR10 on natural
  colors, but steeper in HDR10 on pure single-channel primaries. Use `Ctrl+Click`
  on the Amount slider to enter values greater than 1 if needed.

## Support

Thanks for stopping by! If you have the means and feel like
supporting my questionable tinkering financially, you can chip in here:

- [**Tip Jar**](https://send.monobank.ua/jar/3maQ1jeZKB) (Card, Apple Pay, Google Pay)
- **Solana** (SOL, USDC, USDT):
  ```text
  FRavTdSuQ2czFqMsuj7xW9QNJdJoUxx3rMWhdmQDRh3G
  ```

## License

[CC BY-NC-SA 4.0](LICENSE) © 2026 Starodubysko
