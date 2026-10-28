import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/engine/document.dart';
import 'package:spritedawg/engine/editor_engine.dart';
import 'package:spritedawg/engine/splatter_brush.dart';

EditorEngine canvas([int depth = 32]) {
  final e = EditorEngine();
  e.invoke('new', {'width': 64, 'height': 64});
  e.document.depth = depth;
  return e;
}

Map<String, dynamic> strokeArgs() => {
  'tool': 'splatter',
  'points': [
    [10, 12],
    [46, 36],
    [46, 36],
    [20, 48],
  ],
  'size': 24,
  'seed': 421,
  'color': 0x80c86432,
};

Map<int, int> raster(
  List<(int, int)> points, {
  int seed = 421,
  int size = 24,
}) => splatterPixels(
  points: points,
  width: 64,
  height: 64,
  size: size,
  seed: seed,
);

void main() {
  test(
    'splatter is seeded, sparse, varied droplets rather than held spray',
    () {
      final pixels = raster([(32, 32)]);
      expect(pixels, raster([(32, 32)]));
      expect(pixels, raster(List.filled(20, (32, 32))));
      expect(pixels, isNot(raster([(32, 32)], seed: 422)));
      expect(pixels.length, greaterThan(10));
      expect(pixels.length, lessThan(24 * 24 ~/ 2));
      expect(pixels.values.toSet().length, greaterThan(2));
      expect(pixels.values.every((a) => a >= 64 && a <= 255), true);
      // Real droplets have neighboring same-opacity pixels, unlike a dust mask.
      expect(pixels.entries.any((p) => pixels[p.key + 1] == p.value), true);
      expect(raster([(3, 4)], size: 1).keys, [4 * 64 + 3]);
    },
  );

  test(
    'splatter spacing ignores collinear pointer segmentation and repeats',
    () {
      expect(
        raster([(8, 8), (56, 32)]),
        raster([(8, 8), (20, 14), (20, 14), (32, 20), (56, 32)]),
      );
      final first = raster([(8, 8), (32, 20)]);
      final extended = raster([(8, 8), (32, 20), (56, 32)]);
      for (final p in first.entries) {
        expect(extended[p.key], greaterThanOrEqualTo(p.value));
      }
    },
  );

  for (final depth in [8, 16, 32]) {
    test(
      'splatter mode $depth preview, mirrors, exact alpha, one undo/redo',
      () {
        final e = canvas(depth);
        e.document.frames[0].palette = [0, 0x80c86432, 0x80c86432];
        final before = e.encode();
        final args = strokeArgs()
          ..addAll({'paletteIndex': 2, 'mirrorX': true, 'mirrorY': true});
        final preview = e.previewStroke(args);
        expect(e.encode(), before);
        expect(e.state()['canUndo'], false);
        expect(e.dirty, false);
        e.stroke(args);
        expect(e.state()['pixels'], preview['pixels']);
        final pixels = e.document.resolved(0, 0)!.pixels;
        final painted = pixels.where((p) => p != 0).toList();
        expect(painted, isNotEmpty);
        if (depth == 8) {
          expect(painted.toSet(), {2});
          expect(e.document.frames[0].palette, [0, 0x80c86432, 0x80c86432]);
        } else {
          expect(painted.every((p) => p >> 24 > 0 && p >> 24 <= 128), true);
          expect(painted.map((p) => p >> 24).toSet().length, greaterThan(2));
          if (depth == 32) {
            expect(painted.every((p) => p & 0xffffff == 0xc86432), true);
          } else {
            expect(painted.every((p) => p & 255 == (p >> 8 & 255)), true);
          }
        }
        for (var y = 0; y < 64; y++) {
          for (var x = 0; x < 64; x++) {
            expect(pixels[y * 64 + x], pixels[y * 64 + 63 - x]);
            expect(pixels[y * 64 + x], pixels[(63 - y) * 64 + x]);
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

  test('splatter blends source-over once, even where droplets overlap', () {
    final e = canvas();
    const background = 0x600020d0, color = 0x80c86432;
    e.document.editable(0, 0).pixels.fillRange(0, 64 * 64, background);
    final args = strokeArgs();
    e.stroke(args);
    final actual = e.document.resolved(0, 0)!.pixels;
    final mask = raster([(10, 12), (46, 36), (46, 36), (20, 48)]);
    for (var i = 0; i < actual.length; i++) {
      final coverage = mask[i];
      final alpha = coverage == null ? 0 : (128 * coverage + 127) ~/ 255;
      expect(actual[i], over(background, (color & 0xffffff) | (alpha << 24)));
    }
  });

  test('zero-alpha and off-canvas splatter are true no-ops', () {
    for (final depth in [8, 16, 32]) {
      final e = canvas(depth);
      e.document.frames[0].palette = [0, 0x80c86432, 0x00c86432];
      final before = e.encode();
      e.stroke(strokeArgs()..addAll({'color': 0x00c86432, 'paletteIndex': 1}));
      expect(e.encode(), before);
      expect(e.state()['canUndo'], false);
      expect(e.dirty, false);
      e.stroke(
        strokeArgs()
          ..['points'] = [
            [-100, -100],
            [-80, -80],
          ],
      );
      expect(e.encode(), before);
      expect(e.state()['canUndo'], false);
      if (depth == 8) {
        for (final index in [0, 2]) {
          e.stroke(strokeArgs()..['paletteIndex'] = index);
          expect(e.encode(), before);
          expect(e.state()['canUndo'], false);
        }
      }
    }
  });

  test('splatter edits only the selected frame/layer and respects locks', () {
    final e = canvas();
    e.edit({'action': 'addLayer', 'name': 'Paint'});
    e.edit({'action': 'addFrame'});
    e.stroke(strokeArgs());
    expect(e.document.frames[0].cels.every((c) => c == null), true);
    expect(e.document.frames[1].cels[0], isNull);
    expect(e.document.frames[1].cels[1], isNotNull);
    final before = e.encode();
    e.document.layers[1].flags &= ~2;
    expect(() => e.stroke(strokeArgs()), throwsA(isA<FormatException>()));
    e.document.layers[1].flags |= 2;
    expect(e.encode(), before);
  });
}
