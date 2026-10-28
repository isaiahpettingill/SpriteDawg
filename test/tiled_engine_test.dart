import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/engine/document.dart';
import 'package:spritedawg/engine/editor_engine.dart';
import 'package:spritedawg/engine/palette_texture_brush.dart';
import 'package:spritedawg/engine/symmetry.dart';
import 'package:spritedawg/engine/splatter_brush.dart';

const tilePalette = [
  0,
  0x80241c0b,
  0x80654b16,
  0x80ae852a,
  0x80e0bd55,
  0x80ffefae,
  0xff1255ff,
];
const tileTools = [
  'pencil',
  'eraser',
  'line',
  'rectangle',
  'ellipse',
  'fill',
  'gradient',
  'spray',
  'airbrush',
  'blur',
  'jumble',
  'splatter',
  ...paletteTextureTools,
];

EditorEngine tile(
  int width,
  int height, {
  int depth = 32,
  bool pattern = false,
}) {
  final d = SpriteDocument.create(width, height)..depth = depth;
  d.frames[0].palette = List.of(tilePalette);
  if (pattern) {
    final c = d.editable(0, 0);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        c.pixels[y * width + x] = depth == 8
            ? 1 + (x + 2 * y) % 6
            : d.drawingColor(
                0x80000000 | (x * 23 % 256) << 16 | (y * 31 % 256) << 8 | 47,
                0,
              );
      }
    }
  }
  return EditorEngine()..replace(d);
}

Map<String, dynamic> tiledStroke([Map<String, dynamic> extra = const {}]) => {
  'tool': 'pencil',
  'points': [
    [0, 0],
  ],
  'color': 0x80ae852a,
  'size': 1,
  'wrap': true,
  ...extra,
};

