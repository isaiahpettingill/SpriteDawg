import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/engine/editor_engine.dart';

EditorEngine canvas([int w = 8, int h = 8]) {
  final e = EditorEngine();
  e.invoke('new', {'width': w, 'height': h});
  return e;
}

void draw(
  EditorEngine e,
  String tool,
  List<List<int>> points, [
  Map<String, dynamic> args = const {},
]) => e.invoke('stroke', {
  'tool': tool,
  'points': points,
  'color': 0xffff0000,
  ...args,
});
void main() {
  for (final tool in ['rectangle', 'ellipse']) {
    test(
      '$tool filled reversed drag is identical, clipped and single undo',
      () {
        final a = canvas(), b = canvas();
        draw(
          a,
          tool,
          [
            [1, 1],
            [6, 5],
          ],
          {'filled': true, 'size': 8},
        );
        draw(
          b,
          tool,
          [
            [6, 5],
            [1, 1],
          ],
          {'filled': true, 'size': 1},
        );
        expect(a.document.composite(0), b.document.composite(0));
        expect(a.document.composite(0)[3 * 8 + 3], 0xffff0000);
        expect(a.document.composite(0)[0], 0);
        final after = a.encode();
        a.invoke('undo');
        expect(a.document.composite(0).every((p) => p == 0), true);
        a.invoke('redo');
        expect(a.encode(), after);
        draw(
          a,
          tool,
          [
            [-2, -2],
            [1, 1],
          ],
          {'filled': true},
        );
        expect(a.document.width, 8);
      },
    );
    test('$tool filled one-pixel and skinny degenerates work', () {
      final e = canvas(4, 4);
      draw(
        e,
        tool,
        [
          [2, 2],
          [2, 2],
        ],
        {'filled': true},
      );
      expect(e.document.composite(0).where((p) => p != 0).length, 1);
      draw(
        e,
        tool,
        [
          [0, 0],
          [0, 3],
        ],
        {'filled': true},
      );
      for (var y = 0; y < 4; y++) {
        expect(e.document.composite(0)[y * 4], 0xffff0000);
      }
    });
  }
  test('filled 4x4 ellipse samples twelve pixels without bbox corners', () {
    final e = canvas(4, 4);
    draw(
      e,
      'ellipse',
      [
        [0, 0],
        [3, 3],
      ],
      {'filled': true},
    );
    expect(e.document.composite(0).where((p) => p != 0).length, 12);
    expect(e.document.composite(0)[0], 0);
  });
  test(
    'gradient only floods exact connected region even primary matches old',
    () {
      final e = canvas(5, 1), c = e.document.editable(0, 0);
      c.pixels[3] = 0xff00ff00;
      draw(
        e,
        'fill',
        [
          [0, 0],
        ],
        {
          'color': 0,
          'secondaryColor': 0xff0000ff,
          'gradient': true,
          'gradientDirection': 'horizontal',
        },
      );
      expect(e.document.resolved(0, 0)!.pixels, [
        0,
        0x80000080,
        0xff0000ff,
        0xff00ff00,
        0,
      ]);
    },
  );
  test('vertical alpha gradient uses nearest channel interpolation', () {
    final e = canvas(1, 3);
    draw(
      e,
      'fill',
      [
        [0, 0],
      ],
      {
        'color': 0x00ff0000,
        'secondaryColor': 0xff0000ff,
        'gradient': true,
        'gradientDirection': 'vertical',
      },
    );
    expect(e.document.resolved(0, 0)!.pixels, [0, 0x80800080, 0xff0000ff]);
  });
  test('gradient honors native grayscale and indexed conversion', () {
    for (final depth in [8, 16]) {
      final e = canvas(3, 1);
      e.document.depth = depth;
      if (depth == 8) {
        e.document.frames[0].palette = [0, 0xff000000, 0xffffffff];
      }
      draw(
        e,
        'fill',
        [
          [0, 0],
        ],
        {
          'color': 0xff000000,
          'secondaryColor': 0xffffffff,
          'gradient': true,
          'gradientDirection': 'horizontal',
        },
      );
      final p = e.document.resolved(0, 0)!.pixels;
      expect(p, depth == 8 ? [1, 2, 2] : [0xff000000, 0xff808080, 0xffffffff]);
    }
  });
  test(
    'explicit paletteIndex selects duplicate color entry and eraser ignores it',
    () {
      final e = canvas(2, 1);
      e.document.depth = 8;
      e.document.frames[0].palette = [0, 0xffff0000, 0xffff0000];
      draw(
        e,
        'pencil',
        [
          [0, 0],
        ],
        {'paletteIndex': 2},
      );
      expect(e.document.resolved(0, 0)!.pixels[0], 2);
      draw(
        e,
        'eraser',
        [
          [0, 0],
        ],
        {'paletteIndex': 2},
      );
      expect(e.document.resolved(0, 0)!.pixels[0], 0);
    },
  );
  test('spray is deterministic, distributed, clipped, and one undo', () {
    final a = canvas(16, 16), b = canvas(16, 16);
    for (final e in [a, b]) {
      draw(
        e,
        'spray',
        [
          [8, 8],
        ],
        {'size': 8, 'density': 100, 'seed': 123},
      );
    }
    expect(a.document.composite(0), b.document.composite(0));
    expect(
      a.document.composite(0).where((p) => p != 0).length,
      greaterThan(10),
    );
    expect(a.document.composite(0)[0], 0);
    a.invoke('undo');
    expect(a.document.composite(0).every((p) => p == 0), true);
  });
  test('spray segmentation does not add randomness at repeated junctions', () {
    final a = canvas(16, 16), b = canvas(16, 16);
    draw(
      a,
      'spray',
      [
        [2, 8],
        [10, 8],
      ],
      {'size': 5, 'seed': 5, 'density': 8},
    );
    draw(
      b,
      'spray',
      [
        [2, 8],
        [6, 8],
        [10, 8],
      ],
      {'size': 5, 'seed': 5, 'density': 8},
    );
    expect(a.document.composite(0), b.document.composite(0));
  });
  test('blur averages immutable neighbors with premultiplied alpha', () {
    final e = canvas(3, 1);
    e.document.editable(0, 0).pixels[1] = 0xffff0000;
    draw(
      e,
      'blur',
      [
        [1, 0],
      ],
      {'size': 3, 'strength': 100},
    );
    expect(e.document.resolved(0, 0)!.pixels, [
      0x80ff0000,
      0x55ff0000,
      0x80ff0000,
    ]);
  });
  test(
    'jumble is seeded permutation preserving every raw value including alpha',
    () {
      final a = canvas(4, 4), b = canvas(4, 4);
      final original = List.generate(16, (i) => (i * 17) << 24 | i);
      for (final e in [a, b]) {
        e.document.editable(0, 0).pixels.setAll(0, original);
        draw(
          e,
          'jumble',
          [
            [2, 2],
          ],
          {'size': 4, 'strength': 100, 'seed': 8},
        );
      }
      expect(
        a.document.resolved(0, 0)!.pixels,
        b.document.resolved(0, 0)!.pixels,
      );
      expect(
        a.document.resolved(0, 0)!.pixels.toList()..sort(),
        original.toList()..sort(),
      );
      expect(a.document.resolved(0, 0)!.pixels, isNot(original));
      a.invoke('undo');
      expect(a.document.resolved(0, 0)!.pixels, original);
    },
  );
  test('indexed jumble preserves palette indices exactly', () {
    final e = canvas(4, 1);
    e.document.depth = 8;
    e.document.frames[0].palette = [0, 0xffff0000, 0xffff0000, 0xffffffff];
    e.document.editable(0, 0).pixels.setAll(0, [0, 1, 2, 3]);
    draw(
      e,
      'jumble',
      [
        [2, 0],
      ],
      {'size': 4, 'strength': 100, 'seed': 42},
    );
    expect(e.document.resolved(0, 0)!.pixels.toList()..sort(), [0, 1, 2, 3]);
  });
  test(
    'both symmetry axes reflect spray and solid shapes about canvas center',
    () {
      for (final tool in ['pencil', 'spray', 'rectangle', 'ellipse']) {
        final e = canvas(9, 9);
        draw(
          e,
          tool,
          [
            [1, 1],
            [2, 2],
          ],
          {
            'mirrorX': true,
            'mirrorY': true,
            'filled': true,
            'size': 3,
            'seed': 7,
          },
        );
        final p = e.document.composite(0);
        for (var y = 0; y < 9; y++) {
          for (var x = 0; x < 9; x++) {
            expect(p[y * 9 + x], p[y * 9 + 8 - x]);
            expect(p[y * 9 + x], p[(8 - y) * 9 + x]);
          }
        }
      }
    },
  );
  test('center overlap does not repeatedly blur', () {
    final a = canvas(3, 3), b = canvas(3, 3);
    for (final e in [a, b]) {
      e.document.editable(0, 0).pixels[4] = 0xffff0000;
    }
    draw(
      a,
      'blur',
      [
        [1, 1],
      ],
      {'strength': 50},
    );
    draw(
      b,
      'blur',
      [
        [1, 1],
      ],
      {'strength': 50, 'mirrorX': true, 'mirrorY': true},
    );
    expect(
      a.document.resolved(0, 0)!.pixels,
      b.document.resolved(0, 0)!.pixels,
    );
  });
  test(
    'mirrored gradients fill separate exact regions in mirrored direction',
    () {
      final e = canvas(7, 1), c = e.document.editable(0, 0);
      c.pixels[2] = 0xff00ff00;
      c.pixels[4] = 0xff00ff00;
      draw(
        e,
        'fill',
        [
          [0, 0],
        ],
        {
          'mirrorX': true,
          'gradient': true,
          'gradientDirection': 'horizontal',
          'color': 0xffff0000,
          'secondaryColor': 0xff0000ff,
        },
      );
      expect(e.document.resolved(0, 0)!.pixels, [
        0xffff0000,
        0xff0000ff,
        0xff00ff00,
        0,
        0xff00ff00,
        0xff0000ff,
        0xffff0000,
      ]);
    },
  );
  test('invalid gradient and indexed swatch fail atomically', () {
    final e = canvas();
    final before = e.encode();
    expect(
      () => draw(
        e,
        'fill',
        [
          [0, 0],
        ],
        {'gradient': true, 'gradientDirection': 'diagonal'},
      ),
      throwsFormatException,
    );
    expect(e.encode(), before);
    e.document.depth = 8;
    expect(
      () => draw(
        e,
        'pencil',
        [
          [0, 0],
        ],
        {'paletteIndex': 999},
      ),
      throwsFormatException,
    );
    expect(e.state()['canUndo'], false);
  });
}
