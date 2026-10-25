import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:spritedawg/engine/aseprite.dart';
import 'package:spritedawg/engine/document.dart';
import 'package:spritedawg/engine/deflate_boundary.dart';
import 'package:spritedawg/engine/editor_engine.dart';

SpriteDocument round(SpriteDocument d, {bool compressed = true}) =>
    AsepriteCodec.decode(AsepriteCodec.encode(d, compressed: compressed));
void main() {
  test(
    'zlib scanner validates stored/fixed/dynamic streams and rejects trailing bytes',
    () {
      final random = Random(1);
      for (final level in [0, 1, 6, 9]) {
        for (final size in [1, 10, 100, 1000, 10000, 100000]) {
          for (final noise in [false, true]) {
            final bytes = List.generate(
              size,
              (i) => noise ? random.nextInt(256) : i % 4,
            );
            final compressed = Uint8List.fromList(
              ZLibEncoder(level: level).convert(bytes),
            );
            validateZlib(compressed, size);
            expect(
              () => validateZlib(
                Uint8List.fromList([...compressed, 1, 2, 3]),
                size,
              ),
              throwsFormatException,
            );
          }
        }
      }
    },
  );

  test('every byte truncation is rejected', () {
    final d = SpriteDocument.create(3, 2);
    d.editable(0, 0).pixels[0] = 0x80123456;
    final b = AsepriteCodec.encode(d);
    for (var n = 0; n < b.length; n++) {
      expect(
        () => AsepriteCodec.decode(Uint8List.fromList(b.sublist(0, n))),
        throwsFormatException,
      );
    }
  });
  test('malformed typed properties and non-normal blending refuse', () {
    final d = SpriteDocument.create();
    d.data = UserData(properties: Uint8List.fromList([8, 0, 0, 0, 1, 0, 0, 0]));
    expect(() => round(d), throwsFormatException);
    d.data = null;
    final b = AsepriteCodec.encode(d);
    ByteData.sublistView(b).setUint16(160, 1, Endian.little);
    expect(() => AsepriteCodec.decode(b), throwsFormatException);
  });

  test('normal blend uses official Aseprite integer rounding', () {
    expect(over(0xff00cdf9, 0xffed7614, 128), 0xff76a287);
    expect(over(0, 0x00123456, 255), 0x00123456);
    expect(over(0xff123456, 0x00abcdef, 128), 0xff123456);
    expect(over(0, 0x01123456, 128), 0x01123456);
    expect(over(0xff123456, 0xffffffff, 0), 0xff123456);
  });

  test(
    'legacy six-bit palette matches LibreSprite and asefile all 64 values',
    () {
      final d = SpriteDocument.create(1, 1)..depth = 8;
      final raw = Uint8List(4 + 64 * 3);
      final b = ByteData.sublistView(raw);
      b.setUint16(0, 1, Endian.little);
      raw[2] = 0;
      raw[3] = 64;
      for (var i = 0; i < 64; i++) {
        raw[4 + i * 3] = i;
        raw[5 + i * 3] = i;
        raw[6 + i * 3] = i;
      }
      d.frames[0].palette = List.generate(256, (i) => 0xff000000);
      d.frames[0].metadata.add(RawChunk(17, raw));
      // Inject legacy chunk into a standalone frame, with no modern palette.
      final bytes = AsepriteCodec.encode(d);
      final header = Uint8List.fromList(bytes.sublist(0, 128));
      final frame = ByteData(16 + 6 + raw.length + 26);
      // One minimal normal layer plus the legacy palette chunk.
      final layer = [
        26,
        0,
        0,
        0,
        4,
        32,
        3,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        255,
        0,
        0,
        0,
        2,
        0,
        76,
        49,
      ];
      frame.setUint32(0, frame.lengthInBytes, Endian.little);
      frame.setUint16(4, 0xf1fa, Endian.little);
      frame.setUint16(6, 2, Endian.little);
      frame.setUint16(8, 100, Endian.little);
      frame.setUint32(12, 2, Endian.little);
      final fb = frame.buffer.asUint8List();
      fb.setAll(16, layer);
      frame.setUint32(42, raw.length + 6, Endian.little);
      frame.setUint16(46, 17, Endian.little);
      fb.setAll(48, raw);
      final out = Uint8List.fromList([...header, ...fb]);
      ByteData.sublistView(out).setUint32(0, out.length, Endian.little);
      final decoded = AsepriteCodec.decode(out);
      for (var i = 0; i < 64; i++) {
        final v = (i << 2) | (i >> 4);
        expect(decoded.frames[0].palette[i], 0xff000000 | v << 16 | v << 8 | v);
      }
    },
  );
  test('RGBA raw and zlib round trip, invisible RGB preserved', () {
    final d = SpriteDocument.create(2, 2);
    d.editable(0, 0).pixels.setAll(0, [0x00123456, 0xff123456, 0x80123456, 0]);
    for (final compressed in [true, false]) {
      final r = round(d, compressed: compressed);
      expect(r.resolved(0, 0)!.pixels, d.resolved(0, 0)!.pixels);
      expect(r.composite(0)[0], 0x00123456);
    }
  });
  test('native grayscale and indexed stay native', () {
    for (final depth in [8, 16]) {
      final d = SpriteDocument.create(2, 1)..depth = depth;
      if (depth == 8) {
        d.transparentIndex = 1;
        d.frames[0].palette = [0xffff0000, 0xff000000, 0xff00ff00];
        d.editable(0, 0).pixels[0] = 2;
      } else {
        d.editable(0, 0).pixels[0] = 0x80575757;
      }
      final r = round(d);
      expect(r.depth, depth);
      expect(r.resolved(0, 0)!.pixels, d.resolved(0, 0)!.pixels);
      expect(r.composite(0), d.composite(0));
    }
  });
  test(
    'user data, opaque typed properties, tag repeat/direction preserved',
    () {
      final d = SpriteDocument.create(2, 2);
      final u = UserData(
        text: '{"health":40}',
        color: 0xff123456,
        properties: Uint8List.fromList([8, 0, 0, 0, 0, 0, 0, 0]),
      );
      d.data = u.copy();
      d.layers[0].data = u.copy();
      d.editable(0, 0).data = u.copy();
      d.tags.add(Tag(0, 0, 'Walk', direction: 3, repeat: 7, data: u.copy()));
      final r = round(d);
      for (final target in [
        r.data,
        r.layers[0].data,
        r.frames[0].cels[0]!.data,
        r.tags[0].data,
      ]) {
        expect(target!.text, u.text);
        expect(target.color, u.color);
        expect(target.properties, u.properties);
      }
      expect(r.tags[0].repeat, 7);
      expect(r.tags[0].direction, 3);
    },
  );
  test('linked cel edit detaches without modifying other frames', () {
    final d = SpriteDocument.create(2, 2);
    d.editable(0, 0).pixels[0] = 0xff123456;
    d.addFrame(0, false);
    d.frames[1].cels[0] = Cel(0, 0, 0, 0, Uint32List(0), link: 0);
    final r = round(d);
    r.editable(0, 0).pixels[0] = 0;
    expect(r.resolved(1, 0)!.pixels[0], 0xff123456);
  });
  test(
    'delete palette-changing frame preserves effective colors and names',
    () {
      Uint8List partial(int index, int color) {
        final b = ByteData(26);
        b.setUint32(0, 3, Endian.little);
        b.setUint32(4, index, Endian.little);
        b.setUint32(8, index, Endian.little);
        b.setUint8(22, color >> 16 & 255);
        b.setUint8(23, color >> 8 & 255);
        b.setUint8(24, color & 255);
        b.setUint8(25, 255);
        return b.buffer.asUint8List();
      }

      final d = SpriteDocument(
        1,
        1,
        [Layer('L')],
        [
          Frame(cels: [null], palette: [0, 0xff000000, 0xffffffff]),
          Frame(
            cels: [null],
            palette: [0, 0xffff0000, 0xffffffff],
            paletteNames: {1: 'Fire'},
            metadata: [RawChunk(0x2019, partial(1, 0xffff0000))],
          ),
          Frame(
            cels: [null],
            palette: [0, 0xffff0000, 0xff0000ff],
            paletteNames: {1: 'Fire'},
            metadata: [RawChunk(0x2019, partial(2, 0xff0000ff))],
          ),
        ],
        depth: 8,
      );
      d.removeFrame(1);
      final r = round(d);
      expect(r.frames[1].palette, d.frames[1].palette);
      expect(r.frames[1].paletteNames[1], 'Fire');
    },
  );
  test('drawing undo/redo and failed edits are atomic', () {
    final e = EditorEngine();
    e.invoke('stroke', {
      'tool': 'line',
      'points': [
        [0, 0],
        [31, 31],
      ],
      'color': 0xffff0000,
      'size': 1,
    });
    expect(e.document.composite(0).where((c) => c != 0).length, 32);
    e.invoke('undo');
    expect(e.document.composite(0).every((c) => c == 0), true);
    e.invoke('redo');
    expect(e.document.composite(0)[0], 0xffff0000);
    final before = e.encode();
    expect(
      () => e.invoke('edit', {'action': 'deleteLayer'}),
      throwsFormatException,
    );
    expect(e.encode(), before);
  });
  test('all drawing tools produce pixels and fill is bounded', () {
    for (final tool in [
      'pencil',
      'eraser',
      'fill',
      'line',
      'rectangle',
      'ellipse',
    ]) {
      final e = EditorEngine();
      if (tool == 'eraser') {
        e.invoke('stroke', {
          'tool': 'fill',
          'points': [
            [0, 0],
          ],
          'color': 0xff123456,
        });
      }
      e.invoke('stroke', {
        'tool': tool,
        'points': [
          [2, 2],
          [10, 10],
        ],
        'color': 0xffff0000,
      });
      if (tool == 'eraser') {
        expect(e.document.composite(0)[2 * 32 + 2], 0);
      } else {
        expect(e.document.composite(0).any((c) => c != 0), true);
      }
    }
  });
  test('metadata edits retain typed properties', () {
    final e = EditorEngine();
    final props = Uint8List.fromList([8, 0, 0, 0, 0, 0, 0, 0]);
    e.document.data = UserData(text: 'old', properties: props);
    e.invoke('edit', {'action': 'userData', 'target': 'sprite', 'text': 'new'});
    expect(round(e.document).data!.properties, props);
  });
  test('off canvas pixels survive drawing and resizing', () {
    final e = EditorEngine();
    e.document.frames[0].cels[0] = Cel(
      -1,
      -1,
      2,
      2,
      Uint32List.fromList([0xff123456, 0, 0, 0]),
    );
    e.invoke('stroke', {
      'tool': 'pencil',
      'points': [
        [1, 1],
      ],
      'color': 0xffff0000,
    });
    expect(e.document.resolved(0, 0)!.pixels[0], 0xff123456);
    e.invoke('edit', {'action': 'resize', 'width': 8, 'height': 8});
    expect(round(e.document).resolved(0, 0)!.pixels[0], 0xff123456);
  });
  test('truncated and unknown chunks refuse without editing original', () {
    final e = EditorEngine();
    final bytes = e.encode();
    expect(
      () => AsepriteCodec.decode(
        Uint8List.fromList(bytes.sublist(0, bytes.length - 1)),
      ),
      throwsFormatException,
    );
    final bad = Uint8List.fromList(bytes);
    ByteData.sublistView(bad).setUint16(148, 0x2022, Endian.little);
    expect(() => AsepriteCodec.decode(bad), throwsFormatException);
  });
  final root = Directory('app/src/test/resources/upstream');
  if (root.existsSync()) {
    test('real upstream typed property payloads survive text editing', () {
      final bytes = File(
            '${root.path}/file-tests-props.aseprite',
          ).readAsBytesSync(),
          b = ByteData.sublistView(
            File('${root.path}/file-tests-props.aseprite').readAsBytesSync(),
          );
      var frame = 128, tested = 0;
      while (frame < bytes.length) {
        final end = frame + b.getUint32(frame, Endian.little);
        var c = frame + 16;
        while (c < end) {
          final size = b.getUint32(c, Endian.little),
              type = b.getUint16(c + 4, Endian.little);
          if (type == 0x2020) {
            final flags = b.getUint32(c + 6, Endian.little);
            var p = c + 10;
            if (flags & 1 != 0) p += 2 + b.getUint16(p, Endian.little);
            if (flags & 2 != 0) p += 4;
            if (flags & 4 != 0 &&
                b.getUint32(p + 4, Endian.little) == 1 &&
                b.getUint32(p + 8, Endian.little) == 0) {
              final props = Uint8List.fromList(bytes.sublist(p, c + size));
              final e = EditorEngine();
              e.document.data = UserData(properties: props);
              e.invoke('edit', {
                'action': 'userData',
                'target': 'sprite',
                'text': 'new game metadata',
              });
              expect(round(e.document).data!.properties, props);
              tested++;
            }
          }
          c += size;
        }
        frame = end;
      }
      expect(tested > 0, true);
    });

    for (final name in [
      '1empty3.aseprite',
      '2f-index-3x3.aseprite',
      '4f-index-4x4.aseprite',
      'abcd.aseprite',
      'bg-index-3.aseprite',
      'cut_paste.aseprite',
      'link.aseprite',
      'point2frames.aseprite',
      'point4frames.aseprite',
      'tags3.aseprite',
      'tags3x123reps.aseprite',
    ]) {
      test(
        'upstream $name round trip preserves rendered pixels and metadata',
        () {
          final d = AsepriteCodec.decode(
                File('${root.path}/$name').readAsBytesSync(),
              ),
              r = round(d);
          expect(r.frames.length, d.frames.length);
          expect(r.layers.length, d.layers.length);
          expect(r.depth, d.depth);
          for (var i = 0; i < d.frames.length; i++) {
            expect(r.composite(i), d.composite(i));
            expect(r.frames[i].duration, d.frames[i].duration);
            expect(r.frames[i].palette, d.frames[i].palette);
            expect(r.frames[i].paletteNames, d.frames[i].paletteNames);
          }
          expect(
            r.tags.map(
              (t) => [
                t.name,
                t.from,
                t.to,
                t.repeat,
                t.direction,
                t.data?.text,
              ],
            ),
            d.tags.map(
              (t) => [
                t.name,
                t.from,
                t.to,
                t.repeat,
                t.direction,
                t.data?.text,
              ],
            ),
          );
        },
      );
    }
    for (final name in [
      'file-tests-props.aseprite',
      '2x2tilemap2x2tile.aseprite',
      '2x3tilemap-indexed.aseprite',
      '3x2tilemap-grayscale.aseprite',
      'groups2.aseprite',
      'groups3abc.aseprite',
      'slices-moving.aseprite',
      'slices.aseprite',
      'z-order.aseprite',
    ]) {
      test('upstream $name refuses unsupported features', () {
        expect(
          () => AsepriteCodec.decode(
            File('${root.path}/$name').readAsBytesSync(),
          ),
          throwsFormatException,
        );
      });
    }
  }
}
