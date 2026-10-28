import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/engine/editor_engine.dart';
import 'package:spritedawg/engine/palette_texture_brush.dart';

Map<int, int> raster(List<(int, int)> points, {int seed = 421}) =>
    paletteTexturePixels(
      tool: 'bark',
      points: points,
      width: 96,
      height: 96,
      size: 12,
      ramp: [0, 1, 2, 3, 4],
      seed: seed,
    );

void main() {
  test('bark is canvas-anchored across bends, revisits and preview growth', () {
    const path = [(8, 8), (72, 8), (72, 72), (16, 48)];
    final full = raster(path);
    final prefix = raster(path.take(3).toList());
    for (final pixel in prefix.entries) {
      expect(full[pixel.key], pixel.value);
    }
    expect(raster(path.reversed.toList()), full);
    expect(raster([...path, ...path.reversed]), full);
    expect(raster(path), full);
    expect(raster(path, seed: 422), isNot(full));
    expect(full.values.toSet(), {0, 1, 2, 3, 4});
  });

  test('bark has irregular longitudinal grain, not stripes or white noise', () {
    final points = <(int, int)>[];
    for (var y = 0; y <= 96; y += 8) {
      points.addAll(y % 16 == 0 ? [(0, y), (95, y)] : [(95, y), (0, y)]);
    }
    final pixels = raster(points);
    var across = 0, along = 0;
    for (var y = 8; y < 88; y++) {
      for (var x = 8; x < 88; x++) {
        if (pixels[y * 96 + x] != pixels[y * 96 + x + 1]) across++;
        if (pixels[y * 96 + x] != pixels[(y + 1) * 96 + x]) along++;
      }
    }
    expect(along, greaterThan(0), reason: 'Grain must wander and form knots');
    expect(across, greaterThan(along * 3));
    var checksum = 2166136261;
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        checksum = ((checksum ^ pixels[y * 96 + x]!) * 16777619) & 0xffffffff;
      }
    }
    expect(checksum, 502376854, reason: 'Deterministic grain/knot regression');
  });

  test('bark has an elongated knot with dark core and lit rim', () {
    final pixels = paletteTexturePixels(
      tool: 'bark',
      points: [(61, 62)],
      width: 96,
      height: 96,
      size: 32,
      ramp: [0, 1, 2, 3, 4],
      seed: 17,
    );
    expect(pixels[62 * 96 + 61], 0);
    expect(pixels[62 * 96 + 63], 1);
    expect(pixels[62 * 96 + 64], 3);
    expect(pixels[62 * 96 + 57], 0);
    expect(pixels[69 * 96 + 61], 1);
    expect(pixels[72 * 96 + 61], 3);
    expect(pixels[75 * 96 + 61], 0);
  });

  for (final depth in [8, 16, 32]) {
    test('bark preview matches commit and preserves mode $depth semantics', () {
      final e = EditorEngine();
      e.invoke('new', {'width': 32, 'height': 32});
      e.document.depth = depth;
      e.document.frames[0].palette = [
        0,
        0x8034251b,
        0x80593f2b,
        0x80896343,
        0x80b18a5c,
        0x80d2ac78,
        0xff00ff00,
      ];
      final palette = List<int>.of(e.document.frames[0].palette);
      final before = e.encode();
      final args = <String, dynamic>{
        'tool': 'bark',
        'points': [
          [-3, 2],
          [24, 24],
          [-3, 2],
        ],
        'size': 12,
        'seed': 421,
        'color': 0x80896343,
        'paletteIndex': 3,
        'mirrorX': true,
        'mirrorY': true,
      };
      final preview = e.previewStroke(args);
      expect(e.encode(), before);
      expect(e.state()['canUndo'], false);
      e.stroke(args);
      expect(e.state()['pixels'], preview['pixels']);
      expect(e.document.frames[0].palette, palette);
      final pixels = e.document.editable(0, 0).pixels;
      expect(pixels.any((p) => p != 0), true);
      if (depth == 8) {
        expect(pixels.every((p) => p >= 0 && p <= 5), true);
      } else {
        expect(pixels.where((p) => p != 0).every((p) => p >> 24 == 128), true);
      }
      for (var y = 0; y < 32; y++) {
        for (var x = 0; x < 32; x++) {
          expect(pixels[y * 32 + x], pixels[y * 32 + 31 - x]);
          expect(pixels[y * 32 + x], pixels[(31 - y) * 32 + x]);
        }
      }
      final after = e.encode();
      e.invoke('undo');
      expect(e.encode(), before);
      expect(e.state()['canUndo'], false);
      e.invoke('redo');
      expect(e.encode(), after);
    });
  }

  test('bark honors the exact selected duplicate index and one-pixel size', () {
    final e = EditorEngine();
    e.invoke('new', {'width': 8, 'height': 8});
    e.document.depth = 8;
    e.document.frames[0].palette = [0, 0xff896343, 0xff896343];
    e.stroke({
      'tool': 'bark',
      'points': [
        [3, 4],
      ],
      'size': 1,
      'paletteIndex': 2,
      'color': 0xff896343,
    });
    final pixels = e.document.editable(0, 0).pixels;
    expect(pixels[4 * 8 + 3], 2);
    expect(pixels.where((p) => p != 0), [2]);
  });
}
