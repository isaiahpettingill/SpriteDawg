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
    e.invoke('edit', {
      'action': 'paletteAdd',
      'color': 0x80445566,
      'name': 'glow',
    });
    expect(e.document.frames[0].palette[3], 0x80445566);
    expect(e.document.frames[1].palette[1], 0xff0000ff);
    expect(AsepriteCodec.decode(e.encode()).frames[1].paletteNames[3], 'glow');
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
