import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/engine/palette_presets.dart';
import 'package:spritedawg/user_palette_store.dart';

void main() {
  late Directory directory;
  late File file;
  late UserPaletteStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('spritedawg-palettes-');
    file = File('${directory.path}/palettes.json');
    store = UserPaletteStore(() async => file);
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'Snapshots survive restart with alpha, order, duplicates and names',
    () async {
      final colors = [0x80449922, 0xffaabbcc, 0x80449922, 0x00112233];
      final names = ['Grass glaze', 'Stone', 'Grass again', 'Clear'];
      final saving = store.save(
        name: 'Terrain',
        colors: colors,
        colorNames: names,
      );
      colors[0] = 0;
      names[0] = 'Changed after save request';
      final saved = await saving;
      final restarted = UserPaletteStore(() async => file);
      final loaded = await restarted.load();
      expect(loaded.single.id, saved.id);
      expect(loaded.single.colors, [
        0x80449922,
        0xffaabbcc,
        0x80449922,
        0x00112233,
      ]);
      expect(loaded.single.colorNames, [
        'Grass glaze',
        'Stone',
        'Grass again',
        'Clear',
      ]);
      expect(() => loaded.single.colors[0] = 0, throwsUnsupportedError);
      expect(
        () => loaded.single.colorNames[0] = 'edit',
        throwsUnsupportedError,
      );
      expect(() => loaded.clear(), throwsUnsupportedError);
    },
  );

  test('Queued saves never overwrite names or lose entries', () async {
    final saves = await Future.wait([
      store.save(name: 'Terrain', colors: [0xff000001]),
      store.save(name: 'terrain', colors: [0xff000002]),
      store.save(name: 'Terrain', colors: [0xff000003]),
    ]);
    expect(saves.map((p) => p.name), ['Terrain', 'terrain (2)', 'Terrain (3)']);
    expect(saves.map((p) => p.id).toSet(), hasLength(3));
    expect((await store.load()).map((p) => p.colors.single), [
      0xff000001,
      0xff000002,
      0xff000003,
    ]);
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });

  test(
    'Editing preserves identity; rename collisions are suffixed, not replaced',
    () async {
      final first = await store.save(name: 'A', colors: [0x40ffffff]);
      final second = await store.save(name: 'B', colors: [0xff000000]);
      final changed = await store.save(
        name: 'B',
        colors: [0x00000000, 0x80ff0000],
        colorNames: ['Clear', 'Fire'],
        replaceId: first.id,
      );
      expect(changed.id, first.id);
      expect(changed.name, 'B (2)');
      final loaded = await store.load();
      expect(loaded[0].colors, [0x00000000, 0x80ff0000]);
      expect(loaded[1].id, second.id);
      expect(loaded[1].colors, [0xff000000]);
      await store.delete(first.id);
      expect((await store.load()).single.id, second.id);
    },
  );

  test('Built-ins cannot be replaced or deleted', () async {
    final original = List<int>.of(palettePresets.first.colors);
    await expectLater(
      store.delete(palettePresets.first.id),
      throwsFormatException,
    );
    await expectLater(
      store.save(name: 'Fake', colors: [0], replaceId: palettePresets.first.id),
      throwsFormatException,
    );
    expect(palettePresets.first.colors, original);
    expect(await store.load(), isEmpty);
  });

  test(
    'Malformed or unsupported files are reported and never erased by save',
    () async {
      for (final contents in [
        '{broken json',
        jsonEncode({'version': 9, 'palettes': []}),
        jsonEncode({
          'version': 1,
          'palettes': [
            {
              'id': 'user-one',
              'name': 'Bad',
              'colors': [-1],
              'colorNames': [],
            },
          ],
        }),
        jsonEncode({
          'version': 1,
          'palettes': [
            {
              'id': 'user-one',
              'name': 'Bad',
              'colors': [1.5],
              'colorNames': [],
            },
          ],
        }),
      ]) {
        await file.writeAsString(contents);
        await expectLater(store.load(), throwsFormatException);
        await expectLater(
          store.save(name: 'New', colors: [0xff112233]),
          throwsFormatException,
        );
        expect(await file.readAsString(), contents);
      }
    },
  );

  test(
    'Write failure retains previous file and does not poison later operations',
    () async {
      await store.save(name: 'Original', colors: [0x804488aa]);
      final original = await file.readAsString();
      // A directory at the temporary-file path forces writeAsString to fail.
      final obstacle = Directory('${file.path}.tmp');
      await obstacle.create();
      await expectLater(
        store.save(name: 'Failed', colors: [0]),
        throwsA(isA<FileSystemException>()),
      );
      expect(await file.readAsString(), original);
      await obstacle.delete();
      await store.save(name: 'Retry', colors: [0]);
      expect((await store.load()).map((p) => p.name), ['Original', 'Retry']);
    },
  );

  test(
    '256 colors remain valid; bad counts and mismatched names fail before write',
    () async {
      await store.save(name: 'Full', colors: List.generate(256, (i) => i));
      expect((await store.load()).single.colors.length, 256);
      final before = await file.readAsString();
      for (final colors in [
        <int>[],
        List.filled(257, 0),
        [-1],
        [0x100000000],
      ]) {
        await expectLater(
          store.save(name: 'Invalid', colors: colors),
          throwsFormatException,
        );
      }
      await expectLater(
        store.save(name: 'Invalid', colors: [0, 1], colorNames: ['one']),
        throwsFormatException,
      );
      expect(await file.readAsString(), before);
    },
  );
  test(
    'Oversize encoded library is rejected before replacing the old file',
    () async {
      final colors = List<int>.generate(256, (i) => i);
      final names = List<String>.filled(256, List.filled(128, 'é').join());
      final records = <Map<String, Object>>[];
      String encode() => jsonEncode({'version': 1, 'palettes': records});
      while (true) {
        records.add({
          'id': 'user-${records.length}',
          'name': 'Stored ${records.length}',
          'colors': colors,
          'colorNames': names,
        });
        if (utf8.encode(encode()).length > 4 * 1024 * 1024) {
          records.removeLast();
          break;
        }
      }
      final before = encode();
      await file.writeAsString(before);
      await expectLater(
        store.save(name: 'Too large', colors: colors, colorNames: names),
        throwsFormatException,
      );
      expect(await file.readAsString(), before);
      expect((await store.load()).length, records.length);
      expect(await File('${file.path}.tmp').exists(), isFalse);
    },
  );
  test(
    'Long source labels are retained and collision names stay editable',
    () async {
      final label = List.filled(1000, '木').join();
      final name = List.filled(80, 'a').join();
      await store.save(name: name, colors: [0x80ffffff], colorNames: [label]);
      final copy = await store.save(name: name, colors: [0], colorNames: ['']);
      expect(copy.name.length, 80);
      expect(copy.name, endsWith(' (2)'));
      expect((await store.load()).first.colorNames.single, label);
      await store.save(name: copy.name, colors: [0], replaceId: copy.id);
      expect((await store.load()).last.name, copy.name);
    },
  );
}
