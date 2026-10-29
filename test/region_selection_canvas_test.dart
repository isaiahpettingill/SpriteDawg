import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/engine/editor_engine.dart';
import 'package:spritedawg/pixel_canvas.dart';

void main() {
  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('Select, move, copy/cut/paste/delete and undo: $kind', (t) async {
      final engine = EditorEngine();
      engine.invoke('new', {'width': 8, 'height': 8});
      engine.document.editable(0, 0).pixels[3 * 8 + 3] = 0xff123456;
      final editor = Editor(transport: (method, args) async => engine.invoke(method, args ?? {}));
      await editor.call('state');
      await t.pumpWidget(MaterialApp(home: Scaffold(body: PixelCanvas(
        editor: editor, tool: 'selectRegion', color: 0, brush: 1,
        grid: false, onion: false, fitToken: 0, onPick: (_) {},
        onStroke: (_, _) => fail('Selection must never paint'),
      ))));
      final center = t.getCenter(find.byKey(const Key('pixel-canvas')));
      // 8x8 fits at the 24px cap; choose source pixel (3,3).
      final source = center - const Offset(12, 12);
      final select = await t.startGesture(source, kind: kind);
      await select.up(); await t.pump();
      expect(t.widget<IconButton>(find.byKey(const Key('selection-copy'))).onPressed, isNotNull);
      final move = await t.startGesture(source, kind: kind);
      await move.moveBy(const Offset(24, 0)); await move.up(); await t.pumpAndSettle();
      expect(engine.document.resolved(0, 0)!.pixels[3 * 8 + 4], 0xff123456);
      expect(engine.document.resolved(0, 0)!.pixels[3 * 8 + 3], 0);
      await t.tap(find.byKey(const Key('selection-copy'))); await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('selection-cut'))); await t.pumpAndSettle();
      expect(engine.document.resolved(0, 0)!.pixels[3 * 8 + 4], 0);
      await t.tap(find.byKey(const Key('selection-paste'))); await t.pumpAndSettle();
      expect(engine.document.resolved(0, 0)!.pixels[0], 0xff123456);
      await t.tap(find.byKey(const Key('selection-delete'))); await t.pumpAndSettle();
      expect(engine.document.resolved(0, 0)!.pixels[0], 0);
      await editor.call('undo'); await t.pumpAndSettle();
      expect(engine.document.resolved(0, 0)!.pixels[0], 0xff123456);
      expect(t.widget<IconButton>(find.byKey(const Key('selection-delete'))).onPressed, isNull);
      await t.pumpWidget(const SizedBox()); editor.dispose();
    });
  }
  testWidgets('cancel, second finger, Escape and frame change do not commit a move', (t) async {
    final engine = EditorEngine(); engine.invoke('new', {'width': 8, 'height': 8});
    engine.document.editable(0, 0).pixels[27] = 0xff123456;
    final editor = Editor(transport: (method, args) async => engine.invoke(method, args ?? {}));
    await editor.call('state');
    await t.pumpWidget(MaterialApp(home: Scaffold(body: PixelCanvas(
      editor: editor, tool: 'selectRegion', color: 0, brush: 1,
      grid: false, onion: false, fitToken: 0, onPick: (_) {}, onStroke: (_, _) => fail('No stroke'),
    ))));
    final source = t.getCenter(find.byKey(const Key('pixel-canvas'))) - const Offset(12, 12);
    final select = await t.startGesture(source); await select.up(); await t.pump();
    final move = await t.startGesture(source); await move.moveBy(const Offset(24, 0));
    await move.cancel(); await t.pump();
    expect(engine.document.resolved(0, 0)!.pixels[27], 0xff123456);
    final first = await t.startGesture(source, pointer: 1);
    await first.moveBy(const Offset(24, 0));
    final second = await t.startGesture(source + const Offset(40, 40), pointer: 2);
    await second.up(); await first.up(); await t.pump();
    expect(engine.state()['canUndo'], false);
    await t.sendKeyEvent(LogicalKeyboardKey.escape); await t.pump();
    expect(t.widget<IconButton>(find.byKey(const Key('selection-copy'))).onPressed, isNull);
    final again = await t.startGesture(source); await again.up(); await t.pump();
    await editor.call('select', {'layer': 0}); await t.pump();
    expect(t.widget<IconButton>(find.byKey(const Key('selection-copy'))).onPressed, isNull);
    await t.pumpWidget(const SizedBox()); editor.dispose();
  });
}
