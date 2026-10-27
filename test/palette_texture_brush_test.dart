import 'dart:typed_data';

import 'package:spritedawg/engine/document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/engine/editor_engine.dart';
import 'package:spritedawg/engine/palette_texture_brush.dart';

const shades = [0xff151515, 0xff444444, 0xff888888, 0xffbbbbbb, 0xffeeeeee];
EditorEngine setup({bool indexed = false}) {
  final e = EditorEngine();
  e.invoke('new', {'width': 32, 'height': 32});
  if (indexed) {
    e.document.depth = 8;
    e.document.transparentIndex = 0;
  }
  e.document.frames[0].palette = [if (indexed) 0, ...shades];
  return e;
}

void stroke(
  EditorEngine e,
  String tool, {
  List<List<int>>? points,
  int color = 0xff888888,
  bool mirror = false,
}) => e.stroke({
  'tool': tool,
  'color': color,
  'size': 12,
  'seed': 421,
  'strength': 50,
  'mirrorX': mirror,
  'mirrorY': mirror,
  'points':
      points ??
      [
        [8, 8],
        [24, 24],
      ],
});
void main() {
  test('no-op retouch preserves redo, clean state and linked cels', () {
    for (final original in [0xff888888, 0x80777777, 0]) {
      final e = setup();
      e.document.editable(0, 0).pixels.fillRange(0, 1024, original);
      e.document.frames.add(
        Frame(
          palette: List.of(shades),
          cels: [Cel(0, 0, 0, 0, Uint32List(0), link: 0)],
        ),
      );
      e.frame = 1;
      stroke(e, 'pencil');
      e.invoke('undo');
      e.saved();
      final before = e.encode();
      stroke(e, 'ditherRetouch');
      expect(e.encode(), before);
      expect(e.document.frames[1].cels[0]!.link, 0);
      expect(e.dirty, false);
      expect(e.state()['canRedo'], true);
    }
  });
  test('indexed transparent texture anchor never substitutes opaque ink', () {
    final e = setup(indexed: true);
    e.document.frames[0].palette[0] = 0xff888888;
    final before = e.encode();
    e.saved();
    e.stroke({
      'tool': 'metal',
      'color': 0xff888888,
      'paletteIndex': 0,
      'size': 12,
      'points': [
        [8, 8],
        [24, 24],
      ],
    });
    expect(e.encode(), before);
    expect(e.dirty, false);
    expect(e.state()['canUndo'], false);
  });
  test('Oklab reference black white and red conversion', () {
    expect(PaletteLab(0xff000000).l, closeTo(0, 1e-8));
    expect(PaletteLab(0xffffffff).l, closeTo(1, 1e-7));
    final red = PaletteLab(0xffff0000);
    expect(red.l, closeTo(.627955, 1e-5));
    expect(red.a, closeTo(.224863, 1e-5));
  });
  test(
    'shade ramp keeps actual indices, alpha family and duplicate anchor',
    () {
      final p = [...shades, 0xff00ff00, 0x80888888, 0xff888888];
      final ramp = paletteShadeRamp(p, 0xff888888, selectedIndex: 7);
      expect(ramp[2], 7);
      expect(ramp.contains(5), false);
      expect(ramp.contains(6), false);
      expect(paletteShadeRamp([0, 0x00123456], 0xff111111), isEmpty);
      expect(paletteShadeRamp([0xff123456], 0xff123456), [0, 0, 0, 0, 0]);
    },
  );
  for (final tool in paletteTextureTools) {
    test(
      '$tool one undo, palette-only opaque paint, repeat-event invariance',
      () {
        final a = setup(), b = setup();
        if (tool == 'ditherRetouch') {
          a.document.editable(0, 0).pixels.fillRange(0, 1024, 0xff777777);
          b.document.editable(0, 0).pixels.fillRange(0, 1024, 0xff777777);
        }
        final before = a.encode();
        stroke(
          a,
          tool,
          points: [
            [8, 8],
            [24, 24],
          ],
        );
        stroke(
          b,
          tool,
          points: [
            [8, 8],
            [8, 8],
            [12, 12],
            [16, 16],
            [20, 20],
            [24, 24],
          ],
        );
        expect(a.document.composite(0), b.document.composite(0));
        final pixels = a.document.editable(0, 0).pixels;
        expect(
          pixels.every((p) => p == 0 || p == 0xff777777 || shades.contains(p)),
          true,
        );
        final after = a.encode();
        a.invoke('undo');
        expect(a.encode(), before);
        a.invoke('redo');
        expect(a.encode(), after);
      },
    );
  }
  test(
    'sphere top lighter than bottom and knife flips with stroke direction',
    () {
      Map<int, int> raster(String t, List<(int, int)> points) =>
          paletteTexturePixels(
            tool: t,
            points: points,
            width: 32,
            height: 32,
            size: 11,
            ramp: [0, 1, 2, 3, 4],
          );
      final sphere = raster('sphere', [(16, 16)]);
      expect(sphere[13 * 32 + 16]!, greaterThan(sphere[19 * 32 + 16]!));
      final right = raster('knife', [(8, 16), (24, 16)]),
          left = raster('knife', [(24, 16), (8, 16)]);
      expect(right[13 * 32 + 16]!, greaterThan(right[19 * 32 + 16]!));
      expect(left[13 * 32 + 16]!, lessThan(left[19 * 32 + 16]!));
    },
  );
  test('clusters stable across seed and stripes elongate along tangent', () {
    final a = paletteTexturePixels(
      tool: 'cluster',
      points: [(16, 16)],
      width: 32,
      height: 32,
      size: 32,
      ramp: [0, 1, 2, 3, 4],
      seed: 12,
    );
    final b = paletteTexturePixels(
      tool: 'cluster',
      points: [(16, 16)],
      width: 32,
      height: 32,
      size: 32,
      ramp: [0, 1, 2, 3, 4],
      seed: 13,
    );
    expect(a, isNot(b));
    expect(a.values.toSet().length, greaterThan(1));
    final s = paletteTexturePixels(
      tool: 'stripes',
      points: [(8, 16), (24, 16)],
      width: 32,
      height: 32,
      size: 20,
      ramp: [0, 1, 2, 3, 4],
      seed: 12,
    );
    var horizontal = 0, vertical = 0;
    for (var y = 10; y < 22; y++) {
      for (var x = 8; x < 24; x++) {
        if (s[y * 32 + x] != s[y * 32 + x + 1]) horizontal++;
        if (s[y * 32 + x] != s[(y + 1) * 32 + x]) vertical++;
      }
    }
    expect(horizontal, lessThan(vertical));
  });
  test(
    'indexed branches preserve palette and shade membership with symmetry',
    () {
      final e = setup(indexed: true);
      final palette = List<int>.of(e.document.frames[0].palette);
      stroke(e, 'metal', mirror: true);
      expect(e.document.frames[0].palette, palette);
      final p = e.document.editable(0, 0).pixels;
      expect(p.every((i) => i >= 0 && i < palette.length), true);
      for (var y = 0; y < 32; y++) {
        for (var x = 0; x < 32; x++) {
          expect(p[y * 32 + x], p[y * 32 + 31 - x]);
          expect(p[y * 32 + x], p[(31 - y) * 32 + x]);
        }
      }
    },
  );
  test('semi-alpha texture blends once, retouch never flattens alpha', () {
    final e = setup();
    e.document.frames[0].palette = [0x80123456];
    stroke(e, 'cluster');
    expect(
      e.document
          .editable(0, 0)
          .pixels
          .where((p) => p != 0)
          .every((p) => p == 0x80123456),
      true,
    );
    expect(retouchPaletteIndex(shades, 0x80777777, 0, 0), -1);
    expect(retouchPaletteIndex(shades, 0, 0, 0), -1);
  });
  test(
    'retouch selected color independent and keeps duplicate native indices',
    () {
      final a = setup(), b = setup();
      a.document.editable(0, 0).pixels.fillRange(0, 1024, 0xff777777);
      b.document.editable(0, 0).pixels.fillRange(0, 1024, 0xff777777);
      stroke(a, 'ditherRetouch', color: 0xffff0000);
      stroke(b, 'ditherRetouch', color: 0xff00ff00);
      expect(a.encode(), b.encode());
      final e = setup(indexed: true);
      e.document.frames[0].palette.add(shades[2]);
      e.document.editable(0, 0).pixels.fillRange(0, 1024, 6);
      stroke(e, 'ditherRetouch');
      expect(e.document.editable(0, 0).pixels.every((p) => p == 6), true);
    },
  );
  test('dither paint uses intermediate palette color and canvas phase', () {
    final p = [0xff000000, 0xff636363, 0xffffffff];
    final a = ditherPaletteIndex(p, 0xff000000, 0xffffffff, 1, 2, 50);
    expect(a, 1);
    expect(ditherPaletteIndex(p, 0xff000000, 0xffffffff, 5, 6, 50), a);
    final two = [0xff000000, 0xffffffff];
    final used = <int>{};
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        used.add(ditherPaletteIndex(two, 0xff000000, 0xffffffff, x, y, 50));
      }
    }
    expect(used, {0, 1});
  });
  test(
    'gradient still interpolates arbitrary RGB and quantizes indexed only',
    () {
      final a = setup();
      a.stroke({
        'tool': 'gradient',
        'points': [
          [0, 0],
          [31, 0],
        ],
        'color': 0xff000000,
        'secondaryColor': 0xffffffff,
      });
      expect(shades.contains(a.document.composite(0)[10]), false);
      final b = setup(indexed: true);
      b.stroke({
        'tool': 'gradient',
        'points': [
          [0, 0],
          [31, 0],
        ],
        'color': 0xff000000,
        'secondaryColor': 0xffffffff,
      });
      expect(
        b.document
            .editable(0, 0)
            .pixels
            .every((p) => p < b.document.frames[0].palette.length),
        true,
      );
    },
  );
}
