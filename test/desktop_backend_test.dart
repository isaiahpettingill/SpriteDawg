import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/engine/aseprite.dart';
import 'package:spritedawg/engine/document.dart';
import 'package:spritedawg/platform/desktop_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory base;
  late String? openPath, savePath;
  late DesktopBackend backend;
  setUp(() async {
    base = await Directory.systemTemp.createTemp('spritedawg-backend-test-');
    openPath = null;
    savePath = null;
    backend = DesktopBackend(
      openPath: () async => openPath,
      savePath: (_) async => savePath,
      supportDirectory: () async => Directory('${base.path}/support'),
    );
    await backend.invoke('init', null);
  });
  tearDown(() async {
    await base.delete(recursive: true);
  });
  Future<void> draw() => backend
      .invoke('stroke', {
        'tool': 'pencil',
        'points': [
          [2, 2],
        ],
        'color': 0xffff0000,
      })
      .then((_) {});
  File recovery() => File('${base.path}/support/recovery.aseprite');
  test(
    'cancel open/save/saveAs/export leaves state, history, and recovery intact',
    () async {
      await draw();
      final before = backend.engine.encode();
      for (final action in ['open', 'save', 'saveAs', 'exportPng']) {
        await backend.invoke(action, null);
        expect(backend.engine.encode(), before);
        expect(backend.engine.dirty, true);
        expect(backend.engine.state()['canUndo'], true);
        expect(await recovery().exists(), true);
      }
    },
  );
  test('malformed open never replaces current document or recovery', () async {
    await draw();
    final before = backend.engine.encode(),
        recover = await recovery().readAsBytes();
    final bad = File('${base.path}/bad.aseprite');
    await bad.writeAsBytes([1, 2, 3]);
    openPath = bad.path;
    await expectLater(backend.invoke('open', null), throwsFormatException);
    expect(backend.engine.encode(), before);
    expect(await recovery().readAsBytes(), recover);
    expect(backend.engine.dirty, true);
    expect(backend.engine.state()['canUndo'], true);
  });
  test(
    'save is valid, clears dirty/recovery; subsequent save reuses path',
    () async {
      await draw();
      savePath = '${base.path}/drawing.aseprite';
      await backend.invoke('saveAs', null);
      final saved = File(savePath!);
      expect(
        AsepriteCodec.decode(await saved.readAsBytes()).composite(0)[66],
        0xffff0000,
      );
      expect(backend.engine.dirty, false);
      expect(await recovery().exists(), false);
      savePath = null;
      await draw();
      await backend.invoke('save', null);
      expect(backend.engine.dirty, false);
      expect(await recovery().exists(), false);
      expect(base.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
    },
  );
  test('failed save keeps dirty document and fresh recovery', () async {
    await draw();
    savePath = '${base.path}/missing/failed.aseprite';
    final before = backend.engine.encode();
    await expectLater(
      backend.invoke('saveAs', null),
      throwsA(isA<FileSystemException>()),
    );
    expect(backend.engine.dirty, true);
    expect(backend.engine.encode(), before);
    expect(
      AsepriteCodec.decode(await recovery().readAsBytes()).composite(0)[66],
      0xffff0000,
    );
    expect(await File(savePath!).exists(), false);
  });
  test(
    'recovery failure warns but does not throw away committed edit',
    () async {
      await recovery().create();
      await recovery().delete();
      await Directory(recovery().path).create();
      final state = await backend.invoke('stroke', {
        'tool': 'pencil',
        'points': [
          [2, 2],
        ],
        'color': 0xffff0000,
      });
      expect(
        state!['recoveryError'],
        contains('Recovery could not be written'),
      );
      expect(backend.engine.dirty, true);
      expect(backend.engine.document.composite(0)[66], 0xffff0000);
    },
  );
  test('recover opens unsaved copy without overwrite path', () async {
    await draw();
    final other = DesktopBackend(
      openPath: () async => null,
      savePath: (_) async => null,
      supportDirectory: () async => Directory('${base.path}/support'),
    );
    final state = await other.invoke('init', null);
    expect(state!['recoveryAvailable'], true);
    await other.invoke('recover', null);
    expect(other.engine.document.composite(0)[66], 0xffff0000);
    expect(other.engine.dirty, true);
    await other.invoke('save', null);
    expect(other.engine.dirty, true);
    expect(await recovery().exists(), true);
  });
  test(
    'successful open resets history after decoding and clears old recovery',
    () async {
      await draw();
      final file = File('${base.path}/valid.aseprite');
      await file.writeAsBytes(
        AsepriteCodec.encode(SpriteDocument.create(8, 8)),
      );
      openPath = file.path;
      await backend.invoke('open', null);
      expect(backend.engine.document.width, 8);
      expect(backend.engine.dirty, false);
      expect(backend.engine.state()['canUndo'], false);
      expect(await recovery().exists(), false);
    },
  );
  test('corrupt recovery cannot replace current document', () async {
    await draw();
    final before = backend.engine.encode();
    await recovery().writeAsBytes(Uint8List(10));
    await expectLater(backend.invoke('recover', null), throwsFormatException);
    expect(backend.engine.encode(), before);
  });
  test(
    'overlapping operations serialize and error does not poison queue',
    () async {
      final first = backend.invoke('stroke', {
        'tool': 'pencil',
        'points': [
          [0, 0],
        ],
        'color': 0xff00ff00,
      });
      final second = backend.invoke('stroke', {
        'tool': 'pencil',
        'points': [
          [1, 0],
        ],
        'color': 0xffff0000,
      });
      await Future.wait([first, second]);
      expect(backend.engine.document.composite(0).take(2), [
        0xff00ff00,
        0xffff0000,
      ]);
      await expectLater(
        backend.invoke('edit', {'action': 'deleteLayer'}),
        throwsFormatException,
      );
      await backend.invoke('undo', null);
      expect(backend.engine.document.composite(0)[1], 0);
    },
  );
  test('cleanup failure returns newly opened state with a warning', () async {
    if (!Platform.isLinux) return;
    await draw();
    final valid = File('${base.path}/cleanup-open.aseprite');
    await valid.writeAsBytes(AsepriteCodec.encode(SpriteDocument.create(8, 8)));
    openPath = valid.path;
    final support = '${base.path}/support';
    await Process.run('chmod', ['500', support]);
    try {
      final state = await backend.invoke('open', null);
      expect(state!['width'], 8);
      expect(state['dirty'], false);
      expect(
        state['recoveryError'],
        contains('old recovery could not be removed'),
      );
    } finally {
      await Process.run('chmod', ['700', support]);
    }
  });
}
