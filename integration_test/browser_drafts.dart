import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/drafts/draft_repository.dart';
import 'package:spritedawg/drafts/draft_storage.dart';
import 'package:spritedawg/engine/aseprite.dart';
import 'package:spritedawg/engine/document.dart';
import 'package:spritedawg/platform/draft_storage_web.dart';
import 'package:spritedawg/platform/web_backend.dart';
import 'package:web/web.dart' as web;

int _sequence = 0;

IndexedDbDraftStorage browserTestDraftStorage() => IndexedDbDraftStorage(
  databaseName:
      'spritedawg-ci-drafts-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
);

Future<void> removeBrowserTestDraftStorage(IndexedDbDraftStorage storage) async {
  await storage.close();
  final done = Completer<void>();
  final request = web.window.indexedDB.deleteDatabase(storage.databaseName);
  request.addEventListener(
    'success',
    ((web.Event _) => done.complete()).toJS,
  );
  request.addEventListener(
    'error',
    ((web.Event _) => done.completeError(StateError('Test cleanup failed'))).toJS,
  );
  await done.future;
}

Map<String, dynamic> _stroke(int x, int color) => {
  'tool': 'pencil',
  'points': [
    [x, 0],
  ],
  'color': color,
};

class _FailingStorage implements DraftStorage {
  _FailingStorage(this.inner);
  final DraftStorage inner;
  bool failWrites = false;
  @override
  Future<List<int>> ids() => inner.ids();
  @override
  Future<List<Uint8List>> read(int id) => inner.read(id);
  @override
  Future<void> delete(int id) => inner.delete(id);
  @override
  Future<void> write(int id, Uint8List bytes, {Uint8List? previous}) async {
    if (failWrites) throw StateError('Simulated browser quota exceeded');
    await inner.write(id, bytes, previous: previous);
  }
}

