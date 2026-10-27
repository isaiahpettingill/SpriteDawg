# Palette sources and permissions

Reviewed 2026-10-27. SpriteDawg's preset library is deliberately a subset, not an
unlicensed copy of another editor's asset collection. The existing application
license is unchanged.

## Included presets

| Preset | Entries | Basis |
| --- | ---: | --- |
| PICO-8 | 16 | CC0-1.0 |
| Game Boy Monochrome | 4 | Independently encoded numeric palette |
| CGA | 16 | Independently encoded numeric palette |
| CGA0 | 4 | Independently encoded numeric palette |
| CGA0 High | 4 | Independently encoded numeric palette |
| CGA1 | 4 | Independently encoded numeric palette |
| CGA1 High | 4 | Independently encoded numeric palette |
| ZX Spectrum | 16 | Independently encoded numeric palette |
| Master System | 64 | Independently encoded numeric palette |
| Amstrad CPC | 27 | Independently encoded numeric palette |
| Teletext | 8 | Independently encoded numeric palette |
| Grayscale 16 | 16 | Independently encoded numeric palette |
| Web Safe | 216 | Independently encoded numeric palette |
| Solarized | 16 | MIT |

All values are opaque `0xAARRGGBB` integers. Order and repeated entries are
intentional. The editor manages transparent-index allocation separately. The
largest preset has 216 colors, leaving space for an indexed transparency entry.
These are editing swatches, not emulation of each machine's video output,
sprite limits, gamma, phosphors, or palette switching.

### PICO-8 — Joseph White / Lexaloffle — CC0-1.0

The creator's [official FAQ](https://www.lexaloffle.com/pico-8.php?page=faq),
under “Can I use the PICO-8 palette and/or font for something?”, explicitly
places the palette and font under CC0. Only the 16 palette color values are
included; no font, logo, program code, or sample artwork is included.

