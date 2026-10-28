#!/usr/bin/env python3
"""Compare raw EWMH ARGB window icon pixels to the bundled PNG, not its name."""
import hashlib
import json
from pathlib import Path
import re
import sys


def fingerprint(width, height, pixels):
    return {'width': width, 'height': height, 'sha256': hashlib.sha256(
        b''.join(pixel.to_bytes(4, 'big') for pixel in pixels)).hexdigest()}


def verify(text, expected):
    if '=' not in text:
        raise ValueError('Window has no icon property')
    raw = text.split('=', 1)[1].strip()
    if not re.fullmatch(r'[0-9,\s]+', raw):
        raise ValueError('Window icon property is empty or malformed')
    values = [int(item) for item in re.findall(r'\d+', raw)]
    found = False
    while values:
        if len(values) < 2:
            raise ValueError('Truncated window icon dimensions')
        width, height = values[:2]
        count = width * height
        if not (0 < width <= 1024 and 0 < height <= 1024) or len(values) < count + 2:
            raise ValueError('Invalid window icon dimensions or pixels')
        pixels, values = values[2:count + 2], values[count + 2:]
        if any(pixel < 0 or pixel > 0xffffffff for pixel in pixels):
            raise ValueError('Invalid window icon pixel')
        found |= fingerprint(width, height, pixels) == expected
    if not found:
        raise ValueError('Window icon does not match the bundled SpriteDawg PNG')


def main():
    if sys.argv[1] == 'prepare':
        # Run before the isolated test HOME hides Python's installed user packages.
        from PIL import Image
        image = Image.open(sys.argv[2]).convert('RGBA')
        pixels = [(a << 24) | (r << 16) | (g << 8) | b for r, g, b, a in image.getdata()]
        Path(sys.argv[3]).write_text(json.dumps(fingerprint(*image.size, pixels)))
    else:
        verify(Path(sys.argv[2]).read_text(), json.loads(Path(sys.argv[3]).read_text()))
        print('Window icon pixels exactly match the bundled SpriteDawg PNG.')


if __name__ == '__main__':
    main()
