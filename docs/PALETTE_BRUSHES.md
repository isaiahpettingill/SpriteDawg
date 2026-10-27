# Palette brushes

Long-hold **Metal** for Metal, Cluster, Stripes, Sphere or Knife. Dither Paint is
under Pencil; Dither Retouch is under Blur. Each group remembers its last tool.

- **Metal** uses sharp highlight/shadow bands; **Cluster** uses seeded granite-like
  patches; **Stripes** stretches patches along the stroke.
- **Sphere** lights the top of a round stamp; **Knife** lights one side relative
  to stroke direction. A stationary stamp defaults to a rightward direction.
- **Dither Paint** uses Strength to mix the original pixel toward the selected
  color using palette entries between them.
- **Dither Retouch** approximates existing artwork using nearby palette shades,
  independently of the selected ink. Exact palette matches are unchanged.

## Color and transparency

Shade selection uses Oklab perceptual lightness and chroma, not RGB distance.
Texture ramps stay in the selected color's hue/chroma and alpha family. A
palette with few suitable shades repeats them; it never invents extra shades.
Opaque strokes produce exact palette colors. RGB translucent texture paint
composites the chosen palette ink over the original pixel once, as normal paint
would; the resulting blend need not itself be a palette entry. Indexed paint
stores the chosen palette index directly.

Dither output uses actual palette entries, including available transparency.
Retouch preserves exact source alpha; if the palette has no matching alpha it
leaves that pixel alone. Fully transparent pixels are left alone by Retouch.
Dither Paint may use a transparent entry to represent fractional coverage.
The Bayer pattern is anchored to canvas coordinates, not pointer events.

Both backends use the same algorithm and regression fixtures. Strokes commit as
one undo step. Duplicate and collinear input samples do not change texture
coverage; overlap does not repeatedly blend alpha. Gradient behavior is
unchanged: RGB gradients interpolate RGB; indexed gradients use palette colors.

Oklab matrices: Björn Ottosson's [public-domain reference](https://bottosson.github.io/posts/oklab/),
2021-01-25 revision. Cluster geometry and brush shading are SpriteDawg code.
