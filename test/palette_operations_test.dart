import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/engine/aseprite.dart';
import 'package:spritedawg/engine/document.dart';
import 'package:spritedawg/engine/editor_engine.dart';

EditorEngine indexed() {
  final e = EditorEngine();
  e.replace(
    SpriteDocument(
      2,
      1,
      [Layer('Ink'), Layer('Background', flags: 11)],
      [
        Frame(
          palette: [0xff102030, 0xffff0000, 0xff00ff00],
          paletteNames: {0: 'transparent', 1: 'primary', 2: 'leaf'},
          cels: [
            Cel(
              0,
              0,
              2,
              1,
              Uint32List.fromList([1, 0]),
              data: UserData(text: 'cel-meta'),
            ),
            Cel(0, 0, 2, 1, Uint32List.fromList([0, 2])),
          ],
        ),
        Frame(
          duration: 125,
          palette: [0xffabcdef, 0xff0000ff, 0xffffff00],
          paletteNames: {0: 'hole', 1: 'water', 2: 'sun'},
          cels: [
            Cel(
              0,
              0,
              0,
              0,
              Uint32List(0),
              link: 0,
              data: UserData(text: 'linked-meta'),
            ),
            null,
          ],
        ),
      ],
      depth: 8,
      transparentIndex: 0,
      data: UserData(text: 'sprite-meta'),
    ),
  );
  return e;
}

