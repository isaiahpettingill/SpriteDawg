import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/engine/aseprite.dart';
import 'package:spritedawg/engine/document.dart';
import 'package:spritedawg/engine/editor_engine.dart';

EditorEngine example() {
  final e = EditorEngine();
  e.document.addFrame(0, true);
  e.document.addFrame(1, true);
  e.document.tags.add(
    Tag(
      0,
      1,
      'tiles/grass',
      direction: 3,
      repeat: 7,
      color: Uint8List.fromList([1, 2, 3]),
      data: UserData(
        text: '{"kind":"static","strength":12}',
        color: 0xff123456,
        properties: Uint8List.fromList([8, 0, 0, 0, 0, 0, 0, 0]),
      ),
    ),
  );
  return e;
}

void main() {
  test(
    'updateTag edits only supplied fields, preserving metadata and exact name',
    () {
      final e = example(), before = e.document.tags.single.copy();
      e.invoke('edit', {
        'action': 'updateTag',
        'index': 0,
        'from': 1,
        'to': 2,
        'direction': 2,
        'repeat': 65535,
      });
      final t = e.document.tags.single;
      expect(t.name, before.name);
      expect([t.from, t.to, t.direction, t.repeat], [1, 2, 2, 65535]);
      expect(t.color, before.color);
      expect(t.data!.text, before.data!.text);
      expect(t.data!.color, before.data!.color);
      expect(t.data!.properties, before.data!.properties);
      final reopened = AsepriteCodec.decode(e.encode()).tags.single;
      expect(
        [
          reopened.name,
          reopened.from,
          reopened.to,
          reopened.direction,
          reopened.repeat,
        ],
        [before.name, 1, 2, 2, 65535],
      );
      expect(reopened.color, before.color);
      expect(reopened.data!.properties, before.data!.properties);
      expect(reopened.data!.text, before.data!.text);
    },
  );
  test('updateTag undo and redo restore full document', () {
    final e = example(), before = e.encode();
    e.invoke('edit', {
      'action': 'updateTag',
      'index': 0,
      'name': 'idle',
      'from': 2,
      'to': 2,
      'direction': 0,
      'repeat': 0,
    });
    final after = e.encode();
    e.invoke('undo');
    expect(e.encode(), before);
    e.invoke('redo');
    expect(e.encode(), after);
  });
  test('duplicateTag preserves name and deeply copies metadata/color', () {
    final e = example();
    e.invoke('edit', {'action': 'duplicateTag', 'index': 0});
    expect(e.document.tags.length, 2);
    final a = e.document.tags[0], b = e.document.tags[1];
    expect(b.name, a.name);
    expect(b.color, a.color);
    expect(b.data!.properties, a.data!.properties);
    b.color[0] = 77;
    b.data!.properties![0] = 9;
    b.data!.text = 'changed';
    expect(a.color[0], 1);
    expect(a.data!.properties![0], 8);
    expect(a.data!.text, contains('static'));
  });
  test(
    'duplicateTag optional overrides are one undo transaction and preserve source',
    () {
      final e = example(), before = e.encode();
      e.invoke('edit', {
        'action': 'duplicateTag',
        'index': 0,
        'name': 'tiles/water',
        'from': 1,
        'to': 2,
        'direction': 1,
        'repeat': 4,
      });
      final t = e.document.tags.last;
      expect(
        [t.name, t.from, t.to, t.direction, t.repeat],
        ['tiles/water', 1, 2, 1, 4],
      );
      expect(e.document.tags.first.name, 'tiles/grass');
      final after = e.encode();
      final reopened = AsepriteCodec.decode(after);
      expect(
        reopened.tags[0].data!.properties,
        reopened.tags[1].data!.properties,
      );
      e.invoke('undo');
      expect(e.encode(), before);
      e.invoke('redo');
      expect(e.encode(), after);
    },
  );
  test(
    'invalid tag edits leave document selection and undo history untouched',
    () {
      for (final fields in <Map<String, dynamic>>[
        {'index': -1},
        {'index': 1},
        {'from': 2, 'to': 1},
        {'from': -1},
        {'to': 3},
        {'direction': 4},
        {'direction': -1},
        {'repeat': 65536},
        {'repeat': -1},
        {'direction': 1.5},
        {'repeat': '2'},
        {'name': 'é' * 32768},
      ]) {
        for (final action in ['updateTag', 'duplicateTag']) {
          final e = example(), before = e.encode();
          expect(
            () => e.invoke('edit', {'action': action, 'index': 0, ...fields}),
            throwsFormatException,
          );
          expect(e.encode(), before);
          expect(e.state()['canUndo'], false);
          expect(e.dirty, false);
          expect(e.frame, 0);
        }
      }
    },
  );
  test(
    'single-frame variants and multi-frame animations use ordinary ASE tags',
    () {
      final e = example();
      e.invoke('edit', {
        'action': 'addTag',
        'name': 'tile_stone',
        'from': 2,
        'to': 2,
        'repeat': 0,
        'direction': 0,
      });
      final t = AsepriteCodec.decode(e.encode()).tags.last;
      expect(t.name, 'tile_stone');
      expect([t.from, t.to], [2, 2]);
      expect(t.data?.text, isNull);
      expect(t.data?.properties, isNull);
      expect(t.data?.color, isNull);
    },
  );
  test(
    'thumbnails are bounded nearest-neighbor and have no editor side effects',
    () {
      final e = example();
      e.document.width = 128;
      e.document.height = 64;
      final c = e.document.editable(1, 0);
      c.pixels[0] = 0xff123456;
      c.pixels[2] = 0xffabcdef;
      e.invoke('select', {'frame': 2});
      final before = e.encode(), state = e.state();
      final response = e.invoke('thumbnails', {
        'frames': [1, 0],
        'maxSize': 64,
      });
      final thumbs = response['thumbnails'] as List;
      expect(thumbs.length, 2);
      expect(
        [thumbs[0]['frame'], thumbs[0]['width'], thumbs[0]['height']],
        [1, 64, 32],
      );
      expect((thumbs[0]['pixels'] as Uint8List).take(8), [
        0x12,
        0x34,
        0x56,
        255,
        0xab,
        0xcd,
        0xef,
        255,
      ]);
      expect(e.encode(), before);
      expect(e.frame, 2);
      expect(e.dirty, state['dirty']);
      expect(e.state()['canUndo'], state['canUndo']);
      expect(e.state()['canRedo'], state['canRedo']);
    },
  );
  test(
    'thumbnail invalid requests fail without mutations and size is capped',
    () {
      final e = example(), before = e.encode();
      for (final args in <Map<String, dynamic>>[
        {'frames': List.filled(33, 0)},
        {
          'frames': [-1],
        },
        {
          'frames': [3],
        },
        {
          'frames': [0.1],
        },
        {
          'frames': [0],
          'maxSize': 0,
        },
        {
          'frames': [0],
          'maxSize': 1.2,
        },
      ]) {
        expect(() => e.invoke('thumbnails', args), throwsFormatException);
        expect(e.encode(), before);
      }
      e.document.width = 128;
      e.document.height = 256;
      final thumb =
          (e.invoke('thumbnails', {
                    'frames': [0],
                    'maxSize': 1000,
                  })['thumbnails']
                  as List)
              .single;
      expect([thumb['width'], thumb['height']], [32, 64]);
      expect(e.invoke('thumbnails', {'frames': []})['thumbnails'], isEmpty);
    },
  );
  test('thumbnail small canvases are not upscaled', () {
    final e = EditorEngine();
    e.invoke('new', {'width': 2, 'height': 1});
    final t =
        (e.invoke('thumbnails', {
                  'frames': [0],
                })['thumbnails']
                as List)
            .single;
    expect([t['width'], t['height']], [2, 1]);
  });
}
