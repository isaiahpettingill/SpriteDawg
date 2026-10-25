# SpriteDawg icon

An original pixel dog on a warm violet tile, drawn as editable SVG geometry.
The stepped silhouette connects the name to pixel-art creation. Artwork and
render script use the repository's MIT license; no Papirus artwork is copied.

## Files

- `spritedawg.svg`: scalable 64 px master, for Linux desktop installation.
- `spritedawg-{192,256,512,1024}.png`: transparent launcher/app exports.
- `icons/{16,22,24,32,48,64}/spritedawg.{svg,png}`: separately pixel-snapped
  native-size variants, suitable for a freedesktop hicolor icon hierarchy.
- `render_icons.py`: reproducible source and PNG generation using Python 3 and
  Inkscape; run `python3 art/render_icons.py` from the repository root.

## Papirus design reference

Reviewed the upstream project's [design notes](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme/blob/master/tools/work/DESIGN.md)
and [icon creation basics](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme/wiki/Icon-creation-basics)
on 2026-10-25. The project calls these informal design notes, not a formal
certification or official style guide. This icon follows that guidance; it is
not an endorsed Papirus icon.

Design decisions:

- Flat warm colors, clear silhouettes, no gradients, text objects, or clips.
- Centered base extents: 16/16, 20/22, 20/24, 28/32, 40/48, and 56/64 pixels.
- Individually snapped native-size geometry, rather than blindly scaled SVGs.
- Pure black is reserved for 20% shadows; 20% white provides the base highlight.
- Shadow/highlight displacement is 0.5 px at 22/24 and 1 px at 32/48/64;
  the 16 px icon omits both.
- A medium-value violet base remains distinct on light and dark desktops;
  cream face and dark facial features remain distinct at small sizes.

Native exports were visually checked against light and dark backgrounds, and
all SVGs were rendered successfully with Inkscape. Large PNGs are scaled from
the 64 px master; platform launcher density exports may be generated from it.
