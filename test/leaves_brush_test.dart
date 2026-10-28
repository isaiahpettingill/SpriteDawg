import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/engine/editor_engine.dart';
import 'package:spritedawg/engine/palette_texture_brush.dart';

Map<int, int> raster(List<(int, int)> points, {int seed = 421}) =>
    paletteTexturePixels(
      tool: 'leaves',
      points: points,
      width: 96,
      height: 96,
      size: 12,
      ramp: [0, 1, 2, 3, 4],
      seed: seed,
    );

void main() {
  test(
    'leaves is canvas-anchored across bends, revisits and preview growth',
    () {
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
    },
  );

  test('leaves form coherent shaded shapes rather than cluster noise', () {
    final points = <(int, int)>[];
    for (var y = 0; y <= 96; y += 16) {
      points.addAll(y % 32 == 0 ? [(0, y), (95, y)] : [(95, y), (0, y)]);
    }
    Map<int, int> field(String tool) => paletteTexturePixels(
      tool: tool,
      points: points,
      width: 96,
      height: 96,
      size: 32,
      ramp: [0, 1, 2, 3, 4],
      seed: 421,
    );
    final leaves = field('leaves');
    expect(leaves, isNot(field('cluster')));
    expect(leaves.values.toSet(), {0, 1, 2, 3, 4});
    var coherent = 0, litRims = 0;
    for (var y = 8; y < 88; y++) {
      for (var x = 8; x < 88; x++) {
        final shade = leaves[y * 96 + x]!;
        final right = leaves[y * 96 + x + 1]!;
        if (shade == right) coherent++;
        if (shade <= 2 && right >= 3) litRims++;
      }
    }
    expect(coherent, greaterThan(3000));
    expect(litRims, greaterThan(100));
  });

  test('leaves resampling ignores duplicate and collinear events', () {
    expect(
      raster([(8, 20), (72, 20)]),
      raster([(8, 20), (8, 20), (32, 20), (48, 20), (72, 20)]),
    );
  });

  for (final depth in [8, 16, 32]) {
    test(
      'leaves preview matches commit and preserves mode $depth semantics',
      () {
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
          'tool': 'leaves',
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
          expect(
            pixels.where((p) => p != 0).every((p) => p >> 24 == 128),
            true,
          );
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
      },
    );
  }

  test(
    'leaves honors the exact selected duplicate index and one-pixel size',
    () {
      final e = EditorEngine();
      e.invoke('new', {'width': 8, 'height': 8});
      e.document.depth = 8;
      e.document.frames[0].palette = [0, 0xff896343, 0xff896343];
      e.stroke({
        'tool': 'leaves',
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
    },
  );
}
