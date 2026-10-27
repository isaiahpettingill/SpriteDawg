import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/engine/aseprite.dart';
import 'package:spritedawg/engine/default_user_data.dart';
import 'package:spritedawg/engine/document.dart';
import 'package:spritedawg/engine/editor_engine.dart';
import 'package:spritedawg/engine/editor_sessions.dart';

const raw =
    '  credits="Artist ✨"\nlicense="CC BY 4.0"\ntitle="My title"\nother raw: { }\n';
void main() {
  test('raw defaults on new sprites roundtrip, never change title', () {
    final sessions = EditorSessions();
    for (var i = 0; i < 2; i++) {
      final session = sessions.add(newSprite(16, 24, raw), unsaved: true);
      expect(AsepriteCodec.decode(session.engine.encode()).data!.text, raw);
      expect(session.title.startsWith('Untitled'), true);
      expect(session.engine.state()['canUndo'], false);
    }
    final e = EditorEngine();
    e.invoke('new', {'defaultUserData': raw});
    expect(e.document.data!.text, raw);
    expect(newSprite(4, 4, '').data, isNull);
  });
  test(
    'placeholder only, preserves imported, edited, recovery and existing metadata',
    () {
      final s = EditorSessions();
      s.initializePlaceholder(raw);
      expect(s.active.engine.document.data!.text, raw);
      expect(s.active.engine.dirty, false);
      s.initializePlaceholder('replacement');
      expect(s.active.engine.document.data!.text, raw);
      s.add(SpriteDocument.create()..data = UserData(text: 'imported'));
      s.initializePlaceholder(raw);
      expect(s.active.engine.document.data!.text, 'imported');
      s.add(SpriteDocument.create());
      s.initializePlaceholder(raw);
      expect(s.active.engine.document.data, isNull);
      final recovery = EditorSessions();
      recovery.active.engine.recoveryAvailable = true;
      recovery.initializePlaceholder(raw);
      expect(recovery.active.engine.document.data, isNull);
      final edited = EditorSessions();
      edited.active.engine.dirty = true;
      edited.initializePlaceholder(raw);
      expect(edited.active.engine.document.data, isNull);
      s.close(s.activeId);
      s.close(s.activeId);
      s.initializePlaceholder(raw);
      expect(s.active.engine.document.data!.text, raw);
    },
  );
  test('UTF8 limit validates before replacing a document', () {
    expect(defaultUserData({'defaultUserData': 'a' * 65535}).length, 65535);
    expect(() => newSprite(8, 8, 'é' * 32768), throwsFormatException);
    final e = EditorEngine();
    final before = e.encode();
    expect(
      () => e.invoke('new', {'defaultUserData': 12}),
      throwsFormatException,
    );
    expect(e.encode(), before);
  });
  test('explicit apply preserves color/properties and is one undo', () {
    final e = EditorEngine();
    e.document.data = UserData(
      text: 'original',
      color: 0xff123456,
      properties: Uint8List.fromList([0, 0, 0, 0]),
    );
    final before = e.encode();
    e.edit({'action': 'userData', 'target': 'sprite', 'text': raw});
    expect(e.document.data!.text, raw);
    expect(e.document.data!.color, 0xff123456);
    expect(e.document.data!.properties, [0, 0, 0, 0]);
    e.invoke('undo');
    expect(e.encode(), before);
  });
}
