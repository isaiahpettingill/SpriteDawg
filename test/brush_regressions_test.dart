import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/engine/editor_engine.dart';
import 'package:spritedawg/engine/document.dart';

EditorEngine makeCanvas([int depth = 32]) {
  final e = EditorEngine();
  e.invoke('new', {'width': 16, 'height': 16});
  e.document.depth = depth;
  return e;
}

void stroke(EditorEngine e, String tool, Map<String, dynamic> extra) =>
    e.stroke({
      'tool': tool,
      'points': [
        [8, 8],
      ],
      'size': 1,
      'color': 0x80ff0000,
      ...extra,
    });

void main() {
  test(
    'preview uses active selection and leaves dirty/history/document untouched',
    () {
      final e = makeCanvas();
      final before = e.encode(), stateBefore = e.state();
      final args = <String, dynamic>{
        'tool': 'airbrush',
        'points': [
          [8, 8],
          [8, 8],
        ],
        'size': 9,
        'strength': 20,
        'color': 0xffff0000,
      };
      final preview = e.invoke('previewStroke', args);
      expect(e.encode(), before);
      expect(e.state()['dirty'], stateBefore['dirty']);
      expect(e.state()['canUndo'], stateBefore['canUndo']);
      expect(e.state()['canRedo'], stateBefore['canRedo']);
      e.stroke(args);
      expect(preview['pixels'], e.state()['pixels']);
    },
  );
  for (final tool in ['pencil', 'line', 'rectangle', 'ellipse', 'fill']) {
    test('$tool alpha composites over existing RGBA once per gesture', () {
      final e = makeCanvas();
      e.document.editable(0, 0).pixels.fillRange(0, 256, 0xff0000ff);
      stroke(e, tool, {
        'points': [
          [8, 8],
          [8, 8],
        ],
        'mirrorX': true,
        'mirrorY': true,
      });
      expect(
        e.document.resolved(0, 0)!.pixels[136],
        over(0xff0000ff, 0x80ff0000),
      );
      e.invoke('undo');
      expect(e.document.resolved(0, 0)!.pixels[136], 0xff0000ff);
    });
  }
  test(
    'overlapping translucent pencil stamps do not build up within a stroke',
    () {
      final e = makeCanvas();
      stroke(e, 'pencil', {
        'points': [
          [7, 8],
          [8, 8],
          [7, 8],
        ],
        'size': 3,
      });
      expect(e.document.resolved(0, 0)!.pixels[136], 0x80ff0000);
      stroke(e, 'pencil', {});
      expect(e.document.resolved(0, 0)!.pixels[136] >> 24, 192);
    },
  );
  test(
    'zero-alpha paint leaves the pixel alone; eraser actually clears it',
    () {
      final e = makeCanvas();
      e.document.editable(0, 0).pixels[136] = 0xff0000ff;
      stroke(e, 'pencil', {'color': 0x00ff0000});
      expect(e.document.resolved(0, 0)!.pixels[136], 0xff0000ff);
      stroke(e, 'eraser', {});
      expect(e.document.resolved(0, 0)!.pixels[136], 0);
    },
  );
  test('stationary spray accumulates dispersed seeded dots', () {
    final a = makeCanvas(), b = makeCanvas();
    stroke(a, 'spray', {'size': 12, 'density': 4, 'seed': 17});
    stroke(b, 'spray', {
      'size': 12,
      'density': 4,
      'seed': 17,
      'points': List.generate(10, (_) => [8, 8]),
    });
    final once = a.document.resolved(0, 0)!.pixels;
    final held = b.document.resolved(0, 0)!.pixels;
    expect(once.where((p) => p != 0).length, greaterThan(1));
    expect(
      held.where((p) => p != 0).length,
      greaterThan(once.where((p) => p != 0).length),
    );
    expect(held.where((p) => p != 0).length, lessThan(12 * 12));
    b.invoke('undo');
    expect(b.document.composite(0).every((p) => p == 0), isTrue);
  });
  test('airbrush is soft and builds opacity while stationary', () {
    final a = makeCanvas(), b = makeCanvas();
    stroke(a, 'airbrush', {'size': 9, 'strength': 20, 'color': 0xffff0000});
    stroke(b, 'airbrush', {
      'size': 9,
      'strength': 20,
      'color': 0xffff0000,
      'points': List.generate(4, (_) => [8, 8]),
    });
    final p = a.document.resolved(0, 0)!.pixels;
    expect(p[136] >> 24, 51);
    expect(p[132] >> 24, greaterThan(0));
    expect(p[132] >> 24, lessThan(p[136] >> 24));
    expect(p[4 * 16 + 4], 0);
    expect(b.document.resolved(0, 0)!.pixels[136] >> 24, greaterThan(51));
  });
  test('one-pixel jumble swaps a neighbour, preserving indexed values', () {
    final e = makeCanvas(8);
    e.document.frames[0].palette = Uint32List.fromList([
      0,
      0xffff0000,
      0xff0000ff,
    ]);
    final c = e.document.editable(0, 0);
    c.pixels.fillRange(0, 256, 1);
    c.pixels[136] = 2;
    final original = c.pixels.toList()..sort();
    stroke(e, 'jumble', {'strength': 100, 'seed': 17});
    final actual = e.document.resolved(0, 0)!.pixels;
    expect(actual[136], 1);
    expect(actual.toList()..sort(), original);
  });
  test(
    'blur actually softens isolated opaque detail without black fringes',
    () {
      final e = makeCanvas();
      e.document.editable(0, 0).pixels[136] = 0xffffffff;
      stroke(e, 'blur', {'size': 3, 'strength': 100});
      final p = e.document.resolved(0, 0)!.pixels;
      expect(p[136], 0x1cffffff);
      expect(p[135], 0x1cffffff);
    },
  );
}
