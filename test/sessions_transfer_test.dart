import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/engine/document.dart';
import 'package:spritedawg/engine/aseprite.dart';
import 'package:spritedawg/engine/editor_sessions.dart';
import 'package:spritedawg/engine/tag_transfer.dart';
import 'package:spritedawg/platform/desktop_backend.dart';

SpriteDocument source() {
  final d = SpriteDocument.create(2, 1);
  d.frames = [
    Frame(
      duration: 75,
      cels: [
        Cel(0, 0, 2, 1, Uint32List.fromList([0xffff0000, 0xff0000ff])),
      ],
    ),
    Frame(
      duration: 125,
      cels: [
        Cel(0, 0, 0, 0, Uint32List(0), link: 0, data: UserData(text: 'linked')),
      ],
    ),
  ];
  d.tags = [
    Tag(
      1,
      1,
      'Tile variants',
      direction: 2,
      repeat: 3,
      color: Uint8List.fromList([1, 2, 3]),
      data: UserData(
        text: 'game:tile',
        color: 0xff123456,
        properties: Uint8List.fromList([8, 0, 0, 0, 0, 0, 0, 0]),
      ),
    ),
  ];
  return d;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'copy materializes links and preserves tag metadata and frame duration',
    () {
      final d = source(), before = AsepriteCodec.encode(source());
      final copy = copyTagSection(d, 0);
      expect(copy.frames.single.duration, 125);
      expect(copy.frames.single.cels.single!.link, isNull);
      expect(copy.frames.single.cels.single!.pixels, [0xffff0000, 0xff0000ff]);
      expect(copy.frames.single.cels.single!.data!.text, 'linked');
      expect(copy.tags.single.from, 0);
      expect(copy.tags.single.to, 0);
      expect(copy.tags.single.direction, 2);
      expect(copy.tags.single.repeat, 3);
      expect(copy.tags.single.data!.text, 'game:tile');
      expect(copy.tags.single.data!.properties, [8, 0, 0, 0, 0, 0, 0, 0]);
      expect(AsepriteCodec.encode(d), before);
    },
  );
  test(
    'cross-document paste is one undo and leaves source and clipboard independent',
    () {
      final s = EditorSessions();
      final original = s.add(source(), unsaved: true);
      s.copyTag(0);
      final dst = s.add(SpriteDocument.create(2, 1));
      s.pasteTag();
      expect(dst.engine.document.frames.length, 2);
      expect(dst.engine.document.tags.single.name, 'Tile variants');
      final encoded = dst.engine.encode();
      expect(AsepriteCodec.decode(encoded).tags.single.data!.text, 'game:tile');
      dst.engine.invoke('undo');
      expect(dst.engine.document.frames.length, 1);
      expect(dst.engine.document.tags, isEmpty);
      dst.engine.invoke('redo');
      expect(dst.engine.encode(), encoded);
      expect(original.engine.document.frames.length, 2);
      expect(original.engine.document.tags.single.from, 1);
      s.select(original.id);
      expect(s.active.engine.document.frames.length, 2);
    },
  );
  test('mismatch refusal is atomic and exact tag names are not rewritten', () {
    final s = EditorSessions();
    s.add(source());
    s.copyTag(0);
    final dst = s.add(SpriteDocument.create(3, 1));
    final before = dst.engine.encode();
    expect(() => s.pasteTag(), throwsFormatException);
    expect(dst.engine.encode(), before);
    expect(dst.engine.state()['canUndo'], false);
    final match = s.add(SpriteDocument.create(2, 1));
    s.pasteTag();
    s.pasteTag();
    expect(match.engine.document.tags.map((t) => t.name), [
      'Tile variants',
      'Tile variants',
    ]);
  });
  test(
    'indexed palettes and native indices remain per frame through paste',
    () {
      final d = source();
      d.depth = 8;
      d.transparentIndex = 0;
      d.frames[0].palette = [0, 0xffff0000, 0xff0000ff];
      d.frames[0].cels[0]!.pixels = Uint32List.fromList([1, 2]);
      d.frames[1].palette = [0, 0xff00ff00, 0xffffff00];
      final fragment = copyTagSection(d, 0);
      final target = SpriteDocument.create(2, 1)..depth = 8;
      target.frames[0].palette = [0, 0xff000000];
      pasteTagSection(target, 0, fragment);
      final roundtrip = AsepriteCodec.decode(AsepriteCodec.encode(target));
      expect(roundtrip.frames[1].cels[0]!.pixels, [1, 2]);
      expect(roundtrip.frames[1].palette, [0, 0xff00ff00, 0xffffff00]);
    },
  );
  test(
    'dirty document close requires explicit discard and keeps other history',
    () {
      final s = EditorSessions();
      final a = s.add(source(), unsaved: true);
      final b = s.add(SpriteDocument.create());
      expect(() => s.close(a.id), throwsFormatException);
      s.close(b.id);
      expect(s.active.id, a.id);
      s.close(a.id, discard: true);
      expect(s.documents, isEmpty);
    },
  );
  test(
    'multiple dirty documents recover separately and save remains per document',
    () async {
      final dir = await Directory.systemTemp.createTemp('spritedawg-sessions-');
      addTearDown(() => dir.delete(recursive: true));
      String? savePath;
      DesktopBackend backend() => DesktopBackend(
        openPath: () async => null,
        savePath: (_) async => savePath,
        supportDirectory: () async => dir,
      );
      final b = backend();
      await b.invoke('init', null);
      await b.invoke('new', {'width': 2, 'height': 1});
      final first = b.sessions.activeId;
      await b.invoke('stroke', {
        'tool': 'pencil',
        'points': [
          [0, 0],
        ],
        'color': 0xffff0000,
      });
      await b.invoke('new', {'width': 3, 'height': 1});
      final second = b.sessions.activeId;
      await b.invoke('stroke', {
        'tool': 'pencil',
        'points': [
          [0, 0],
        ],
        'color': 0xff0000ff,
      });
      await b.invoke('selectDocument', {'id': first});
      expect(b.engine.document.width, 2);
      expect(b.engine.state()['canUndo'], true);
      savePath = '${dir.path}/saved.aseprite';
      await b.invoke('save', null);
      await b.invoke('flushDrafts', null);
      expect(await File('${dir.path}/draft-$first.sdd').exists(), true);
      expect(await File('${dir.path}/draft-$second.sdd').exists(), true);
      await b.dispose();
      final reopened = backend();
      expect((await reopened.invoke('init', null))!['hasDocument'], true);
      expect(reopened.sessions.activeId, first);
      expect(reopened.engine.dirty, true);
      await reopened.invoke('selectDocument', {'id': second});
      expect(reopened.engine.document.width, 3);
      expect(reopened.engine.document.composite(0)[0], 0xff0000ff);
      expect(reopened.engine.dirty, true);
      await reopened.dispose();
    },
  );
  test(
    'paste as new keeps schema and destination links retain their targets',
    () {
      final s = EditorSessions();
      final origin = s.add(source());
      s.copyTag(0);
      s.pasteTagAsNew();
      expect(s.active.engine.document.width, 2);
      expect(s.active.title, 'Tile variants');
      expect(origin.engine.document.frames.length, 2);
      final target = source();
      final fragment = copyTagSection(source(), 0);
      pasteTagSection(target, -1, fragment);
      expect(target.frames[2].cels[0]!.link, 1);
      expect(target.resolved(2, 0)!.pixels, [0xffff0000, 0xff0000ff]);
    },
  );
  test('conflicting layer metadata refuses without dropping source data', () {
    final s = EditorSessions();
    s.add(source());
    s.copyTag(0);
    final target = SpriteDocument.create(2, 1);
    target.layers[0].data = UserData(text: 'different');
    final dst = s.add(target);
    final before = dst.engine.encode();
    expect(() => s.pasteTag(), throwsFormatException);
    expect(dst.engine.encode(), before);
  });
  test('aggregate memory refusal preserves documents and undo', () {
    final s = EditorSessions(residentBudget: 4096);
    final a = s.add(SpriteDocument.create(2, 1));
    final before = a.engine.encode();
    expect(
      () => a.engine.applyDocumentEdit(
        (d) => d.data = UserData(text: 'x' * 5000),
      ),
      throwsFormatException,
    );
    expect(a.engine.encode(), before);
    expect(a.engine.state()['canUndo'], false);
    final oversized = SpriteDocument.create(2, 1)
      ..data = UserData(text: 'x' * 5000);
    expect(() => s.add(oversized), throwsFormatException);
    expect(s.documents.length, 1);
    expect(s.active.id, a.id);
  });
  test(
    'many corrupt drafts remain individually visible without replacing work',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'spritedawg-recovery-cap-',
      );
      addTearDown(() => dir.delete(recursive: true));
      for (var i = 0; i < 9; i++) {
        await File('${dir.path}/recovery-$i.aseprite').writeAsBytes([0]);
      }
      final b = DesktopBackend(
        openPath: () async => null,
        savePath: (_) async => null,
        supportDirectory: () async => dir,
      );
      await b.invoke('init', null);
      expect(b.sessions.documents, isEmpty);
      await expectLater(
        b.invoke('recover', null),
        throwsA(predicate((e) => e.toString().contains('No readable draft'))),
      );
      expect(b.sessions.documents, isEmpty);
      expect((await b.invoke('listDrafts', null))!['drafts'], hasLength(9));
      expect(
        await dir.list().where((f) => f.path.endsWith('.aseprite')).length,
        9,
      );
      await b.dispose();
    },
  );
  test('recovery stages growing and shrinking documents atomically', () {
    final s = EditorSessions(residentBudget: 9000);
    final a = s.add(
      SpriteDocument.create(2, 1)..data = UserData(text: 'a' * 1000),
    );
    final b = s.add(
      SpriteDocument.create(2, 1)..data = UserData(text: 'b' * 2000),
    );
    final restored = s.restoreDecoded([
      MapEntry(
        a.id,
        SpriteDocument.create(2, 1)..data = UserData(text: 'a' * 2000),
      ),
      MapEntry(
        b.id,
        SpriteDocument.create(2, 1)..data = UserData(text: 'b' * 1000),
      ),
    ]);
    expect(restored[0].engine.document.data!.text!.length, 2000);
    expect(restored[1].engine.document.data!.text!.length, 1000);
    expect(s.active.id, b.id);
  });
  test('undo budget refusal does not consume the undo entry', () {
    final s = EditorSessions(residentBudget: 14000);
    final a = s.add(
      SpriteDocument.create(2, 1)..data = UserData(text: 'a' * 3000),
    );
    a.engine.applyDocumentEdit((d) => d.data = UserData(text: 'small'));
    final b = s.add(
      SpriteDocument.create(2, 1)..data = UserData(text: 'b' * 4000),
    );
    final before = a.engine.encode();
    expect(() => a.engine.invoke('undo'), throwsFormatException);
    expect(a.engine.encode(), before);
    expect(a.engine.state()['canUndo'], true);
    s.close(b.id);
    a.engine.invoke('undo');
    expect(a.engine.document.data!.text!.length, 3000);
  });
}
