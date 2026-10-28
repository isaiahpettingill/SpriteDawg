import 'dart:io';
import 'dart:typed_data';

import 'package:spritedawg/engine/editor_engine.dart';
import 'package:spritedawg/engine/palette_texture_brush.dart';

/// Generate portable output consumed by Android's cross-backend regression test.
/// Run: dart tool/brush_interop.dart /tmp/spritedawg-dart-brush-interop
/// Then set SPRITEDAWG_BRUSH_INTEROP_DIR to that directory for native tests.
void main(List<String> arguments) {
  final root = Directory(
    arguments.isEmpty ? '/tmp/spritedawg-dart-brush-interop' : arguments.first,
  )..createSync(recursive: true);
  void run(
    String name,
    bool pattern,
    Map<String, dynamic> args, {
    bool barrier = false,
    List<int>? palette,
    bool indexed = false,
    int? background,
  }) {
    final e = EditorEngine();
    e.invoke('new', {'width': 32, 'height': 32});
    if (palette != null) e.document.frames[0].palette = palette;
    if (indexed) {
      e.document.depth = 8;
      e.document.transparentIndex = 0;
    }
    final c = e.document.editable(0, 0);
    if (pattern) {
      for (var y = 0; y < 32; y++) {
        for (var x = 0; x < 32; x++) {
          c.pixels[y * 32 + x] =
              ((x * 17 + y * 13) % 256) << 24 |
              ((x * 7) % 256) << 16 |
              ((y * 9) % 256) << 8 |
              ((x + y) * 5) % 256;
        }
      }
    }
    if (background != null) c.pixels.fillRange(0, 1024, background);
    if (barrier) {
      for (var y = 0; y < 32; y++) {
        c.pixels[y * 32 + 16] = 0xff00ff00;
      }
    }
    e.invoke('stroke', args);
    final actual = e.state()['pixels'] as Uint8List;
    File('${root.path}/$name.rgba').writeAsBytesSync(actual);
    stdout.writeln('Wrote $name: ${actual.length} RGBA bytes');
  }

  run('gradient', false, {
    'tool': 'fill',
    'points': [
      [2, 3],
    ],
    'gradient': true,
    'gradientDirection': 'horizontal',
    'color': 0xffc86432,
    'secondaryColor': 0x10010203,
    'mirrorX': true,
  }, barrier: true);
  run('linear-gradient', true, {
    'tool': 'gradient',
    'points': [
      [-8192, -8192],
      [8192, 8192],
    ],
    'color': 0x80ff0000,
    'secondaryColor': 0x200000ff,
    'mirrorX': true,
    'size': 32,
  });
  run('spray', false, {
    'tool': 'spray',
    'points': [
      [4, 5],
      [18, 19],
      [20, 19],
    ],
    'size': 8,
    'density': 70,
    'seed': 42,
    'mirrorX': true,
    'mirrorY': true,
    'color': 0x80c86432,
  });
  for (final indexed in [false, true]) {
    run(
      indexed ? 'splatter-indexed' : 'splatter',
      !indexed,
      {
        'tool': 'splatter',
        'points': [[-3, 5], [18, 19], [18, 19], [20, 19]],
        'size': 20,
        'seed': 42,
        'mirrorX': true,
        'mirrorY': true,
        'color': 0x80c86432,
        if (indexed) 'paletteIndex': 2,
      },
      indexed: indexed,
      palette: indexed ? [0, 0x80c86432, 0x80c86432] : null,
    );
  }
  run('airbrush', true, {
    'tool': 'airbrush',
    'points': [
      [5, 5],
      [5, 5],
      [13, 15],
    ],
    'size': 9,
    'strength': 20,
    'color': 0x80c86432,
    'mirrorX': true,
    'mirrorY': true,
  });
  run('alpha', true, {
    'tool': 'pencil',
    'points': [
      [5, 5],
      [13, 15],
      [5, 5],
    ],
    'size': 5,
    'color': 0x80c86432,
    'mirrorX': true,
  });
  run('blur', true, {
    'tool': 'blur',
    'points': [
      [8, 8],
      [20, 12],
    ],
    'size': 5,
    'strength': 67,
    'mirrorX': true,
    'mirrorY': true,
  });
  run('jumble', true, {
    'tool': 'jumble',
    'points': [
      [10, 10],
      [16, 17],
    ],
    'size': 8,
    'strength': 70,
    'seed': 99,
    'mirrorX': true,
  });
  run('ellipse', false, {
    'tool': 'ellipse',
    'points': [
      [18, 22],
      [3, 5],
    ],
    'filled': true,
    'color': 0x80c86432,
    'mirrorX': true,
  });
  const palette = [
    0,
    0xff241c0b,
    0xff654b16,
    0xffae852a,
    0xffe0bd55,
    0xffffefae,
    0xff1255ff,
  ];
  for (final tool in [
    'metal',
    'cluster',
    'stripes',
    'sphere',
    'knife',
    'bark',
    'leaves',
    'ditherPaint',
    'ditherRetouch',
  ]) {
    final args = <String, dynamic>{
      'tool': tool,
      'points': [
        [4, 5],
        [18, 19],
        [20, 19],
      ],
      'size': 9,
      'seed': 42,
      'strength': 50,
      'color': 0xffae852a,
      'paletteIndex': 3,
      'mirrorX': true,
      'mirrorY': true,
    };
    run(
      'texture-$tool',
      true,
      args,
      palette: palette,
      background: tool == 'ditherRetouch' ? 0xffa5802c : null,
    );
    run(
      'texture-indexed-$tool',
      false,
      args,
      palette: palette,
      indexed: true,
      background: 2,
    );
    run(
      'texture-alpha-$tool',
      false,
      {...args, 'color': 0x80ae852a},
      palette: [
        0,
        0x80241c0b,
        0x80654b16,
        0x80ae852a,
        0x80e0bd55,
        0x80ffefae,
        0xff1255ff,
      ],
      background: 0x80a5802c,
    );
  }
  // Small canvases expose diagonal center, clipping, parity, overlap and
  // directional texture differences without bloating the checked-in fixtures.
  for (final (width, height) in [(9, 9), (10, 10), (11, 7), (10, 7)]) {
    for (final depth in [8, 16, 32]) {
      for (final tool in [
        'pencil', 'eraser', 'line', 'rectangle', 'ellipse', 'fill', 'gradient',
        'spray', 'airbrush', 'blur', 'jumble', 'splatter', ...paletteTextureTools,
      ]) {
        final e = EditorEngine();
        e.invoke('new', {'width': width, 'height': height});
        final d = e.document;
        d.depth = depth;
        d.frames[0].palette = [
          0, 0x80241c0b, 0x80654b16, 0x80ae852a, 0x80e0bd55, 0x80ffefae,
          0xff1255ff,
        ];
        final c = d.editable(0, 0);
        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            c.pixels[y * width + x] = depth == 8
                ? 1 + (x + 2 * y) % 6
                : d.drawingColor(
                    ((x * 17 + y * 13) % 256) << 24 |
                    ((x * 7) % 256) << 16 |
                    ((y * 9) % 256) << 8 |
                    ((x + y) * 5) % 256,
                    0,
                  );
          }
        }
        e.stroke({
          'tool': tool,
          'points': [tool == 'fill' ? [1, 2] : [-2, 1], [width - 3, height - 3],
            [width - 3, height - 3], [2, height - 2]],
          'size': 5, 'seed': 42, 'density': 12, 'strength': 50,
          'color': 0x80ae852a, 'paletteIndex': 3, 'filled': true,
          'gradient': true, 'gradientDirection': 'horizontal',
          'secondaryColor': 0x20808080,
          'mirrorDiagonal': true, 'mirrorAntiDiagonal': height.isOdd,
          'mirrorX': width.isEven, 'mirrorY': depth == 16,
        });
        final name = 'symmetry-${width}x$height-$depth-$tool';
        final bytes = e.state()['pixels'] as Uint8List;
        File('${root.path}/$name.rgba').writeAsBytesSync(bytes);
      }
    }
  }

  // Negative half-pixel outline coordinates must use Dart's away-from-zero
  // rounding in the native engine too, before a diagonal brings them onscreen.
  for (final (width, height, from, to) in [
    (5, 9, [-4, 0], [-2, 3]),
    (9, 5, [-2, -2], [1, 0]),
  ]) {
    for (final reverse in [false, true]) {
      final e = EditorEngine();
      e.invoke('new', {'width': width, 'height': height});
      e.stroke({
        'tool': 'ellipse',
        'points': reverse ? [to, from] : [from, to],
        'size': 1,
        'color': 0x80ff0000,
        'mirrorDiagonal': true,
      });
      final name = 'negative-outline-${width}x$height-$reverse';
      File('${root.path}/$name.rgba').writeAsBytesSync(
        e.state()['pixels'] as Uint8List,
      );
    }
  }

  for (final (width, height) in [(8, 5), (7, 7), (1, 1), (1, 7)]) {
    for (final depth in [8, 16, 32]) {
      for (final tool in [
        'pencil', 'eraser', 'line', 'rectangle', 'ellipse', 'fill', 'gradient',
        'spray', 'airbrush', 'blur', 'jumble', 'splatter', ...paletteTextureTools,
      ]) {
        final e = EditorEngine();
        e.invoke('new', {'width': width, 'height': height});
        final d = e.document;
        d.depth = depth;
        d.frames[0].palette = [
          0, 0x80241c0b, 0x80654b16, 0x80ae852a, 0x80e0bd55, 0x80ffefae,
          0xff1255ff,
        ];
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
        e.stroke({
          'tool': tool, 'wrap': true,
          'points': [[-1, -1], [1, 1], [width + 1, 1], [width + 1, 1]],
          'size': 5, 'seed': 42, 'density': 12, 'strength': 50,
          'color': 0x80ae852a, 'paletteIndex': 3,
          'filled': depth != 16, 'gradient': true,
          'gradientDirection': 'horizontal', 'secondaryColor': 0x20808080,
          'mirrorDiagonal': true, 'mirrorAntiDiagonal': height.isOdd,
          'mirrorX': width.isEven, 'mirrorY': depth == 16,
        });
        final name = 'wrap-${width}x$height-$depth-$tool';
        File('${root.path}/$name.rgba').writeAsBytesSync(
          e.state()['pixels'] as Uint8List,
        );
      }
    }
  }

}
