import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/engine/aseprite.dart';
import 'package:spritedawg/engine/document.dart';
import 'package:spritedawg/platform/desktop_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final backends = <DesktopBackend>[];
  DesktopBackend create({String? open, String? save}) {
    final backend = DesktopBackend(
      openPath: () async => open,
      savePath: (_) async => save,
      supportDirectory: () async => directory,
    );
    backends.add(backend);
    return backend;
  }
  setUp(() async { directory = await Directory.systemTemp.createTemp('internal-drafts'); });
  tearDown(() async {
    for (final backend in backends) { await backend.dispose(); }
    backends.clear();
    await directory.delete(recursive: true);
  });
  Future<void> stroke(DesktopBackend b, int color) async {
    await b.invoke('stroke', {'tool': 'pencil', 'color': color, 'points': [[0, 0]]});
  }

  test('new and imported drafts survive restart and recover with stable IDs', () async {
    final original = File('${directory.path}/original.aseprite');
    final bytes = AsepriteCodec.encode(SpriteDocument.create(3, 2));
    await original.writeAsBytes(bytes);
    final b = create(open: original.path);
    await b.invoke('new', {'width': 2, 'height': 2});
    final first = b.sessions.activeId;
    await stroke(b, 0xffff0000);
    await b.invoke('open', null);
    final imported = b.sessions.activeId;
    await b.invoke('flushDrafts', null);
    expect(await original.readAsBytes(), bytes);
    await b.dispose();
    final restart = create();
    final state = await restart.invoke('init', null);
    expect((state!['drafts'] as List).length, 2);
    await restart.invoke('recover', {'id': first});
    expect(restart.sessions.activeId, first);
    expect(restart.engine.document.composite(0)[0], 0xffff0000);
    await restart.invoke('recover', {'id': imported});
    expect(restart.sessions.active.title, 'original.aseprite');
    expect(restart.sessions.active.path, isNull);
    expect(restart.sessions.active.source, original.path);
    expect(restart.engine.dirty, true);
    expect(await original.readAsBytes(), bytes);
  });

  test('queued flush follows IDs and cannot resurrect discarded or saved documents', () async {
    final b = create(save: '${directory.path}/saved.aseprite');
    await b.invoke('new', null);
    final first = b.sessions.activeId;
    await stroke(b, 0xff00ff00);
    await b.invoke('new', null);
    final second = b.sessions.activeId;
    await stroke(b, 0xffff0000);
    final discard = b.invoke('closeDocument', {'id': first, 'discard': true});
    final flush = b.invoke('flushDrafts', null);
    await Future.wait([discard, flush]);
    expect((await b.drafts.list()).map((d) => d.id), [second]);
    await b.invoke('save', null);
    await b.invoke('flushDrafts', null);
    expect(await b.drafts.list(), isEmpty);
  });

  test('keep-close is recoverable and cancelled close leaves pending work intact', () async {
    final b = create();
    await b.invoke('new', {'width': 4, 'height': 4});
    final id = b.sessions.activeId;
    await stroke(b, 0xff123456);
    await expectLater(b.invoke('closeDocument', {'id': id}), throwsFormatException);
    expect(b.sessions.activeId, id);
    await b.invoke('closeDocument', {'id': id, 'keepDraft': true});
    final list = (await b.invoke('listDrafts', null))!['drafts'] as List;
    expect(list.single['id'], id);
    await b.invoke('recover', {'id': id});
    expect(b.engine.document.composite(0)[0], 0xff123456);
    expect(b.engine.dirty, true);
  });

  test('last good generation and a healthy neighbor survive corrupt current', () async {
    final b = create();
    await b.invoke('new', {'width': 2, 'height': 2});
    final first = b.sessions.activeId;
    await stroke(b, 0xff112233);
    await b.invoke('flushDrafts', null);
    await stroke(b, 0xff445566);
    await b.invoke('flushDrafts', null);
    await b.invoke('new', {'width': 3, 'height': 3});
    final second = b.sessions.activeId;
    await b.invoke('flushDrafts', null);
    await b.dispose();
    await File('${directory.path}/draft-$first.sdd').writeAsBytes([0, 1, 2]);
    await File('${directory.path}/draft-999.sdd').writeAsBytes([0]);
    final restart = create();
    final state = await restart.invoke('init', null);
    expect((state!['drafts'] as List).length, 3);
    await restart.invoke('recover', {'id': first});
    expect(restart.engine.document.composite(0)[0], 0xff112233);
    await restart.invoke('recover', {'id': second});
    expect(restart.engine.document.width, 3);
    expect(await File('${directory.path}/draft-999.sdd').exists(), true);
  });
}
