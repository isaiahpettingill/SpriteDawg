import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/engine/editor_engine.dart';
import 'package:spritedawg/engine/document.dart';

EditorEngine canvas([int depth = 32]) {
  final d = SpriteDocument.create(5, 3)..depth = depth;
  return EditorEngine()..replace(d);
}

Map<String, dynamic> gradient([Map<String, dynamic> extra = const {}]) => {
  'tool': 'gradient',
  'points': [
    [1, 1],
    [3, 1],
  ],
  'color': 0xffff0000,
  'secondaryColor': 0xff0000ff,
  ...extra,
};
void main() {
  test('drag gradient clamps endpoints across active canvas and one undo', () {
    final e = canvas();
    e.stroke(gradient());
    expect(
      e.document.composite(0),
      List.generate(
        3,
        (_) => [0xffff0000, 0xffff0000, 0xff800080, 0xff0000ff, 0xff0000ff],
      ).expand((r) => r),
    );
    final after = e.encode();
    e.invoke('undo');
    expect(e.document.composite(0).every((p) => p == 0), true);
    e.invoke('redo');
    expect(e.encode(), after);
  });
  test('diagonal reverse drag swaps endpoints without changing field', () {
    final a = canvas(), b = canvas();
    a.stroke(
      gradient({
        'points': [
          [0, 0],
          [4, 2],
        ],
      }),
    );
    b.stroke(
      gradient({
        'points': [
          [4, 2],
          [0, 0],
        ],
        'color': 0xff0000ff,
        'secondaryColor': 0xffff0000,
      }),
    );
    expect(a.document.composite(0), b.document.composite(0));
  });
  test('alpha blends once, symmetry and brush size do not distort field', () {
    final a = canvas(), b = canvas();
    a.document.editable(0, 0).pixels.fillRange(0, 15, 0xff00ff00);
    b.document.editable(0, 0).pixels.fillRange(0, 15, 0xff00ff00);
    final args = gradient({'color': 0x00ff0000, 'secondaryColor': 0x800000ff});
    a.stroke(args);
    b.stroke({...args, 'mirrorX': true, 'mirrorY': true, 'size': 32});
    expect(a.document.composite(0), b.document.composite(0));
    expect(a.document.composite(0)[0], 0xff00ff00);
    expect(a.document.composite(0)[4], over(0xff00ff00, 0x800000ff));
  });
  test('tap is no-op without dirty/history changes', () {
    final e = canvas(), before = canvas().encode();
    e.stroke(
      gradient({
        'points': [
          [2, 1],
          [2, 1],
        ],
      }),
    );
    expect(e.encode(), before);
    expect(e.dirty, false);
    expect(e.state()['canUndo'], false);
  });
  test('preview uses same gradient without changing document or history', () {
    final e = canvas(), before = canvas().encode();
    final p = e.previewStroke(gradient());
    expect(e.encode(), before);
    expect(e.state()['canUndo'], false);
    e.stroke(gradient());
    expect(p['pixels'], e.state()['pixels']);
  });
  test(
    'indexed gradient quantizes blended result, keeps palette and transparent ink indices',
    () {
      final e = canvas(8);
      e.document.frames[0].palette = Uint32List.fromList([
        0,
        0xff00ff00,
        0xff800080,
        0xff007f80,
        0xff00ff00,
      ]);
      e.document.editable(0, 0).pixels.fillRange(0, 15, 4);
      e.stroke(
        gradient({
          'color': 0x000000ff,
          'secondaryColor': 0x800000ff,
          'paletteIndex': 2,
        }),
      );
      final p = e.document.resolved(0, 0)!.pixels;
      expect(p[0], 4); // Exact duplicate index remains under transparent ink.
      expect(p[4], 3); // Blended green/blue, not the supplied palette index.
      expect(e.document.frames[0].palette.length, 5);
      e.invoke('undo');
      expect(e.document.resolved(0, 0)!.pixels.every((p) => p == 4), true);
    },
  );
  test('grayscale projects blended color to grayscale', () {
    final e = canvas(16);
    e.stroke(gradient());
    for (final p in e.document.composite(0)) {
      expect(p >> 16 & 255, p >> 8 & 255);
      expect(p >> 8 & 255, p & 255);
    }
  });
  test('large off-canvas endpoints do not overflow', () {
    final e = canvas();
    e.stroke(
      gradient({
        'points': [
          [-8192, -8192],
          [8192, 8192],
        ],
      }),
    );
    expect(e.document.composite(0)[0], 0xff800080);
  });
}
