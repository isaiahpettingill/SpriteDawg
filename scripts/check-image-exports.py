#!/usr/bin/env python3
"""Independent interop verifier: Pillow==12.3.0. Directory then --require-avif."""
import json
from pathlib import Path
import sys
from PIL import Image

root = Path(sys.argv[1] if len(sys.argv) > 1 else 'build/export-interop')
expected = json.loads((root / 'expected.json').read_text())
for fmt in ('gif', 'apng', 'webp', 'qoi', 'avif'):
    path = root / f'fixture.{fmt}'
    if not path.exists():
        assert fmt == 'avif' and '--require-avif' not in sys.argv, f'Missing {path}'
        print('AVIF not provided (pass --require-avif in native CI)')
        continue
    with Image.open(path) as image:
        animated = fmt in ('gif', 'apng', 'webp')
        count = 3 if animated else 1
        assert image.size == (expected['width'], expected['height']), (fmt, image.size)
        assert getattr(image, 'n_frames', 1) == count, (fmt, 'frame count')
        if animated:
            loop = expected['totalPlays'] - (1 if fmt == 'gif' else 0)
            assert image.info.get('loop') == loop, (fmt, image.info)
        for frame in range(count):
            image.seek(frame)
            actual = image.convert('RGBA').tobytes()
            reference = bytearray(expected['frames'][frame])
            if fmt == 'gif':
                for p in range(3, len(reference), 4):
                    reference[p] = 255 if reference[p] >= 128 else 0
            for p in range(0, len(reference), 4):
                assert abs(actual[p + 3] - reference[p + 3]) <= (1 if fmt == 'avif' else 0), (fmt, frame, p, 'alpha', actual[p:p+4], reference[p:p+4])
                # GIF/viewers discard hidden RGB; AVIF RGB/YUV can round.
                if reference[p + 3] != 0 or fmt in ('apng', 'qoi'):
                    tolerance = 4 if fmt == 'avif' else 0
                    assert all(abs(actual[p+c] - reference[p+c]) <= tolerance for c in range(3)), (fmt, frame, p, actual[p:p+4], reference[p:p+4])
            if animated:
                assert image.info.get('duration') == expected['durationMs'][frame], (fmt, frame, image.info)
    print(f'{fmt}: independent frame/pixel/alpha/timing/loop checks passed')

metadata = json.loads((root / 'atlas.json').read_text())
w, h = expected['width'], expected['height']
with Image.open(root / 'atlas.png') as atlas:
    assert atlas.size == (2 * w + 3, 2 * h + 3)
    assert metadata['meta']['size'] == {'w': atlas.width, 'h': atlas.height}
    assert metadata['meta']['image'] == 'atlas.png'
    assert metadata['meta']['frameTags'] == [{'name': 'fixture', 'from': 0, 'to': 2, 'direction': 'forward', 'repeat': 2}]
    assert len(metadata['frames']) == 3
    for i, frame in enumerate(metadata['frames']):
        x, y = 1 + (i % 2) * (w + 1), 1 + (i // 2) * (h + 1)
        assert frame['frame'] == {'x': x, 'y': y, 'w': w, 'h': h}
        assert frame['filename'] == f'atlas-{i}.aseprite'
        assert frame['sourceSize'] == {'w': w, 'h': h}
        assert frame['spriteSourceSize'] == {'x': 0, 'y': 0, 'w': w, 'h': h}
        assert frame['rotated'] is False and frame['trimmed'] is False
        assert frame['duration'] == expected['durationMs'][i]
        assert atlas.crop((x, y, x+w, y+h)).convert('RGBA').tobytes() == bytes(expected['frames'][i])
    assert atlas.convert('RGBA').getpixel((0, 0)) == (0, 0, 0, 0)
print('spritesheet: independent atlas crop/JSON rectangle/duration/tag checks passed')
