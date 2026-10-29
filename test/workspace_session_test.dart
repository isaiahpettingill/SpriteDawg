import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/platform/desktop_backend.dart';
import 'package:spritedawg/platform/draft_storage_io.dart';

class FailingWorkspaceStorage extends FileDraftStorage {
  FailingWorkspaceStorage(super.directory);
  bool fail = false;
  @override
  Future<void> writeWorkspace(String value) async {
    if (fail) throw StateError('Simulated workspace write failure');
    await super.writeWorkspace(value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final instances = <DesktopBackend>[];
  DesktopBackend create() {
    final result = DesktopBackend(
      supportDirectory: () async => directory,
      openPath: () async => null,
      savePath: (_) async => null,
    );
    instances.add(result);
    return result;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('workspace-session-');
  });
  tearDown(() async {
    for (final instance in instances) {
      await instance.dispose();
    }
    instances.clear();
    await directory.delete(recursive: true);
  });

  test('first launch and cancelled Open stay empty across restart', () async {
    final first = create();
    final state = (await first.invoke('init', null))!;
    expect(state['hasDocument'], false);
    expect(state['documents'], isEmpty);
    expect(state['width'], 0);
    await first.invoke('open', null);
    expect(first.sessions.documents, isEmpty);
    await expectLater(first.invoke('stroke', {}), throwsStateError);
    await first.dispose();
    final next = create();
    expect((await next.invoke('init', null))!['hasDocument'], false);
  });

  test(
    'last successful dimensions survive close and failed creation',
    () async {
      final first = create();
      await first.invoke('new', {'width': 16, 'height': 24});
      final id = first.sessions.activeId;
      await expectLater(
        first.invoke('new', {'width': 0, 'height': 24}),
        throwsFormatException,
      );
      await expectLater(
        first.invoke('new', {'width': 16.5, 'height': 24}),
        throwsFormatException,
      );
      expect(first.sessions.documents, hasLength(1));
      await first.invoke('closeDocument', {'id': id, 'discard': true});
      expect(first.sessions.documents, isEmpty);
      await first.dispose();
      final next = create();
      final state = (await next.invoke('init', null))!;
      expect(state['lastNewWidth'], 16);
      expect(state['lastNewHeight'], 24);
      expect(state['hasDocument'], false);
      await next.invoke('new', null);
      expect(next.engine.document.width, 16);
      expect(next.engine.document.height, 24);
    },
  );

  test(
    'restores order and selected tab, never explicitly closed drafts',
    () async {
      final first = create();
      final ids = <int>[];
      for (final width in [4, 5, 6]) {
        await first.invoke('new', {'width': width, 'height': 8});
        ids.add(first.sessions.activeId);
      }
      await first.invoke('selectDocument', {'id': ids.first});
      await expectLater(
        first.invoke('closeDocument', {'id': ids.first}),
        throwsFormatException,
      );
      await first.invoke('closeDocument', {'id': ids[1], 'keepDraft': true});
      await first.dispose();
      final next = create();
      final state = (await next.invoke('init', null))!;
      expect(next.sessions.documents.map((s) => s.id), [ids[0], ids[2]]);
      expect(next.sessions.activeId, ids.first);
      expect((state['drafts'] as List).single['id'], ids[1]);
      for (final id in [ids[0], ids[2]]) {
        await next.invoke('closeDocument', {'id': id, 'keepDraft': true});
      }
      await next.dispose();
      final empty = create();
      expect((await empty.invoke('init', null))!['hasDocument'], false);
      expect((await empty.invoke('listDrafts', null))!['drafts'], hasLength(3));
    },
  );

  test('a damaged open draft does not block its healthy neighbor', () async {
    final first = create();
    await first.invoke('new', {'width': 4, 'height': 8});
    final damaged = first.sessions.activeId;
    await first.invoke('new', {'width': 5, 'height': 8});
    final healthy = first.sessions.activeId;
    await first.dispose();
    final damagedFile = File('${directory.path}/draft-$damaged.sdd');
    await damagedFile.writeAsBytes([1, 2, 3]);
    final next = create();
    final state = (await next.invoke('init', null))!;
    expect(next.sessions.documents.map((s) => s.id), [healthy]);
    expect(state['recoveryError'], contains('kept'));
    expect(await damagedFile.readAsBytes(), [1, 2, 3]);
  });

  test(
    'failed close manifest leaves the tab and pending autosave intact',
    () async {
      final storage = FailingWorkspaceStorage(directory);
      final backend = DesktopBackend(
        supportDirectory: () async => directory,
        draftStorage: storage,
      );
      instances.add(backend);
      await backend.invoke('new', {'width': 4, 'height': 4});
      final id = backend.sessions.activeId;
      await backend.invoke('stroke', {
        'tool': 'pencil',
        'color': 0xff123456,
        'points': [
          [0, 0],
        ],
      });
      storage.fail = true;
      await expectLater(
        backend.invoke('closeDocument', {'id': id, 'discard': true}),
        throwsFormatException,
      );
      expect(backend.sessions.activeId, id);
      storage.fail = false;
      expect(
        (await backend.invoke('flushDrafts', null))!['recoveryError'],
        isNull,
      );
      expect(
        (await backend.drafts.load(id)).document.composite(0)[0],
        0xff123456,
      );
      await backend.dispose();
      final restarted = create();
      await restarted.invoke('init', null);
      expect(restarted.sessions.activeId, id);
      expect(restarted.engine.document.composite(0)[0], 0xff123456);
    },
  );

  test('damaged workspace metadata and all drafts remain available', () async {
    final first = create();
    await first.invoke('new', {'width': 4, 'height': 8});
    await first.dispose();
    final manifest = File('${directory.path}/workspace.json');
    await manifest.writeAsString('broken');
    final next = create();
    final state = (await next.invoke('init', null))!;
    expect(state['hasDocument'], false);
    expect(state['recoveryError'], contains('kept'));
    expect(state['drafts'], hasLength(1));
    expect(await manifest.readAsString(), 'broken');
    expect((await next.invoke('recover', null))!['recoveryError'], isNull);
    expect(next.engine.document.width, 4);
    final backups = directory.listSync().whereType<File>().where(
      (file) => file.path.contains('workspace-unreadable-'),
    );
    expect(backups, hasLength(1));
    expect(await backups.single.readAsString(), 'broken');
    expect(await manifest.readAsString(), isNot('broken'));
  });
}
