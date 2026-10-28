import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/engine/document.dart';
import 'package:spritedawg/engine/editor_engine.dart';
import 'package:spritedawg/engine/palette_texture_brush.dart';
import 'package:spritedawg/engine/symmetry.dart';

EditorEngine canvas(int width, int height) =>
    EditorEngine()..replace(SpriteDocument.create(width, height));

const mirrorFlags = [
  'mirrorX',
  'mirrorY',
  'mirrorDiagonal',
  'mirrorAntiDiagonal',
];

Map<String, dynamic> ink([Map<String, dynamic> extra = const {}]) => {
  'tool': 'pencil',
  'points': [[1, 2]],
  'size': 1,
  'color': 0x80ff0000,
  ...extra,
};

void main() {
  test('diagonal reflection is centered, unscaled and clipped on rectangles', () {
    final diagonal = CanvasSymmetry(width: 9, height: 5, mirrorDiagonal: true);
    expect(diagonal.points(3, 1).toSet(), {(3, 1)});
    expect(diagonal.points(2, 1).toSet(), {(2, 1), (3, 0)});
    expect(diagonal.points(0, 0).toSet(), {(0, 0)});
    final anti = CanvasSymmetry(width: 9, height: 5, mirrorAntiDiagonal: true);
    expect(anti.points(2, 1).toSet(), {(2, 1), (5, 4)});
  });

  test('mixed parity reflects half-pixels with ties toward top/left once', () {
    final diagonal = CanvasSymmetry(width: 8, height: 5, mirrorDiagonal: true);
    expect(diagonal.points(2, 1).toSet(), {(2, 1), (2, 0)});
    final all = CanvasSymmetry(
      width: 8, height: 5, mirrorX: true, mirrorY: true,
      mirrorDiagonal: true, mirrorAntiDiagonal: true,
    );
    expect(all.transforms.length, 8);
    expect(all.points(2, 1).toSet(), {
      (2, 1), (5, 1), (2, 3), (5, 3), (2, 0), (4, 3), (4, 0),
    });
  });

  test('every axis combination has finite unique exact transforms', () {
    for (var mask = 0; mask < 16; mask++) {
      final symmetry = CanvasSymmetry(
        width: 15, height: 15, mirrorX: mask & 1 != 0,
        mirrorY: mask & 2 != 0, mirrorDiagonal: mask & 4 != 0,
        mirrorAntiDiagonal: mask & 8 != 0,
      );
      expect(symmetry.transforms.length, lessThanOrEqualTo(8));
      expect(symmetry.transforms.toSet().length, symmetry.transforms.length);
      for (final a in symmetry.transforms) {
        for (final b in symmetry.transforms) {
          expect(symmetry.transforms, contains(a.after(b)));
        }
      }
      expect(symmetry.points(7, 7).toList(), [(7, 7)]);
    }
  });

  test('source bounds include exactly bounded contributions from outside', () {
    for (final size in [(9, 5), (8, 5), (5, 8), (1, 8)]) {
      final symmetry = CanvasSymmetry(
        width: size.$1, height: size.$2,
        mirrorX: true, mirrorY: true,
        mirrorDiagonal: true, mirrorAntiDiagonal: true,
      );
      final bounds = symmetry.sourceBounds;
      expect(bounds.$3 - bounds.$1 + 1, lessThanOrEqualTo(10));
      expect(bounds.$4 - bounds.$2 + 1, lessThanOrEqualTo(10));
      for (var y = -12; y < 20; y++) {
        for (var x = -12; x < 20; x++) {
          if (symmetry.points(x, y).isNotEmpty) {
            expect(x, inInclusiveRange(bounds.$1, bounds.$3));
            expect(y, inInclusiveRange(bounds.$2, bounds.$4));
          }
        }
      }
    }
  });

  for (final tool in ['pencil', 'rectangle', 'ellipse', 'splatter',
    ...paletteTextureTools.where((t) => !t.startsWith('dither'))]) {
    test('$tool reflects an outside rectangular-canvas source before clipping', () {
      final e = canvas(9, 5);
      e.stroke(ink({
        'tool': tool, 'points': [[4, -1]], 'filled': true,
        'mirrorDiagonal': true, 'color': 0xffff0000,
      }));
      final pixels = e.document.composite(0);
      expect(pixels[2 * 9 + 1], isNot(0));
      expect(pixels.where((p) => p != 0).length, 1);
    });
  }

  for (final size in [(9, 9), (10, 10), (11, 7), (10, 7)]) {
    for (var mask = 1; mask < 16; mask++) {
      test('pencil ${size.$1}x${size.$2} combination $mask blends once', () {
        final e = canvas(size.$1, size.$2);
        final before = e.encode();
        final flags = <String, dynamic>{
          for (var i = 0; i < 4; i++) mirrorFlags[i]: mask & (1 << i) != 0,
        };
        final symmetry = CanvasSymmetry(
          width: size.$1, height: size.$2,
          mirrorX: flags['mirrorX'], mirrorY: flags['mirrorY'],
          mirrorDiagonal: flags['mirrorDiagonal'],
          mirrorAntiDiagonal: flags['mirrorAntiDiagonal'],
        );
        e.stroke(ink({...flags, 'points': [[3, 2], [3, 2]]}));
        final expected = symmetry.points(3, 2).map((p) => p.$2 * size.$1 + p.$1).toSet();
        final pixels = e.document.composite(0);
        for (var i = 0; i < pixels.length; i++) {
          expect(pixels[i], expected.contains(i) ? 0x80ff0000 : 0);
        }
        final after = e.encode();
        e.invoke('undo');
        expect(e.encode(), before);
        expect(e.state()['canUndo'], false);
        e.invoke('redo');
        expect(e.encode(), after);
      });
    }
  }

  test('both diagonals at a center pixel do not multiply translucent ink', () {
    final e = canvas(9, 9);
    e.stroke(ink({
      'points': [[4, 4]],
      for (final key in mirrorFlags) key: true,
    }));
    expect(e.document.composite(0)[4 * 9 + 4], 0x80ff0000);
    expect(e.document.composite(0).where((p) => p != 0).length, 1);
  });

  for (final tool in [
    'pencil', 'eraser', 'line', 'rectangle', 'ellipse', 'fill', 'gradient',
    'spray', 'airbrush', 'blur', 'jumble', 'splatter', ...paletteTextureTools,
  ]) {
    test('$tool diagonal preview commits only the selected frame/layer', () {
      final e = canvas(11, 7);
      e.edit({'action': 'addLayer', 'name': 'Paint'});
      e.edit({'action': 'addFrame'});
      e.document.editable(e.frame, e.layer).pixels.fillRange(0, 77, 0xff808080);
      final before = e.encode(), selection = (e.frame, e.layer);
      final args = ink({
        'tool': tool, 'points': [[1, 1], [6, 4]], 'size': 5,
        'seed': 19, 'strength': 50, 'filled': true,
        'secondaryColor': 0xff0000ff,
        'mirrorDiagonal': true, 'mirrorAntiDiagonal': true, 'mirrorX': true,
      });
      final undoBefore = e.state()['canUndo'];
      final preview = e.previewStroke(args);
      expect(e.encode(), before);
      expect(e.state()['canUndo'], undoBefore);
      expect((e.frame, e.layer), selection);
      e.stroke(args);
      expect(e.state()['pixels'], preview['pixels']);
      expect(e.document.composite(0).every((p) => p == 0), true);
      expect(e.document.resolved(1, 0), isNull);
      if (e.encode().toString() != before.toString()) {
        e.invoke('undo');
        expect(e.encode(), before);
      }
    });
  }

  test('fill diagonal rotates gradient direction in a separate region', () {
    final e = canvas(7, 7), c = e.document.editable(0, 0);
    c.pixels.fillRange(0, 49, 0xff00ff00);
    for (final p in [(1, 0), (2, 0), (3, 0), (0, 1), (0, 2), (0, 3)]) {
      c.pixels[p.$2 * 7 + p.$1] = 0;
    }
    e.stroke(ink({
      'tool': 'fill', 'points': [[1, 0]], 'color': 0xffff0000,
      'secondaryColor': 0xff0000ff, 'gradient': true,
      'gradientDirection': 'horizontal', 'mirrorDiagonal': true,
    }));
    final p = e.document.composite(0);
    expect([p[1], p[2], p[3]], [0xffff0000, 0xff800080, 0xff0000ff]);
    expect([p[7], p[14], p[21]], [0xffff0000, 0xff800080, 0xff0000ff]);
  });

  test('standalone gradient retains its symmetry-independent field', () {
    final a = canvas(10, 7), b = canvas(10, 7);
    final args = ink({
      'tool': 'gradient', 'points': [[1, 1], [7, 5]],
      'secondaryColor': 0x800000ff,
    });
    a.stroke(args);
    b.stroke({...args, for (final flag in mirrorFlags) flag: true});
    expect(a.document.composite(0), b.document.composite(0));
  });

  test('retouch samples the mirrored destination instead of the source dab', () {
    final e = canvas(9, 9);
    e.document.frames[0].palette = [0, 0xffff0000, 0xff0000ff];
    final c = e.document.editable(0, 0);
    c.pixels[2 * 9 + 1] = 0xffff0000;
    c.pixels[1 * 9 + 2] = 0xff0000ff;
    e.stroke(ink({
      'tool': 'ditherRetouch', 'mirrorDiagonal': true, 'color': 0xffffffff,
    }));
    final p = e.document.composite(0);
    expect(p[2 * 9 + 1], 0xffff0000);
    expect(p[1 * 9 + 2], 0xff0000ff);
  });

  test('diagonal leaves stay stable across reversed overlapping paths', () {
    const path = [(1, 1), (15, 3), (6, 11), (2, 2)];
    for (final size in [(18, 14), (19, 14)]) {
      Map<int, int> raster(List<(int, int)> points) => paletteTexturePixels(
        tool: 'leaves', points: points, width: size.$1, height: size.$2,
        size: 8, ramp: [0, 1, 2, 3, 4], seed: 42,
        mirrorDiagonal: true, mirrorAntiDiagonal: true, mirrorX: true,
      );
      final full = raster(path);
      expect(raster(path.reversed.toList()), full);
      for (final p in raster(path.take(3).toList()).entries) {
        expect(full[p.key], p.value);
      }
    }
  });

  for (final tool in ['metal', 'stripes', 'knife', 'sphere', 'bark', 'cluster']) {
    test('$tool diagonal mirrors actual texture pixels, not a reoriented stamp', () {
      Map<int, int> raster(bool mirror) => paletteTexturePixels(
        tool: tool, points: [(2, 11), (6, 14)], width: 24, height: 24,
        size: 3, ramp: [0, 1, 2, 3, 4], seed: 42,
        mirrorDiagonal: mirror,
      );
      final plain = raster(false), mirrored = raster(true);
      for (final p in plain.entries) {
        final x = p.key % 24, y = p.key ~/ 24;
        expect(mirrored[p.key], p.value);
        expect(mirrored[x * 24 + y], p.value);
      }
    });
  }
  test('negative-half ellipse outlines do not gain stray mirrored pixels', () {
    for (final (width, height, points) in [
      (5, 9, [[-4, 0], [-2, 3]]),
      (9, 5, [[-2, -2], [1, 0]]),
    ]) {
      for (final reverse in [false, true]) {
        final e = canvas(width, height);
        e.stroke(ink({
          'tool': 'ellipse',
          'points': reverse ? points.reversed.toList() : points,
          'mirrorDiagonal': true,
        }));
        expect(e.document.composite(0), [
          0x80ff0000,
          ...List<int>.filled(width * height - 1, 0),
        ]);
      }
    }
  });

}
