import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/drafts/draft_repository.dart';
import 'package:spritedawg/drafts/draft_storage.dart';
import 'package:spritedawg/engine/aseprite.dart';
import 'package:spritedawg/engine/document.dart';

class MemoryDraftStorage implements DraftStorage {
  final records = <int, List<Uint8List>>{};
  bool fail = false;
  @override
  Future<List<int>> ids() async => records.keys.toList();
  @override
  Future<List<Uint8List>> read(int id) async => records[id] ?? [];
  @override
  Future<void> write(int id, Uint8List bytes, {Uint8List? previous}) async {
    if (fail) throw StateError('disk full');
    records[id] = [bytes, ?previous];
  }
  @override
  Future<void> delete(int id) async { records.remove(id); }
}

void main() {
  test('restart preserves independent named imported and unsaved drafts', () async {
    final storage = MemoryDraftStorage();
    final repo = DraftRepository(storage, now: () => 100);
    await repo.save(id: 1, title: 'Untitled', document: SpriteDocument.create(2, 3));
    await repo.save(id: 2, title: 'hero.aseprite', source: 'content://original', document: SpriteDocument.create(4, 5));
    final restart = DraftRepository(storage);
    final draft = await restart.load(2);
    expect(draft.info.title, 'hero.aseprite');
    expect(draft.source, 'content://original');
    expect(draft.info.updatedAt, 100);
    expect(draft.document.width, 4);
    expect((await restart.list()).map((d) => d.id), containsAll([1, 2]));
  });

  test('damaged newest snapshot falls back without poisoning next backup', () async {
    final storage = MemoryDraftStorage();
    final repo = DraftRepository(storage);
    await repo.save(id: 1, title: 'first', document: SpriteDocument.create(2, 2));
    await repo.save(id: 1, title: 'second', document: SpriteDocument.create(3, 3));
    storage.records[1]!.first[30] ^= 1;
    expect((await repo.load(1)).info.fallback, true);
    expect((await repo.load(1)).document.width, 2);
    await repo.save(id: 1, title: 'third', document: SpriteDocument.create(4, 4));
    storage.records[1]!.first[30] ^= 1;
    expect((await repo.load(1)).document.width, 2);
  });

  test('one corrupt draft does not hide others and is never deleted', () async {
    final storage = MemoryDraftStorage();
    final repo = DraftRepository(storage);
    storage.records[9] = [Uint8List(100)];
    await repo.save(id: 1, title: 'safe', document: SpriteDocument.create());
    final list = await repo.list();
    expect(list.singleWhere((d) => d.id == 9).error, isNotNull);
    expect(list.singleWhere((d) => d.id == 1).error, isNull);
    expect(storage.records.containsKey(9), true);
  });

  test('quota and write failures preserve previous snapshot and other drafts', () async {
    final storage = MemoryDraftStorage();
    final repo = DraftRepository(storage, maxDrafts: 1);
    await repo.save(id: 1, title: 'safe', document: SpriteDocument.create(2, 2));
    await expectLater(repo.save(id: 2, title: 'new', document: SpriteDocument.create()), throwsStateError);
    storage.fail = true;
    await expectLater(repo.save(id: 1, title: 'unsaved', document: SpriteDocument.create(3, 3)), throwsStateError);
    expect((await repo.load(1)).document.width, 2);
    storage.fail = false;
    final full = DraftRepository(storage, maxBytes: 1);
    await expectLater(full.save(id: 1, title: 'too large', document: SpriteDocument.create()), throwsStateError);
    expect((await repo.load(1)).document.width, 2);
  });

  test('legacy raw recovery migrates without changing pixels', () async {
    final storage = MemoryDraftStorage();
    storage.records[0] = [AsepriteCodec.encode(SpriteDocument.create(7, 8))];
    final repo = DraftRepository(storage);
    final old = await repo.load(0);
    await repo.save(id: 0, title: 'Migrated', document: old.document);
    expect((await repo.load(0)).document.width, 7);
  });
}
