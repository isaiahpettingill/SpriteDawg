import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/document_tabs.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/responsive_editor_shell.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(568, 320),
    const Size(800, 1024),
    const Size(1280, 800),
  ]) {
    testWidgets('Space-based editor shell $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ResponsiveEditorShell(
              mobileBody: Text('compact'),
              canvas: Text('canvas'),
              tools: Text('tools'),
              layers: Text('layers'),
              timeline: Text('timeline'),
              documentTabs: Text('documents'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('documents'), findsOneWidget);
      expect(
        find.text('canvas'),
        size.width >= 700 && size.height >= 500 ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('compact'),
        size.width >= 700 && size.height >= 500 ? findsNothing : findsOneWidget,
      );
    });
  }
  testWidgets('Dirty document close requires explicit discard', (tester) async {
    final calls = <String>[];
    final args = <Map<String, dynamic>?>[];
    final e = Editor(
      transport: (method, arguments) async {
        calls.add(method);
        args.add(arguments);
        return null;
      },
    );
    e.state = {
      'documents': [
        {'id': 1, 'title': 'Terrain', 'dirty': true, 'active': true},
        {'id': 2, 'title': 'NPC', 'dirty': false, 'active': false},
      ],
    };
    addTearDown(e.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 52,
            child: DocumentTabs(
              editor: e,
              onNew: () {},
              onOpen: () {},
              beforeSwitch: () async => true,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Close Terrain'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.tap(find.byTooltip('Close Terrain'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard and close'));
    await tester.pumpAndSettle();
    expect(calls, ['closeDocument']);
    expect(args.single, {'id': 1, 'discard': true, 'defaultUserData': ''});
  });
}