void registerBrowserDraftTests() {
  testWidgets('IndexedDB restores imported and unsaved documents independently', (
    tester,
  ) async {
    final storage = browserTestDraftStorage();
    final original = AsepriteCodec.encode(SpriteDocument.create(8, 8));
    final backend = DesktopBackend(
      draftStorage: storage,
      openFile: () async => XFile.fromData(original, name: 'source.aseprite'),
      download: (_, _) async {},
    );
    final restartedStorage = IndexedDbDraftStorage(
      databaseName: storage.databaseName,
    );
    final restarted = DesktopBackend(draftStorage: restartedStorage);
    addTearDown(() async {
      await backend.dispose();
      await restarted.dispose();
      await restartedStorage.close();
      await removeBrowserTestDraftStorage(storage);
    });
    await backend.invoke('init', null);
    await backend.invoke('open', null);
    final imported = backend.sessions.activeId;
    expect(backend.engine.dirty, false);
    // Even an unedited import has its own persistent internal copy.
    expect(await storage.read(imported), isNotEmpty);
    await backend.invoke('new', {'width': 8, 'height': 8});
    final unsaved = backend.sessions.activeId;
    await Future.wait([
      backend.invoke('stroke', _stroke(0, 0xffff0000)),
      backend.invoke('stroke', _stroke(1, 0xff00ff00)),
      backend.invoke('selectDocument', {'id': imported}),
      backend.invoke('stroke', _stroke(2, 0xff0000ff)),
      backend.invoke('flushDrafts', null),
    ]);
    await backend.dispose();
    final state = (await restarted.invoke('init', null))!;
    final drafts = (state['drafts'] as List).cast<Map>();
    expect(drafts.map((draft) => draft['id']).toSet(), {imported, unsaved});
    expect(drafts.every((draft) => (draft['updatedAt'] as int) > 0), true);
    await restarted.invoke('recover', {'id': unsaved});
    expect(restarted.sessions.activeId, unsaved);
    expect(restarted.engine.document.composite(0).take(2), [0xffff0000, 0xff00ff00]);
    expect(restarted.engine.dirty, true);
    await restarted.invoke('recover', {'id': imported});
    expect(restarted.sessions.active.title, 'source.aseprite');
    expect(restarted.sessions.active.source, 'source.aseprite');
    expect(restarted.sessions.active.path, isNull);
    expect(restarted.engine.document.composite(0)[2], 0xff0000ff);
    expect(AsepriteCodec.decode(original).composite(0)[2], 0);
  });

  testWidgets('IndexedDB last-good fallback isolates a corrupt draft', (
    tester,
  ) async {
    final storage = browserTestDraftStorage();
    final backend = DesktopBackend(draftStorage: storage);
    final restartStorage = IndexedDbDraftStorage(databaseName: storage.databaseName);
    final restarted = DesktopBackend(draftStorage: restartStorage);
    addTearDown(() async {
      await backend.dispose();
      await restarted.dispose();
      await restartStorage.close();
      await removeBrowserTestDraftStorage(storage);
    });
    await backend.invoke('new', {'width': 8, 'height': 8});
    await backend.invoke('stroke', _stroke(0, 0xffff0000));
    await backend.invoke('flushDrafts', null);
    final good = backend.sessions.activeId;
    final lastGood = (await storage.read(good)).first;
    await backend.invoke('new', {'width': 8, 'height': 8});
    final corrupt = backend.sessions.activeId;
    await backend.dispose();
    await storage.write(good, Uint8List.fromList([1, 2, 3]), previous: lastGood);
    await storage.write(corrupt, Uint8List.fromList([4, 5, 6]));
    await storage.close();
    final state = (await restarted.invoke('init', null))!;
    final drafts = (state['drafts'] as List).cast<Map>();
    expect(drafts.singleWhere((draft) => draft['id'] == good)['fallback'], true);
    expect(drafts.singleWhere((draft) => draft['id'] == corrupt)['error'], isNotNull);
    await expectLater(restarted.invoke('recover', {'id': corrupt}), throwsFormatException);
    await restarted.invoke('recover', {'id': good});
    expect(restarted.engine.document.composite(0)[0], 0xffff0000);
    expect(await restartStorage.read(corrupt), isNotEmpty);
  });

  testWidgets('browser quota failure retains last good and refuses keep-close', (
    tester,
  ) async {
    final storage = browserTestDraftStorage();
    final failing = _FailingStorage(storage);
    final backend = DesktopBackend(draftStorage: failing);
    addTearDown(() async {
      await backend.dispose();
      await removeBrowserTestDraftStorage(storage);
    });
    await backend.invoke('new', {'width': 8, 'height': 8});
    final id = backend.sessions.activeId;
    final before = (await storage.read(id)).first;
    failing.failWrites = true;
    await backend.invoke('stroke', _stroke(0, 0xffff0000));
    final failed = (await backend.invoke('flushDrafts', null))!;
    expect(failed['recoveryError'], contains('quota exceeded'));
    expect((await storage.read(id)).first, orderedEquals(before));
    await expectLater(
      backend.invoke('closeDocument', {'id': id, 'keepDraft': true}),
      throwsFormatException,
    );
    expect(backend.sessions.activeId, id);
    expect(backend.engine.document.composite(0)[0], 0xffff0000);
    failing.failWrites = false;
    final recovered = (await backend.invoke('flushDrafts', null))!;
    expect(recovered['recoveryError'], isNull);
    expect((await storage.read(id)).first, isNot(orderedEquals(before)));
  });

  testWidgets('only one browser tab can own or discard a draft database', (
    tester,
  ) async {
    final storage = browserTestDraftStorage();
    final secondStorage = IndexedDbDraftStorage(databaseName: storage.databaseName);
    final first = DesktopBackend(draftStorage: storage);
    final second = DesktopBackend(draftStorage: secondStorage);
    addTearDown(() async {
      await first.dispose();
      await second.dispose();
      await removeBrowserTestDraftStorage(storage);
    });
    await first.invoke('new', {'width': 8, 'height': 8});
    final id = first.sessions.activeId;
    await first.invoke('stroke', _stroke(0, 0xff123456));
    await first.invoke('flushDrafts', null);
    final original = (await storage.read(id)).first;
    final blocked = (await second.invoke('init', null))!;
    expect(blocked['recoveryError'], contains('another tab'));
    await expectLater(second.invoke('recover', {'id': id}), throwsStateError);
    await expectLater(second.invoke('discardRecovery', {'id': id}), throwsStateError);
    await second.invoke('new', {'width': 8, 'height': 8});
    expect((await storage.read(id)).first, orderedEquals(original));
    expect(await storage.ids(), [id]);
    await first.dispose();
    await second.invoke('listDrafts', null);
    await second.invoke('recover', {'id': id});
    expect(second.engine.document.composite(0)[0], 0xff123456);
  });

  testWidgets('IndexedDB accounts for both generations atomically', (tester) async {
    final storage = browserTestDraftStorage();
    addTearDown(() => removeBrowserTestDraftStorage(storage));
    await storage.write(1, Uint8List(23), previous: Uint8List(11));
    expect(await storage.totalBytes(), 34);
    expect((await storage.read(1)).map((bytes) => bytes.length), [23, 11]);
    await storage.write(1, Uint8List(31), previous: Uint8List(23));
    expect(await storage.totalBytes(), 54);
    await storage.delete(1);
    expect(await storage.totalBytes(), 0);
    expect(await storage.ids(), isEmpty);
  });

  testWidgets('browser pagehide flushes edits before the normal debounce', (
    tester,
  ) async {
    final storage = browserTestDraftStorage();
    final backend = DesktopBackend(draftStorage: storage);
    final restartedStorage = IndexedDbDraftStorage(databaseName: storage.databaseName);
    final restarted = DesktopBackend(draftStorage: restartedStorage);
    addTearDown(() async {
      await backend.dispose();
      await restarted.dispose();
      await restartedStorage.close();
      await removeBrowserTestDraftStorage(storage);
    });
    await backend.invoke('new', {'width': 8, 'height': 8});
    final id = backend.sessions.activeId;
    await backend.invoke('stroke', _stroke(0, 0xff123456));
    web.window.dispatchEvent(web.Event('pagehide'));
    await backend.invoke('state', null);
    expect(
      (await DraftRepository(storage).load(id)).document.composite(0)[0],
      0xff123456,
      reason: 'The pagehide handler must flush before disposal itself runs.',
    );
    await backend.dispose();
    await restarted.invoke('init', null);
    await restarted.invoke('recover', {'id': id});
    expect(restarted.engine.document.composite(0)[0], 0xff123456);
  });

  testWidgets('browser disposal drains accepted edits before releasing ownership', (
    tester,
  ) async {
    final storage = browserTestDraftStorage();
    final downloadEntered = Completer<void>();
    final releaseDownload = Completer<void>();
    final backend = DesktopBackend(
      draftStorage: storage,
      download: (_, _) async {
        downloadEntered.complete();
        await releaseDownload.future;
      },
    );
    final restartedStorage = IndexedDbDraftStorage(databaseName: storage.databaseName);
    final restarted = DesktopBackend(draftStorage: restartedStorage);
    addTearDown(() async {
      if (!releaseDownload.isCompleted) releaseDownload.complete();
      await backend.dispose();
      await restarted.dispose();
      await removeBrowserTestDraftStorage(storage);
    });
    await backend.invoke('new', {'width': 8, 'height': 8});
    final id = backend.sessions.activeId;
    final held = backend.invoke('save', null);
    await downloadEntered.future;
    final accepted = backend.invoke('stroke', _stroke(0, 0xff123456));
    final disposing = backend.dispose();
    expect(identical(backend.dispose(), disposing), true);
    await expectLater(
      backend.invoke('stroke', _stroke(1, 0xffff0000)),
      throwsStateError,
    );
    releaseDownload.complete();
    await held;
    await accepted;
    await disposing;
    expect(backend.engine.document.composite(0)[0], 0xff123456);
    expect(backend.engine.document.composite(0)[1], 0);
    await restarted.invoke('init', null);
    await restarted.invoke('recover', {'id': id});
    expect(restarted.engine.document.composite(0)[0], 0xff123456);
    expect(restarted.engine.document.composite(0)[1], 0);
  });

  testWidgets('queued flush cannot resurrect discarded browser documents', (
    tester,
  ) async {
    final storage = browserTestDraftStorage();
    final backend = DesktopBackend(draftStorage: storage);
    addTearDown(() async {
      await backend.dispose();
      await removeBrowserTestDraftStorage(storage);
    });
    await backend.invoke('new', {'width': 8, 'height': 8});
    final discarded = backend.sessions.activeId;
    await Future.wait([
      backend.invoke('stroke', _stroke(0, 0xffff0000)),
      backend.invoke('flushDrafts', null),
      backend.invoke('closeDocument', {'id': discarded, 'discard': true}),
      backend.invoke('flushDrafts', null),
    ]);
    expect(await storage.read(discarded), isEmpty);
    await backend.invoke('new', {'width': 8, 'height': 8});
    final kept = backend.sessions.activeId;
    await backend.invoke('stroke', _stroke(0, 0xff00ff00));
    final state = (await backend.invoke('closeDocument', {'id': kept, 'keepDraft': true}))!;
    expect((state['drafts'] as List).cast<Map>().single['id'], kept);
    await backend.invoke('recover', {'id': kept});
    expect(backend.engine.document.composite(0)[0], 0xff00ff00);
  });
}
