import 'dart:io';
import 'dart:typed_data';

import 'package:spritedawg/engine/editor_engine.dart';

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
  }) {
    final e = EditorEngine();
    e.invoke('new', {'width': 32, 'height': 32});
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
}
