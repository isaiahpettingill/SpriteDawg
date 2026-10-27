import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/export_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('export owns busy guard and leaves document state untouched', () async {
    final gate = Completer<Map<String, dynamic>?>();
    final calls = <String>[];
    final editor = Editor(
      transport: (method, args) async {
        calls.add(method);
        if (method == 'exportSnapshot') return {'width': 1};
        if (method == 'saveExport') return {'saved': true};
        return null;
      },
    );
    editor.state = {'dirty': true, 'frame': 2, 'canUndo': true};
    final original = Map<String, dynamic>.of(editor.state);
    final operation = editor.exportMedia({
      'scope': 'current',
    }, (_) => gate.future);
    expect(editor.busy, true);
    expect(await editor.exportMedia({}, (_) async => {}), false);
    gate.complete({'files': {}});
    expect(await operation, true);
    expect(editor.busy, false);
    expect(editor.state, original);
    expect(calls, ['exportSnapshot', 'saveExport']);
    editor.dispose();
  });
  test('cancel and encode failure never invoke storage', () async {
    final calls = <String>[];
    final editor = Editor(
      transport: (m, a) async {
        calls.add(m);
        return {};
      },
    );
    expect(await editor.exportMedia({}, (_) async => null), false);
    expect(editor.error, isNull);
    expect(
      await editor.exportMedia(
        {},
        (_) async => throw PlatformException(
          code: 'encoder',
          message: 'Codec unavailable',
        ),
      ),
      false,
    );
    expect(editor.error, 'Codec unavailable');
    expect(editor.busy, false);
    expect(calls, ['exportSnapshot', 'exportSnapshot']);
    editor.dispose();
  });
  testWidgets(
    'compact export dialog exposes formats without explanatory wall',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var calls = 0;
      final editor = Editor(
        transport: (_, _) async {
          calls++;
          return {};
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showExportDialog(context, editor),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Export'), findsWidgets);
      expect(find.text('PNG'), findsOneWidget);
      expect(find.textContaining('GIF uses'), findsNothing);
      await tester.tap(find.text('PNG'));
      await tester.pumpAndSettle();
      expect(find.text('QOI'), findsWidgets);
      expect(find.text('AVIF (lossy)'), findsWidgets);
      expect(find.text('Spritesheet + JSON'), findsWidgets);
      await tester.tap(find.text('QOI').last);
      await tester.pumpAndSettle();
      expect(find.text('Frames'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(tester.takeException(), isNull);
      editor.dispose();
    },
  );
  testWidgets('small canvas disables unsupported AVIF before encoding', (
    tester,
  ) async {
    final editor = Editor(transport: (_, _) async => {})
      ..state = {'width': 8, 'height': 8};
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showExportDialog(context, editor),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final dropdown = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>).first,
    );
    expect(
      dropdown.items!.singleWhere((item) => item.value == 'avif').enabled,
      false,
    );
    expect(
      dropdown.items!.singleWhere((item) => item.value == 'qoi').enabled,
      true,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    editor.dispose();
  });
}