void main() {
  test('negative seam crossings rasterize continuous lines before modulo', () {
    final e = tile(8, 3);
    e.stroke(
      tiledStroke({
        'points': [
          [-1, 1],
          [1, 1],
        ],
      }),
    );
    final pixels = e.document.composite(0);
    for (var y = 0; y < 3; y++) {
      for (var x = 0; x < 8; x++) {
        expect(
          pixels[y * 8 + x],
          y == 1 && {7, 0, 1}.contains(x) ? 0x80ae852a : 0,
        );
      }
    }
  });

  test('multiple tile crossings and wide brush overlap blend only once', () {
    final e = tile(8, 3), before = tile(8, 3).encode();
    e.stroke(
      tiledStroke({
        'points': [
          [7, 1],
          [17, 1],
          [-4, 1],
        ],
        'size': 5,
      }),
    );
    expect(e.document.composite(0).every((p) => p == 0x80ae852a), true);
    e.invoke('undo');
    expect(e.encode(), before);
    expect(e.state()['canUndo'], false);
  });

  test('wrap canonicalizes before rectangular diagonal mirrors and dedups', () {
    for (var flags = 0; flags < 16; flags++) {
      final s = CanvasSymmetry(
        width: 8,
        height: 5,
        wrap: true,
        mirrorX: flags & 1 != 0,
        mirrorY: flags & 2 != 0,
        mirrorDiagonal: flags & 4 != 0,
        mirrorAntiDiagonal: flags & 8 != 0,
      );
      final baseline = s.points(2, 1).toSet();
      expect(s.points(-6, -4).toSet(), baseline);
      expect(s.points(10, 6).toSet(), baseline);
      expect(baseline.length, lessThanOrEqualTo(8));
      expect(
        baseline.every((p) => p.$1 >= 0 && p.$1 < 8 && p.$2 >= 0 && p.$2 < 5),
        true,
      );
    }
  });

  test('periodic representative exactly minimizes each filled-shape axis', () {
    for (var period = 1; period <= 9; period++) {
      for (var start = -9; start <= 9; start++) {
        for (var end = start; end <= start + 18; end++) {
          for (var coordinate = 0; coordinate < period; coordinate++) {
            final candidates = [
              for (var p = start; p <= end; p++)
                if (p % period == coordinate) p,
            ];
            final p = periodicRepresentative(start, end, coordinate, period);
            if (candidates.isEmpty) {
              expect(p, isNull);
            } else {
              expect(candidates, contains(p));
              final distance = (2 * p! - start - end).abs();
              expect(
                candidates.every(
                  (c) => (2 * c - start - end).abs() >= distance,
                ),
                true,
              );
            }
          }
        }
      }
    }
  });

  for (final tool in ['rectangle', 'ellipse']) {
    test('wrapped filled $tool equals brute-force world coverage', () {
      for (final box in [(-2, -1, 3, 3), (-7, -4, 12, 9), (7, 3, 10, 6)]) {
        final (l, t, r, b) = box;
        final expected = List<int>.filled(40, 0);
        final w = r - l + 1, h = b - t + 1;
        for (var y = t; y <= b; y++) {
          for (var x = l; x <= r; x++) {
            final dx = 2 * x - l - r, dy = 2 * y - t - b;
            if (tool == 'rectangle' ||
                dx * dx * h * h + dy * dy * w * w <= w * w * h * h) {
              expected[(y % 5) * 8 + x % 8] = 0x80ae852a;
            }
          }
        }
        final e = tile(8, 5);
        e.stroke(
          tiledStroke({
            'tool': tool,
            'filled': true,
            'points': [
              [l, t],
              [r, b],
            ],
          }),
        );
        expect(e.document.composite(0), expected);
      }
    });
    test('extreme wrapped $tool is bounded and paints each pixel once', () {
      final e = tile(8, 5);
      e.stroke(
        tiledStroke({
          'tool': tool,
          'filled': true,
          'points': [
            [-8192, -8192],
            [8192, 8192],
          ],
        }),
      );
      expect(e.document.composite(0).every((p) => p == 0x80ae852a), true);
    });
  }

  test('fill crosses only equal-color toroidal neighbors', () {
    final e = tile(8, 3), c = e.document.editable(0, 0);
    c.pixels.fillRange(0, 24, 0xff00ff00);
    c.pixels[8] = 0;
    c.pixels[15] = 0;
    e.stroke(
      tiledStroke({
        'tool': 'fill',
        'points': [
          [-1, 1],
        ],
      }),
    );
    final pixels = e.document.composite(0);
    expect(pixels[8], 0x80ae852a);
    expect(pixels[15], 0x80ae852a);
    expect(pixels[9], 0xff00ff00);
  });

  test('blur samples the opposite edge and jumble preserves native pixels', () {
    for (final tool in ['blur', 'jumble']) {
      final e = tile(4, 1), c = e.document.editable(0, 0);
      c.pixels.fillRange(0, 4, 0xff000000);
      c.pixels[3] = 0xffffffff;
      e.stroke(tiledStroke({'tool': tool, 'strength': 100, 'seed': 1}));
      final p = e.document.composite(0);
      if (tool == 'blur') {
        expect(p[0], 0xff555555);
      } else {
        expect(p, [0xffffffff, 0xff000000, 0xff000000, 0xff000000]);
      }
    }
  });

  test(
    'retouch reads the wrapped target original, not the source dab color',
    () {
      final e = tile(8, 3);
      e.document.frames[0].palette = [0, 0xffff0000, 0xff0000ff];
      final c = e.document.editable(0, 0);
      c.pixels[8] = 0xffff0000;
      c.pixels[15] = 0xff0000ff;
      e.stroke(
        tiledStroke({
          'tool': 'ditherRetouch',
          'points': [
            [0, 1],
          ],
          'size': 3,
        }),
      );
      expect(e.document.composite(0)[8], 0xffff0000);
      expect(e.document.composite(0)[15], 0xff0000ff);
    },
  );

  for (final tool in tileTools) {
    for (final dimensions in [(8, 5), (1, 1), (1, 7)]) {
      test(
        '$tool repeats identically on $dimensions with preview and undo parity',
        () {
          final (w, h) = dimensions;
          final a = tile(w, h, pattern: true), b = tile(w, h, pattern: true);
          final points = [
            [w - 1, h - 1],
            [w + 1, h + 1],
            [w + 1, h + 1],
          ];
          final args = tiledStroke({
            'tool': tool,
            'points': points,
            'size': 5,
            'seed': 42,
            'strength': 50,
            'density': 12,
            'paletteIndex': 3,
            'secondaryColor': 0x20808080,
            'gradient': true,
            'filled': true,
            'mirrorX': true,
            'mirrorDiagonal': true,
            'mirrorAntiDiagonal': true,
          });
          final before = a.encode(), preview = a.previewStroke(args);
          expect(a.encode(), before);
          expect(a.state()['canUndo'], false);
          a.stroke(args);
          b.stroke({
            ...args,
            'points': points.map((p) => [p[0] - 2 * w, p[1] - h]).toList(),
          });
          expect(a.state()['pixels'], preview['pixels']);
          expect(a.document.composite(0), b.document.composite(0));
          if (a.state()['canUndo'] == true) {
            final after = a.encode();
            a.invoke('undo');
            expect(a.encode(), before);
            expect(a.state()['canUndo'], false);
            a.invoke('redo');
            expect(a.encode(), after);
          }
        },
      );
    }
  }

  test('negative-center outlined ellipses match on every repeated tile', () {
    final a = tile(5, 9), b = tile(5, 9);
    a.stroke(
      tiledStroke({
        'tool': 'ellipse',
        'points': [
          [-4, 0],
          [-2, 3],
        ],
      }),
    );
    b.stroke(
      tiledStroke({
        'tool': 'ellipse',
        'points': [
          [1, 9],
          [3, 12],
        ],
      }),
    );
    expect(a.document.composite(0), b.document.composite(0));
  });

  test(
    'wrapped strokes edit only selected frame/layer, including indexed alpha',
    () {
      final e = tile(7, 5, depth: 8);
      e.edit({'action': 'addLayer', 'name': 'Wrapped'});
      e.edit({'action': 'addFrame'});
      final before = e.encode();
      final args = tiledStroke({
        'points': [
          [-1, -1],
          [1, 1],
        ],
        'paletteIndex': 3,
      });
      final preview = e.previewStroke(args);
      expect(e.encode(), before);
      e.stroke(args);
      expect(e.state()['pixels'], preview['pixels']);
      expect(e.document.resolved(0, 0), isNull);
      expect(e.document.resolved(1, 0), isNull);
      expect(
        e.document.resolved(1, 1)!.pixels.every((p) => p == 0 || p == 3),
        true,
      );
      e.invoke('undo');
      expect(e.encode(), before);
    },
  );

  test('normal view strokes keep clipping rather than wrapping', () {
    final e = tile(8, 3);
    e.stroke(
      tiledStroke({
        'wrap': false,
        'points': [
          [-1, 1],
          [1, 1],
        ],
      }),
    );
    final p = e.document.composite(0);
    expect(p[15], 0);
    expect(p[8], 0x80ae852a);
    expect(p[9], 0x80ae852a);
  });
  test(
    'pure texture fields and splatter seeds repeat in canonical tile space',
    () {
      const path = [(6, 3), (10, 7), (12, 7)];
      final shifted = path.map((p) => (p.$1 - 16, p.$2 + 5)).toList();
      for (final tool in paletteTextureTools) {
        Map<int, int> raster(List<(int, int)> points) => paletteTexturePixels(
          tool: tool,
          points: points,
          width: 8,
          height: 5,
          size: 7,
          ramp: [0, 1, 2, 3, 4],
          seed: 42,
          wrap: true,
          mirrorDiagonal: true,
        );
        expect(raster(path), raster(shifted), reason: tool);
      }
      Map<int, int> splatter(List<(int, int)> points) => splatterPixels(
        points: points,
        width: 8,
        height: 5,
        size: 7,
        seed: 42,
        wrap: true,
        mirrorDiagonal: true,
      );
      expect(splatter(path), splatter(shifted));
    },
  );
}