void main() {
  test('named RGBA presets retain exact ARGB and names in every frame', () {
    final e = indexed();
    e.invoke('edit', {'action': 'convertMode', 'depth': 32});
    e.replace(e.document.copy());
    final before = e.encode();
    final pixels = [for (var f = 0; f < 2; f++) e.document.composite(f)];
    final colors = [0xffc08040, 0x80c08040, 0x20c08040, 0x00112233];
    final names = ['Terre brûlée', 'Glaze 50%', 'Glaze 12.5%', ''];
    final expectedNames = {0: names[0], 1: names[1], 2: names[2]};
    e.invoke('edit', {
      'action': 'palettePreset',
      'colors': colors,
      'names': names,
    });
    final reopened = AsepriteCodec.decode(e.encode());
    for (var f = 0; f < 2; f++) {
      expect(e.document.frames[f].palette, colors);
      expect(e.document.frames[f].paletteNames, expectedNames);
      expect(reopened.frames[f].palette, colors);
      expect(reopened.frames[f].paletteNames, expectedNames);
      expect(reopened.composite(f), pixels[f]);
    }
    e.invoke('undo');
    expect(e.encode(), before);
    expect(e.state()['canUndo'], false);
    e.invoke('redo');
    expect(e.document.frames[1].paletteNames, expectedNames);
    names[0] = 'Changed input';
    e.document.frames[0].paletteNames[0] = 'Changed frame';
    expect(e.document.frames[1].paletteNames[0], 'Terre brûlée');
  });
  test(
    'named indexed presets retain semitransparent frame colors and undo',
    () {
      final e = EditorEngine();
      e.replace(
        SpriteDocument(
          5,
          1,
          [Layer('Ink'), Layer('Background', flags: 11)],
          [
            Frame(
              palette: [0xff3c2a18, 0x80aabbcc, 0xffaabbcc, 0x20aabbcc, 0],
              paletteNames: {1: 'old glaze'},
              cels: [
                Cel(0, 0, 5, 1, Uint32List.fromList([1, 2, 3, 0, 4])),
                Cel(0, 0, 5, 1, Uint32List.fromList([1, 2, 3, 0, 4])),
              ],
            ),
            Frame(
              palette: [0xff3c2a18, 0x20aabbcc, 0x80aabbcc, 0xffaabbcc, 0],
              paletteNames: {1: 'old light glaze'},
              cels: [
                Cel(
                  0,
                  0,
                  0,
                  0,
                  Uint32List(0),
                  link: 0,
                  data: UserData(text: 'linked-glaze'),
                ),
                null,
              ],
            ),
          ],
          depth: 8,
        ),
      );
      final before = e.encode();
      final pixels = [for (var f = 0; f < 2; f++) e.document.composite(f)];
      final colors = [
        0xffaabbcc,
        0x80aabbcc,
        0x20aabbcc,
        0xff3c2a18,
        0x00112233,
      ];
      final names = [
        'Solid',
        'Glaze 50%',
        'Glaze 12.5%',
        'Ground',
        'Hidden RGB',
      ];
      final expectedNames = {
        for (var i = 0; i < names.length; i++) i: names[i],
      };
      e.invoke('edit', {
        'action': 'palettePreset',
        'colors': colors,
        'names': names,
        'remap': true,
      });
      expect(e.document.depth, 8);
      expect(e.document.transparentIndex, 5);
      expect(e.document.frames[0].cels[0]!.pixels, [1, 0, 2, 5, 5]);
      expect(e.document.frames[0].cels[1]!.pixels, [1, 0, 2, 3, 5]);
      expect(e.document.frames[1].cels[0]!.pixels, [2, 1, 0, 5, 5]);
      expect(e.document.frames[1].cels[0]!.link, isNull);
      final reopened = AsepriteCodec.decode(e.encode());
      expect(reopened.frames[1].cels[0]!.data!.text, 'linked-glaze');
      for (var f = 0; f < 2; f++) {
        expect(e.document.frames[f].paletteNames, expectedNames);
        expect(reopened.frames[f].palette, [...colors, 0]);
        expect(reopened.frames[f].paletteNames, expectedNames);
        expect(reopened.composite(f), pixels[f]);
      }
      e.invoke('undo');
      expect(e.encode(), before);
      expect(e.state()['canUndo'], false);
      e.invoke('redo');
      expect(e.document.frames[1].paletteNames, expectedNames);
      expect(e.document.frames[1].cels[0]!.pixels, [2, 1, 0, 5, 5]);
    },
  );
  test('invalid preset names preserve artwork and undo redo history', () {
    for (final e in [EditorEngine(), indexed()]) {
      final before = e.encode();
      final args = {
        'action': 'palettePreset',
        'colors': [0x80abcdef, 0xffabcdef],
        'names': ['Glaze', 'Solid'],
        'remap': true,
      };
      e.invoke('edit', args);
      e.invoke('undo');
      e.saved();
      for (final names in <dynamic>[
        null,
        'not a list',
        [],
        ['Only one'],
        ['One', 'Two', 'Extra'],
        [1, 'Two'],
        ['One', null],
        ['a' * 65536, 'Two'],
        ['é' * 32768, 'Two'],
      ]) {
        expect(
          () => e.invoke('edit', {...args, 'names': names}),
          throwsFormatException,
        );
        expect(e.encode(), before);
        expect(e.state()['canUndo'], false);
        expect(e.state()['canRedo'], true);
        expect(e.dirty, false);
      }
      e.invoke('redo');
      expect(e.document.frames[0].paletteNames, {0: 'Glaze', 1: 'Solid'});
    }
  });
  test('preset names accept the UTF-8 byte limit and empty unnamed slots', () {
    final name = '€' * 21845; // Exactly 65535 UTF-8 bytes.
    for (final e in [EditorEngine(), indexed()]) {
      final before = e.encode();
      e.invoke('edit', {
        'action': 'palettePreset',
        'colors': [0x80446688, 0xff446688],
        'names': [name, ''],
        'remap': true,
      });
      final reopened = AsepriteCodec.decode(e.encode());
      for (final frame in reopened.frames) {
        expect(frame.paletteNames, {0: name});
      }
      e.invoke('undo');
      expect(e.encode(), before);
    }
  });
  test(
    'RGBA preset replaces all swatches without changing artwork or links',
    () {
      final e = indexed();
      e.invoke('edit', {'action': 'convertMode', 'depth': 32});
      // Start with real persisted palette chunks and a linked RGBA cel.
      e.document.frames[1].cels[0] = Cel(
        0,
        0,
        0,
        0,
        Uint32List(0),
        link: 0,
        data: UserData(text: 'linked-rgba'),
      );
      e.document.frames[0].metadata.add(RawChunk(0x2007, Uint8List(16)));
      e.replace(AsepriteCodec.decode(e.encode()));
      final before = e.encode();
      final pixels = [for (var f = 0; f < 2; f++) e.document.composite(f)];
      final colors = [0xff123456, 0x80765432];
      expect(e.document.frames[0].metadata.any((c) => c.type == 0x2019), true);
      e.invoke('edit', {'action': 'palettePreset', 'colors': colors});
      expect(e.document.depth, 32);
      expect(e.document.frames[1].cels[0]!.link, 0);
      for (var f = 0; f < 2; f++) {
        expect(e.document.frames[f].palette, colors);
        expect(e.document.frames[f].paletteNames, isEmpty);
        expect(e.document.frames[f].palettePatches, isEmpty);
        expect(
          e.document.frames[f].metadata.where(
            (c) => [4, 17, 0x2019].contains(c.type),
          ),
          isEmpty,
        );
        expect(e.document.composite(f), pixels[f]);
      }
      expect(e.document.frames[0].metadata.single.type, 0x2007);
      final reopened = AsepriteCodec.decode(e.encode());
      expect(reopened.frames[1].cels[0]!.data!.text, 'linked-rgba');
      expect(reopened.data!.text, 'sprite-meta');
      for (var f = 0; f < 2; f++) {
        expect(reopened.frames[f].palette, colors);
        expect(reopened.frames[f].paletteNames, isEmpty);
        expect(reopened.composite(f), pixels[f]);
      }
      e.invoke('undo');
      expect(e.encode(), before);
      expect(e.state()['canUndo'], false);
      e.invoke('redo');
      expect(e.document.frames[0].palette, colors);
      // Each frame and the input own their palette list.
      colors[0] = 0;
      e.document.frames[0].palette[0] = 0;
      expect(e.document.frames[1].palette[0], 0xff123456);
    },
  );
  test('indexed preset remaps per-frame links and background transparency', () {
    final e = indexed();
    e.document.frames[1].palette.add(0xff999999);
    e.document.frames[1].cels[0]!.opacity = 128;
    final before = e.encode();
    final pixels = [for (var f = 0; f < 2; f++) e.document.composite(f)];
    final colors = [0xff0000ff, 0xffff0000, 0xff102030, 0xff00ff00];
    e.invoke('edit', {
      'action': 'palettePreset',
      'colors': colors,
      'remap': true,
    });
    expect(e.document.depth, 8);
    expect(e.document.transparentIndex, 4);
    expect(e.document.frames[0].cels[0]!.pixels, [1, 4]);
    expect(e.document.frames[0].cels[1]!.pixels, [2, 3]);
    expect(e.document.frames[1].cels[0]!.pixels, [0, 4]);
    expect(e.document.frames[1].cels[0]!.link, isNull);
    expect(e.document.frames[1].cels[0]!.opacity, 128);
    expect(e.document.frames[1].cels[0]!.data!.text, 'linked-meta');
    expect(e.document.layers[1].flags, 11);
    final reopened = AsepriteCodec.decode(e.encode());
    for (var f = 0; f < 2; f++) {
      expect(e.document.frames[f].palette, [...colors, 0]);
      expect(e.document.frames[f].paletteNames, isEmpty);
      expect(reopened.frames[f].palette, [...colors, 0]);
      expect(reopened.composite(f), pixels[f]);
    }
    e.invoke('undo');
    expect(e.encode(), before);
    expect(e.state()['canUndo'], false);
    e.invoke('redo');
    expect(e.document.frames[1].cels[0]!.pixels, [0, 4]);
  });
  test(
    'preset quantization includes alpha and deterministically resolves ties',
    () {
      final e = EditorEngine();
      e.replace(
        SpriteDocument(
          4,
          1,
          [Layer('Ink')],
          [
            Frame(
              palette: [0, 0xff101010, 0x80101010, 0xff808080],
              cels: [
                Cel(0, 0, 4, 1, Uint32List.fromList([0, 1, 2, 3])),
              ],
            ),
          ],
          depth: 8,
        ),
      );
      e.invoke('edit', {
        'action': 'palettePreset',
        'colors': [0xff101010, 0x80101010, 0xff7f8080, 0xff818080],
        'remap': true,
      });
      expect(e.document.frames[0].cels[0]!.pixels, [4, 0, 1, 2]);
    },
  );
  test(
    'preset input and indexed confirmation failures leave history untouched',
    () {
      final e = EditorEngine();
      final before = e.encode();
      for (final colors in <dynamic>[
        null,
        'not a list',
        [],
        List.filled(257, 0),
        [-1],
        [0x100000000],
        [1.0],
        ['ffffff'],
        [null],
      ]) {
        expect(
          () => e.invoke('edit', {'action': 'palettePreset', 'colors': colors}),
          throwsFormatException,
        );
        expect(e.encode(), before);
        expect(e.state()['canUndo'], false);
        expect(e.state()['dirty'], false);
      }
      final i = indexed(), indexedBefore = i.encode();
      for (final args in [
        {
          'colors': [0xff000000],
        },
        {
          'colors': [0xff000000],
          'remap': false,
        },
        {
          'colors': [0xff000000],
          'remap': 'true',
        },
        {'colors': List.filled(256, 0xff000000), 'remap': true},
      ]) {
        expect(
          () => i.invoke('edit', {'action': 'palettePreset', ...args}),
          throwsFormatException,
        );
        expect(i.encode(), indexedBefore);
        expect(i.state()['canUndo'], false);
      }
    },
  );
  test('preset accepts full RGBA and maximum indexed palettes', () {
    final e = EditorEngine();
    final colors = List.generate(256, (i) => 0xff000000 | i);
    e.invoke('edit', {'action': 'palettePreset', 'colors': colors});
    expect(AsepriteCodec.decode(e.encode()).frames[0].palette, colors);
    final i = indexed();
    i.invoke('edit', {
      'action': 'palettePreset',
      'colors': colors.sublist(0, 255),
      'remap': true,
    });
    expect(i.document.transparentIndex, 255);
    expect(AsepriteCodec.decode(i.encode()).frames[0].palette.length, 256);
  });
  test('preset remap refuses oversized linked expansion before committing', () {
    final e = EditorEngine();
    final d = SpriteDocument(
      2048,
      2048,
      [Layer('Ink')],
      [
        for (var f = 0; f < 5; f++)
          Frame(
            cels: [
              f == 0
                  ? Cel(0, 0, 2048, 2048, Uint32List(maxPixels))
                  : Cel(0, 0, 0, 0, Uint32List(0), link: 0),
            ],
          ),
      ],
      depth: 8,
    );
    e.replace(d);
    expect(
      () => e.invoke('edit', {
        'action': 'palettePreset',
        'colors': [0xff000000],
        'remap': true,
      }),
      throwsFormatException,
    );
    expect(identical(e.document, d), true);
    expect(e.document.frames[4].cels[0]!.link, 0);
    expect(e.state()['canUndo'], false);
  });
  test('preset validation rollback preserves document and redo history', () {
    final e = indexed();
    final args = {
      'action': 'palettePreset',
      'colors': [0xff000000, 0xffffffff],
      'remap': true,
    };
    e.invoke('edit', args);
    e.invoke('undo');
    final before = e.encode();
    e.validateCandidate = (_) => throw const FormatException('Test rejection');
    expect(() => e.invoke('edit', args), throwsFormatException);
    expect(e.encode(), before);
    expect(e.state()['canUndo'], false);
    expect(e.state()['canRedo'], true);
    e.validateCandidate = null;
    e.invoke('redo');
    expect(e.document.transparentIndex, 2);
  });
  test(
    'palette reorder preserves appearances links names transparency and undo',
    () {
      final e = indexed(), before = e.encode();
      final pixels = [for (var f = 0; f < 2; f++) e.document.composite(f)];
      e.invoke('edit', {'action': 'paletteMove', 'index': 0, 'to': 2});
      expect(e.document.transparentIndex, 2);
      expect(e.document.frames[1].cels[0]!.link, 0);
      expect(e.document.frames[1].paletteNames[0], 'water');
      for (var f = 0; f < 2; f++) {
        expect(e.document.composite(f), pixels[f]);
      }
      final reopened = AsepriteCodec.decode(e.encode());
      for (var f = 0; f < 2; f++) {
        expect(reopened.composite(f), pixels[f]);
      }
      expect(reopened.frames[1].cels[0]!.data!.text, 'linked-meta');
      e.invoke('undo');
      expect(e.encode(), before);
      e.invoke('redo');
      expect(e.document.transparentIndex, 2);
    },
  );
  test('frame palette edit retains other frame and metadata on roundtrip', () {
    final e = indexed();
    e.invoke('select', {'frame': 1});
    e.invoke('edit', {
      'action': 'paletteEdit',
      'index': 1,
      'color': 0xff223344,
      'name': 'new water',
    });
    expect(e.document.frames[0].palette[1], 0xffff0000);
    final d = AsepriteCodec.decode(e.encode());
    expect(d.frames[1].palette[1], 0xff223344);
    expect(d.frames[1].paletteNames[1], 'new water');
    expect(d.frames[0].paletteNames[1], 'primary');
    expect(d.data!.text, 'sprite-meta');
  });
  test('add adds common index retaining perframe palettes', () {
    final e = indexed();
    final before = e.encode();
    final pixels = [for (var f = 0; f < 2; f++) e.document.composite(f)];
    e.invoke('edit', {
      'action': 'paletteAdd',
      'color': 0x80445566,
      'name': 'glow',
    });
    expect(e.document.frames[0].palette[3], 0x80445566);
    expect(e.document.frames[1].palette[1], 0xff0000ff);
    expect(AsepriteCodec.decode(e.encode()).frames[1].paletteNames[3], 'glow');
    for (var f = 0; f < 2; f++) {
      expect(e.document.composite(f), pixels[f]);
      expect(AsepriteCodec.decode(e.encode()).composite(f), pixels[f]);
    }
    e.invoke('undo');
    expect(e.encode(), before);
    e.invoke('redo');
    expect(e.document.frames[0].palette[3], 0x80445566);
  });
  test(
    'remove requires explicit nontransparent replacement and remaps linked data',
    () {
      final e = indexed();
      e.invoke('edit', {
        'action': 'paletteRemove',
        'index': 1,
        'replacement': 2,
      });
      expect(e.document.frames[0].cels[0]!.pixels, [1, 0]);
      expect(e.document.frames[1].cels[0]!.link, 0);
      expect(e.document.frames[1].paletteNames[1], 'sun');
      expect(e.document.frames[1].palette.length, 2);
    },
  );
  test('unsafe palette mutations are transactional', () {
    final e = indexed();
    final before = e.encode();
    for (final a in [
      {'action': 'paletteRemove', 'index': 0, 'replacement': 1},
      {'action': 'paletteRemove', 'index': 1, 'replacement': 0},
      {'action': 'paletteEdit', 'index': 9, 'color': 0, 'name': ''},
      {'action': 'paletteMove', 'index': 1.5, 'to': 2},
      {'action': 'paletteEdit', 'index': 1, 'color': -1, 'name': ''},
    ]) {
      expect(() => e.invoke('edit', a), throwsFormatException);
      expect(e.encode(), before);
      expect(e.state()['canUndo'], false);
    }
    e.document.frames[1].palette.add(0);
    expect(
      () => e.invoke('edit', {'action': 'paletteMove', 'index': 1, 'to': 2}),
      throwsFormatException,
    );
  });
  test(
    'indexed to RGBA resolves palette timeline linked and background values',
    () {
      final e = indexed();
      final before = e.encode(),
          pixels = [for (var f = 0; f < 2; f++) e.document.composite(f)];
      e.invoke('edit', {'action': 'convertMode', 'depth': 32});
      expect(e.document.frames[1].cels[0]!.link, isNull);
      for (var f = 0; f < 2; f++) {
        expect(e.document.composite(f), pixels[f]);
      }
      final d = AsepriteCodec.decode(e.encode());
      for (var f = 0; f < 2; f++) {
        expect(d.composite(f), pixels[f]);
      }
      expect(d.frames[1].cels[0]!.data!.text, 'linked-meta');
      e.invoke('undo');
      expect(e.encode(), before);
    },
  );
  test(
    'RGBA indexed conversion reserves extra transparency without erasing black',
    () {
      final e = EditorEngine();
      e.invoke('new', {'width': 3, 'height': 1});
      e.document.frames[0].palette = [0xff000000, 0xff112233, 0x80112233];
      e.document.frames[0].paletteNames = {0: 'black', 1: 'shade'};
      e.document.frames[0].cels[0] = Cel(
        0,
        0,
        3,
        1,
        Uint32List.fromList([0xff000000, 0, 0x80112233]),
      );
      final before = e.encode();
      e.invoke('edit', {'action': 'convertMode', 'depth': 8});
      expect(e.document.transparentIndex, 3);
      expect(e.document.frames[0].cels[0]!.pixels, [0, 3, 2]);
      final d = AsepriteCodec.decode(e.encode());
      expect(d.composite(0), [0xff000000, 0, 0x80112233]);
      expect(d.frames[0].paletteNames[0], 'black');
      e.invoke('undo');
      expect(e.encode(), before);
    },
  );
  test(
    'full palette conversion refuses instead of stealing existing index',
    () {
      final e = EditorEngine();
      e.document.frames[0].palette = List.filled(256, 0xff010203);
      final before = e.encode();
      expect(
        () => e.invoke('edit', {'action': 'convertMode', 'depth': 8}),
        throwsFormatException,
      );
      expect(e.encode(), before);
    },
  );
}
