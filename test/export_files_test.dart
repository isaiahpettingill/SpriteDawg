import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/platform/export_files.dart';

void main() {
  late Directory root;
  final png = Uint8List.fromList([1, 2, 3]);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('export-test-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test('cancel does not create files', () async {
    final saver = ExportFiles(
      pickFile: (_, _) async => null,
      pickDirectory: () async => null,
    );
    expect(
      await saver.save({
        'name': 'sprite',
        'files': {'sprite.png': png},
      }),
      {'saved': false},
    );
    expect(
      await saver.save({
        'name': 'sprite',
        'files': {'sprite.png': png, 'sprite.json': png},
      }),
      {'saved': false},
    );
    expect(await root.list().toList(), isEmpty);
  });
  test(
    'explicit single save replaces only picked output and removes temporary files',
    () async {
      final file = File('${root.path}/chosen.png');
      await file.writeAsString('old');
      final saver = ExportFiles(pickFile: (_, _) async => file.path);
      expect(
        (await saver.save({
          'name': 'sprite',
          'files': {'sprite.png': png},
        }))['saved'],
        true,
      );
      expect(await file.readAsBytes(), png);
      expect((await root.list().toList()).length, 1);
    },
  );
  test(
    'paired exports create unique folders and preserve earlier pairs',
    () async {
      final saver = ExportFiles(pickDirectory: () async => root.path);
      final args = {
        'name': 'sprite',
        'files': {'sprite.png': png, 'sprite.json': png},
      };
      final a = await saver.save(args), b = await saver.save(args);
      expect(a['location'], isNot(b['location']));
      for (final result in [a, b]) {
        expect(
          await File('${result['location']}/sprite.png').readAsBytes(),
          png,
        );
        expect(
          await File('${result['location']}/sprite.json').readAsBytes(),
          png,
        );
      }
      expect((await root.list().toList()).length, 2);
    },
  );
  test('reject path traversal before showing destination picker', () async {
    var called = false;
    final saver = ExportFiles(
      pickFile: (_, _) async {
        called = true;
        return null;
      },
    );
    await expectLater(
      saver.save({
        'name': 'sprite',
        'files': {'../bad.png': png},
      }),
      throwsFormatException,
    );
    expect(called, false);
  });
}