- [CC0 legal terms](https://creativecommons.org/publicdomain/zero/1.0/legalcode)
- Local copy: [LICENSES/CC0-1.0.txt](../LICENSES/CC0-1.0.txt)
- Exact color/order reference: [Aseprite pico-8.gpl](https://github.com/aseprite/aseprite/blob/b3e34acbae812b8a1d814c2e6285343b351c8945/data/extensions/pico8-palette/pico-8.gpl)
- Reference blob: `2436ce25aa0d052a8a4e4b7514848ae8196b68ff`.
- The permission comes from Lexaloffle's CC0 dedication, **not** Aseprite's
  repository license. The standard 16 slots, black through peach, are retained.
  Credit is provided voluntarily; CC0 does not require attribution.

### Solarized — Ethan Schoonover — MIT

Acquired from the creator's own repository, not under either editor's license.

- Repository pin: `altercation/solarized@62f656a02f93c5190a8753159e34b385588d5ff3`
- [Original palette](https://github.com/altercation/solarized/blob/62f656a02f93c5190a8753159e34b385588d5ff3/gimp-palette-solarized/solarized.gpl)
- Palette blob: `40b86e5a8919b524cffd7ce02f1c6023a91ab67e`.
- [Original MIT license](https://github.com/altercation/solarized/blob/62f656a02f93c5190a8753159e34b385588d5ff3/LICENSE)
- [Retained full notice](../LICENSES/Solarized-MIT.txt)

The 16 entries are unchanged and retain the creator's order: eight neutral
colors (base03 through base3), then yellow, orange, red, magenta, violet, blue,
cyan, green. Aseprite's corresponding palette has the identical blob.
The full MIT notice is also exposed as `solarizedPaletteLicense` for inclusion
in the application's license screen and binary distribution. Do not omit that
notice when redistributing this palette.

## Independently encoded color models

These entries are newly written numeric definitions rather than copied
Aseprite/LibreSprite source code, palette-file text, comments, artwork, or
software assets. Their arithmetic and order are stated here for reproducibility.
Hardware names describe the color model; they do not imply endorsement.

- **CGA:** for indices `i = 0..15`, intensity `I = (i >> 3) & 1`.
  Compute red, green, blue as their bits (2, 1, 0 respectively) times 170,
  plus `I * 85`. At index 6, set green to 85 for brown.
  The four-color variants are selections from this RGBI table:
  CGA0 `[0,2,4,6]`; CGA0 High `[0,10,12,14]`;
  CGA1 `[0,3,5,7]`; CGA1 High `[0,11,13,15]`.
  Black is the chosen background. These are conventional digital RGB
  renderings, not sampled analog video. Reference:
  [IBM Color/Graphics Monitor Adapter documentation archive](https://www.pcjs.org/machines/pcx86/ibm/video/).
- **ZX Spectrum:** use color-index bits green=2, red=1, blue=0. Produce
  indices 0..7 with each enabled channel at 192, followed by 0..7 at 255.
  This preserves both black entries (16 slots, 15 distinct colors).
  The 192/255 approximation matches the inspected editor palette.
  Color order and brightness model:
  [Sinclair BASIC Programming manual, chapter 16](https://worldofspectrum.net/ZXBasicManual/zxmanchap16.html).
- **Master System:** iterate indices 0..63, treating the index as
  `00BBGGRR`; multiply each 2-bit component by 85. This yields all 64
  RGB222 colors in hardware order.
  [SMS Power development reference](https://www.smspower.org/Development/Palette)
  and [Maxim's palette table](https://www.smspower.org/maxim/HowToProgram/Palette)
  document the color model. This is the conventional linear approximation,
  not the nonlinear blue response of some original hardware.
- **Amstrad CPC:** levels `[0,128,255]`, nested in ascending green,
  red, then blue order (blue changes fastest). This is the 27-entry BASIC
  ink order, **not** gate-array register encoding.
  [Amstrad firmware manual appendix](https://cpctech.cpcwiki.de/docs/manual/s968ap12.pdf).
  RGB output is a three-level digital approximation.
- **Teletext:** enumerate a one-bit RGB cube, with blue changing fastest,
  then red, then green. This matches the inspected editors' swatch order.
  It is **not** Teletext control-code order, which is black, red, green,
  yellow, blue, magenta, cyan, white.
  [Yle's Teletext API documentation](https://open-developer-yle-production.c3.yle.fi/en/api/index.html)
  documents those eight colors.
- **Game Boy Monochrome:** white, light gray, dark gray, black, rendered as
  neutral `FFFFFF, AAAAAA, 555555, 000000`. Shade meanings/order:
  [Pan Docs palette registers](https://github.com/gbdev/pandocs/blob/master/src/Palettes.md).
  Equal RGB spacing is our rendering choice. This is intentionally **not**
  the green-tinted “Game Boy” palette in Aseprite/LibreSprite, nor a claim
  to reproduce the original LCD.
- **Grayscale 16:** sixteen equal RGB channels `i * 17`, `i = 0..15`,
  ordered black to white.
- **Web Safe:** all combinations of six channel levels
  `[255,204,153,102,51,0]`, nested red, green, then blue (blue changes
  fastest), for 216 entries ordered white to black. No ColorZilla code,
  palette-file metadata, or artwork is included.

As a data check, every generated CGA variant, ZX Spectrum, Master System,
CPC, Teletext, and Web Safe sequence was compared with the corresponding
Aseprite reference at the pin below and matched entry-for-entry.
The original mathematical definitions do not take Aseprite's EULA or
LibreSprite's GPL as a redistribution grant.

## Inspected editor inventories and exclusions

### Aseprite

Pin: [`aseprite/aseprite@b3e34acbae812b8a1d814c2e6285343b351c8945`](https://github.com/aseprite/aseprite/tree/b3e34acbae812b8a1d814c2e6285343b351c8945/data/extensions).

The tree has **64 contributed palette files in 12 extension packages**.
`data/palettes/` contains only `tags.gpl`, not the preset library.
There is no blanket `data/palettes/LICENSE` or per-palette-package LICENSE at
this pin. A `.gpl` filename here means **GIMP Palette format**, not a GNU GPL
license grant. The [Aseprite EULA](https://github.com/aseprite/aseprite/blob/b3e34acbae812b8a1d814c2e6285343b351c8945/EULA.txt)
is not a permissive grant to redistribute the whole collection.

Counts below are palette entries, including repeated/transparent slots:

- **Adigun A. Polack Palettes:** AAP-64 (64), AAP-Micro12 (12), AAP-Splendor128 (128), AAP-RadiantXV (15), SimpleJPC-16 (16).
- **Arne Niklas Jansson Palettes:** A64 (16), ARNE16 (16), ARNE32 (32), CGArne (16), Copper Tech (16), CPC Boy (32), Eroge Copper (16), JMP (16), Psygnosia (16).
- **Davit Masia Palettes:** Matriax8c (8).
- **Richard "DawnBringer" Fhager Palettes:** DB16 (16), DB32 (32).
- **ENDESGA Studios Palettes:** ARQ4 (4), ARQ16 (16), EDG16 (16), EDG32 (32), EDG8 (8), EN4 (4), ENOS16 (16), HEPT32 (32).
- **Hardware Palettes:** Apple II (16), Atari 2600 NTSC (256), Atari 2600 PAL (128), CGA (16), CGA0 (4), CGA0 High (4), CGA1 (4), CGA1 High (4), CGA3rd (4), CGA3rd High (4), Commodore Plus/4 (128), Commodore VIC-20 (16), Commodore 64 (16), CPC (27), Game Boy (4), Game Boy Color Type1 (38), Master System (64), MSX1 (16), MSX2 (16), NES (56), NES NTSC (56), Teletext (8), VGA 13h (256), Virtual Boy (4), ZX Spectrum (16).
- **Hyohnoo Palettes:** mail24 (24).
- **Javier Guerrero Palettes:** nyx8 (8).
- **PICO-8 Palette:** PICO-8 (16).
- **PineTreePizza Palettes:** BubbleGum16 (16), Rosy-42 (42).
- **Software Palettes:** Google UI (154), Minecraft (48), Monokai (12), SmileBASIC (18), Solarized (16), Web Safe Colors (216), Win16 (16), X11 (138).
- **Zughy Palettes:** Zughy-32 (32).

Unincluded artistic palettes are **not** declared proprietary merely because
their grants were not verified. For example, [Arne's own page](https://androidarts.com/palette/16pal.htm)
permits using/modifying his 16-color palette, but this release avoids turning
informal wording into a broader blanket grant. Some Adigun files explicitly
say “All Rights Reserved.” Creator credits, download availability, a Lospec
listing, or inclusion in another editor alone are not treated as permission
to relicense assets. Artist palettes with unverified redistribution terms,
sampled game palettes, and analog-hardware approximations are omitted.

### LibreSprite

Pin: [`LibreSprite/LibreSprite@20bd2515cf68146ad445a28e8aa4621edaf223cb`](https://github.com/LibreSprite/LibreSprite/tree/20bd2515cf68146ad445a28e8aa4621edaf223cb/data/palettes).

Its [README](https://github.com/LibreSprite/LibreSprite/blob/20bd2515cf68146ad445a28e8aa4621edaf223cb/README.md)
and [LICENSE.txt](https://github.com/LibreSprite/LibreSprite/blob/20bd2515cf68146ad445a28e8aa4621edaf223cb/LICENSE.txt)
identify GNU GPL version 2. No blanket permissive palette exception or
per-palette license file was present. This release does not copy LibreSprite
program code or relicense its asset collection as MIT.

The 38 `data/palettes/*.gpl` files are:

- `a64.gpl` — 16 entries
- `aap-16.gpl` — 16 entries
- `aap-64.gpl` — 64 entries
- `aap-splendor128.gpl` — 128 entries
- `apple-ii.gpl` — 16 entries
- `arne-paldac.gpl` — 241 entries
- `arne16.gpl` — 16 entries
- `arne32.gpl` — 31 entries
- `atari2600-ntsc.gpl` — 256 entries
- `atari2600-pal.gpl` — 128 entries
- `cg-arne.gpl` — 16 entries
- `cga.gpl` — 16 entries
- `commodore-plus4.gpl` — 128 entries
- `commodore-vic20.gpl` — 16 entries
- `commodore64.gpl` — 16 entries
- `copper-tech.gpl` — 16 entries
- `cpc-boy.gpl` — 32 entries
- `db16.gpl` — 16 entries
- `db32.gpl` — 32 entries
- `eroge-copper.gpl` — 16 entries
- `gameboy-color-type1.gpl` — 38 entries
- `gameboy.gpl` — 4 entries
- `google-ui.gpl` — 154 entries
- `jmp.gpl` — 16 entries
- `master-system.gpl` — 32 entries
- `monokai.gpl` — 12 entries
- `nes-ntsc.gpl` — 56 entries
- `nes.gpl` — 56 entries
- `pico-8.gpl` — 16 entries
- `psygnork.gpl` — 16 entries
- `smile-basic.gpl` — 18 entries
- `solarized.gpl` — 16 entries
- `teletext.gpl` — 8 entries
- `vga-13h.gpl` — 256 entries
- `web-safe-colors.gpl` — 216 entries
- `win16.gpl` — 16 entries
- `x11.gpl` — 138 entries
- `zx-spectrum.gpl` — 16 entries

Notably, LibreSprite's `master-system.gpl` is an older 32-entry selection,
whereas the independently generated SpriteDawg preset is the complete
64-entry RGB222 cube (also present in current Aseprite). The two editors'
catalogs and orders must not be assumed interchangeable. LibreSprite's
`arne32.gpl` also contains 31 entries at this pin despite its name; current
Aseprite's counterpart has 32. All 38 LibreSprite palette-file headers were
inspected; none provides an additional permissive redistribution grant.

## Rechecking or extending this library

1. Pin the upstream repository commit and exact file/blob before acquiring data.
2. Check the original creator's grant, not merely a hosting page or file extension.
3. For hardware/math presets, record the component formula, ordering, and RGB
   approximation; write the implementation independently.
4. Preserve all licensed palette slots and their order. Do not deduplicate,
   pad to 256, add opacity changes, or reorder artist palettes silently.
5. Retain required notices in both source and distributed application materials.
6. Keep runtime presets offline and immutable; any future fetching is separate
   from this built-in catalog.
