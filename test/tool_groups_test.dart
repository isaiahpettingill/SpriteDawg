import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/main.dart';
import 'package:spritedawg/pixel_canvas.dart';
import 'package:spritedawg/tool_groups.dart';
import 'editor_test.dart' as fixture;

void main() {
  testWidgets(
    'Hold picks subtool without choosing previous tool; groups remember',
    (t) async {
      final calls = <String>[];
      final editor = Editor(
        transport: (method, args) async {
          calls.add(method);
          return fixture.state();
        },
      );
      await t.pumpWidget(PocketPixelApp(editor: editor));
      await t.pumpAndSettle();
      await t.longPress(find.byKey(const Key('tool-group-ink')));
      await t.pumpAndSettle();
      expect(find.text('Airbrush'), findsOneWidget);
      await t.tap(find.text('Airbrush'));
      await t.pumpAndSettle();
      expect(t.widget<PixelCanvas>(find.byType(PixelCanvas)).tool, 'airbrush');
      await t.tap(find.byKey(const Key('tool-group-eraser')));
      await t.pump();
      await t.tap(find.byKey(const Key('tool-group-ink')));
      await t.pump();
      expect(t.widget<PixelCanvas>(find.byType(PixelCanvas)).tool, 'airbrush');
      expect(calls.where((v) => v == 'stroke'), isEmpty);
      await t.longPress(find.byKey(const Key('tool-group-shape')));
      await t.pumpAndSettle();
      await t.tap(find.text('Filled ellipse'));
      await t.pumpAndSettle();
      final canvas = t.widget<PixelCanvas>(find.byType(PixelCanvas));
      expect(canvas.tool, 'ellipse');
      expect(canvas.filled, isTrue);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Gradient is a fill subtool and exposes two-color drag instructions',
    (t) async {
      final editor = Editor(transport: (_, _) async => fixture.state());
      await t.pumpWidget(PocketPixelApp(editor: editor));
      await t.pumpAndSettle();
      await t.longPress(find.byKey(const Key('tool-group-fill')));
      await t.pumpAndSettle();
      await t.tap(find.text('Gradient'));
      await t.pumpAndSettle();
      expect(t.widget<PixelCanvas>(find.byType(PixelCanvas)).tool, 'gradient');
      expect(find.text('End'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Right-click opens choices and dismiss does not select', (
    t,
  ) async {
    final selected = <String>[];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawingToolGroupButton(
            group: 'fill',
            current: 'fill',
            active: true,
            onSelected: selected.add,
          ),
        ),
      ),
    );
    final mouse = await t.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.down(t.getCenter(find.byKey(const Key('tool-group-fill'))));
    await mouse.up();
    await t.pumpAndSettle();
    expect(find.text('Gradient'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(selected, isEmpty);
  });
  testWidgets(
    'Filled option persists when leaving and returning to shape group',
    (t) async {
      final editor = Editor(transport: (_, _) async => fixture.state());
      await t.pumpWidget(PocketPixelApp(editor: editor));
      await t.pumpAndSettle();
      await t.longPress(find.byKey(const Key('tool-group-shape')));
      await t.pumpAndSettle();
      await t.tap(find.text('Rectangle'));
      await t.pumpAndSettle();
      await t.tap(find.text('Outline'));
      await t.pump();
      await t.tap(find.byKey(const Key('tool-group-eraser')));
      await t.pump();
      await t.tap(find.byKey(const Key('tool-group-shape')));
      await t.pump();
      expect(t.widget<PixelCanvas>(find.byType(PixelCanvas)).filled, isTrue);
    },
  );
  testWidgets('Menu key opens choices on focused button', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawingToolGroupButton(
            group: 'fill',
            current: 'fill',
            active: true,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await t.pumpAndSettle();
    expect(find.text('Gradient'), findsOneWidget);
  });
  for (final width in [320.0, 360.0, 768.0, 1280.0]) {
    testWidgets(
      'All seven group controls reachable without toolbar scroll at $width',
      (t) async {
        t.view.physicalSize = Size(width, 800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final editor = Editor(transport: (_, _) async => fixture.state());
        await t.pumpWidget(PocketPixelApp(editor: editor));
        await t.pumpAndSettle();
        for (final key in drawingToolGroups.keys) {
          final finder = find.byKey(Key('tool-group-$key'));
          expect(finder.hitTestable(), findsOneWidget);
          expect(t.getSize(finder).width, greaterThanOrEqualTo(48));
          expect(t.getSize(finder).height, greaterThanOrEqualTo(48));
        }
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
