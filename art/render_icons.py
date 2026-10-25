#!/usr/bin/env python3
"""Build original SpriteDawg SVGs and PNGs; requires Inkscape on PATH."""
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
SIZES = {16: (0, 16), 22: (1, 20), 24: (2, 20), 32: (2, 28), 48: (4, 40), 64: (4, 56)}

def svg(size):
    margin, extent = SIZES[size]
    def x(value): return margin + round(value * extent / 56)
    def path(points):
        return 'M' + ' '.join(f'{x(a)},{x(b)}' for a,b in points) + 'Z'
    def rect(a,b,c,d,color):
        return f'<path fill="{color}" d="M{x(a)} {x(b)}H{x(c)}V{x(d)}H{x(a)}Z"/>'
    radius = max(2, round(extent/7))
    shadow = 0 if size == 16 else .5 if size in (22,24) else 1
    body = path([(16,12),(40,12),(40,16),(48,16),(48,36),(40,36),(40,44),(36,44),(36,48),(20,48),(20,44),(16,44),(16,36),(8,36),(8,16),(16,16)])
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">',
             '<title>SpriteDawg</title>',
             '<desc>An original pixel dog on a warm violet tile. MIT licensed.</desc>']
    if shadow:
        parts.append(f'<rect x="{margin}" y="{margin+shadow}" width="{extent}" height="{extent}" rx="{radius}" fill="#000000" opacity=".2"/>')
    parts.append(f'<rect x="{margin}" y="{margin}" width="{extent}" height="{extent}" rx="{radius}" fill="#7466a3"/>')
    if shadow:
        m, e, r, s = margin, extent, radius, shadow
        # Difference between the base and its downward translation: no clip paths.
        parts.append(f'<path fill="#ffffff" opacity=".2" d="M{m+r} {m}H{m+e-r}Q{m+e} {m} {m+e} {m+r}V{m+r+s}Q{m+e} {m+s} {m+e-r} {m+s}H{m+r}Q{m} {m+s} {m} {m+r+s}V{m+r}Q{m} {m} {m+r} {m}Z"/>')
        parts.append(f'<path d="{body}" fill="#000000" opacity=".2" transform="translate(0 {shadow})"/>')
    parts.append(f'<path d="{body}" fill="#f5e6c8"/>')
    # Floppy ears, square eyes, nose and a small tongue: deliberately sparse.
    parts += [rect(8,16,16,36,'#b88a60'), rect(40,16,48,36,'#b88a60'),
              rect(20,24,24,28,'#403743'), rect(32,24,36,28,'#403743'),
              rect(24,32,32,36,'#403743'), rect(26,36,30,40,'#403743'),
              rect(24,40,32,44,'#cc7574')]
    parts.append('</svg>')
    return '\n'.join(parts)+'\n'

for size in SIZES:
    target = HERE / 'icons' / str(size)
    target.mkdir(parents=True, exist_ok=True)
    source = target / 'spritedawg.svg'
    source.write_text(svg(size))
    subprocess.run(['inkscape',str(source),'--export-type=png',f'--export-filename={target / "spritedawg.png"}'], check=True, capture_output=True)
(HERE / 'spritedawg.svg').write_text(svg(64))
for size in (192,256,512,1024):
    subprocess.run(['inkscape',str(HERE / 'spritedawg.svg'),'--export-type=png',f'--export-width={size}',f'--export-height={size}',f'--export-filename={HERE / f"spritedawg-{size}.png"}'], check=True, capture_output=True)
print('Generated six pixel-aligned SVG/PNG pairs, scalable SVG, and four large PNGs.')
