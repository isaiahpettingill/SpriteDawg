import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/engine/document.dart';
import 'package:spritedawg/engine/editor_engine.dart';

const area = {'x': 0, 'y': 0, 'width': 2, 'height': 1};
EditorEngine fixture({bool indexed = false}) {
  final d = SpriteDocument.create(4, 2);
  if (indexed) {
    d.depth = 8;
    d.transparentIndex = 2;
    d.frames[0].palette = [0xff123456, 0xff123456, 0];
  }
  final c = d.editable(0, 0);
  c.pixels[0] = indexed ? 0 : 0x80123456;
  c.pixels[1] = indexed ? 1 : 0xffaabbcc;
  return EditorEngine()..replace(d);
}

void main() {
  for (final indexed in [false, true]) {
    test(
      'native region copy/move/delete/paste round trip indexed=$indexed',
      () {
        final e = fixture(indexed: indexed);
        final before = e.encode();
        final copy = e.invoke('copyRegion', area);
        expect(e.encode(), before);
        expect(e.state()['dirty'], false);
        expect(e.state()['canUndo'], false);
        e.invoke('edit', {
          'action': 'region',
          'operation': 'move',
          ...area,
          'dx': 1,
          'dy': 0,
        });
        final pixels = e.document.resolved(0, 0)!.pixels;
        expect(
          pixels.take(3),
          indexed ? [2, 0, 1] : [0, 0x80123456, 0xffaabbcc],
        );
        e.invoke('undo');
        expect(e.encode(), before);
        e.invoke('redo');
        e.invoke('edit', {
          'action': 'region',
          'operation': 'delete',
          ...area,
          'x': 1,
        });
        expect(
          e.document.resolved(0, 0)!.pixels.take(3),
          indexed ? [2, 2, 2] : [0, 0, 0],
        );
        e.invoke('edit', {
          'action': 'region',
          'operation': 'paste',
          ...area,
          'clipboard': copy,
        });
        expect(e.document.resolved(0, 0)!.pixels.take(2), [
          for (var i = 0; i < 2; i++)
            ByteData.sublistView(
              copy['pixels'] as Uint8List,
            ).getUint32(i * 4, Endian.little),
        ]);
      },
    );
  }
  test('rejected edits leave pixels, history and dirty state alone', () {
    for (final args in [
      {'operation': 'move', 'dx': -1, 'dy': 0},
      {'operation': 'move', 'dx': 3, 'dy': 0},
      {'operation': 'delete', 'width': 9},
      {'operation': 'paste', 'clipboard': <String, dynamic>{}},
    ]) {
      final e = fixture();
      final before = e.encode();
      expect(
        () => e.invoke('edit', {'action': 'region', ...area, ...args}),
        throwsFormatException,
      );
      expect(e.encode(), before);
      expect(e.state()['canUndo'], false);
      expect(e.dirty, false);
    }
    for (final flags in [1, 11]) {
      final e = fixture();
      e.document.layers[0].flags = flags;
      expect(
        () => e.invoke('edit', {
          'action': 'region',
          'operation': 'delete',
          ...area,
        }),
        throwsFormatException,
      );
    }
    final hidden = fixture();
    hidden.document.layers[0].visible = false;
    expect(
      () => hidden.invoke('edit', {
        'action': 'region',
        'operation': 'delete',
        ...area,
      }),
      throwsFormatException,
    );
  });
  test('indexed palette changes are rejected without recoloring', () {
    final e = fixture(indexed: true);
    final copy = e.invoke('copyRegion', area);
    e.document.frames[0].palette[0] = 0xffffffff;
    final before = e.encode();
    expect(
      () => e.invoke('edit', {
        'action': 'region',
        'operation': 'paste',
        ...area,
        'clipboard': copy,
      }),
      throwsFormatException,
    );
    expect(e.encode(), before);
  });
  test('linked frames and other layers are detached and unchanged', () {
    final e = fixture();
    e.document.frames.add(e.document.frames[0].copy());
    e.document.frames[1].cels[0] = Cel(0, 0, 0, 0, Uint32List(0), link: 0);
    e.document.layers.add(Layer('Other'));
    for (final frame in e.document.frames) {
      frame.cels.add(Cel(-1, -1, 1, 1, Uint32List.fromList([0xffabcdef])));
    }
    final other = List<int>.of(e.document.resolved(1, 0)!.pixels);
    e.invoke('edit', {'action': 'region', 'operation': 'delete', ...area});
    expect(e.document.resolved(1, 0)!.pixels, other);
    expect(e.document.resolved(0, 1)!.pixels.single, 0xffabcdef);
    expect(e.document.resolved(0, 1)!.x, -1);
    e.invoke('undo');
    expect(e.document.resolved(0, 0)!.pixels, other);
  });
  test(
    'grayscale alpha and transparent pixels replace the destination exactly',
    () {
      final e = fixture();
      e.document.depth = 16;
      e.document.editable(0, 0).pixels[0] = 0x80808080;
      e.document.editable(0, 0).pixels[1] = 0;
      final copy = e.invoke('copyRegion', area);
      e.document.editable(0, 0).pixels[3] = 0xffffffff;
      e.invoke('edit', {
        'action': 'region',
        'operation': 'paste',
        ...area,
        'x': 2,
        'clipboard': copy,
      });
      expect(e.document.resolved(0, 0)!.pixels.skip(2).take(2), [
        0x80808080,
        0,
      ]);
    },
  );
  test('oversized copy and malformed clipboard refuse before mutation', () {
    final e = EditorEngine()..replace(SpriteDocument.create(1025, 1024));
    expect(
      () => e.invoke('copyRegion', {
        'x': 0,
        'y': 0,
        'width': 1025,
        'height': 1024,
      }),
      throwsFormatException,
    );
    final small = fixture();
    final copy = small.invoke('copyRegion', area);
    for (final bad in [
      {...copy, 'width': 2.5},
      {...copy, 'pixels': Uint8List(3)},
    ]) {
      expect(
        () => small.invoke('edit', {
          'action': 'region',
          'operation': 'paste',
          ...area,
          'clipboard': bad,
        }),
        throwsFormatException,
      );
      expect(small.dirty, false);
    }
  });
}
