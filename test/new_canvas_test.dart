import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/main.dart';

void main() {
  testWidgets('empty startup, cancel, validation and remembered dimensions', (
    tester,
  ) async {
    final creations = <Map<String, dynamic>>[];
    var lastWidth = 16, lastHeight = 24;
    final editor = Editor(
      transport: (method, args) async {
        if (method == 'new') {
          creations.add(args!);
          lastWidth = args['width'] as int;
          lastHeight = args['height'] as int;
        }
        return {
          'hasDocument': false,
          'documents': [],
          'width': 0,
          'height': 0,
          'lastNewWidth': lastWidth,
          'lastNewHeight': lastHeight,
          'recoveryAvailable': false,
        };
      },
    );
    await tester.pumpWidget(PocketPixelApp(editor: editor));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('empty-workspace')), findsOneWidget);
    expect(find.text('No canvas open'), findsOneWidget);
    expect(creations, isEmpty);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.save_outlined),
          )
          .onPressed,
      isNull,
    );

    Future<void> openDialog() async {
      await tester.tap(find.text('New canvas'));
      await tester.pumpAndSettle();
    }

    final width = find.byKey(const Key('new-canvas-width'));
    final height = find.byKey(const Key('new-canvas-height'));
    String value(Finder field) =>
        tester.widget<TextFormField>(field).controller!.text;

    await openDialog();
    expect(value(width), '16');
    expect(value(height), '24');
    await tester.enterText(width, '123');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(creations, isEmpty);
    expect(find.byKey(const Key('empty-workspace')), findsOneWidget);
    await openDialog();
    expect(value(width), '16');
    for (final invalid in ['', '0', '-1', '2049', '16x16', '1.5']) {
      await tester.enterText(width, invalid);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.text('Enter 1–2048 pixels'), findsOneWidget);
      expect(creations, isEmpty);
    }
    await tester.enterText(width, '48');
    await tester.enterText(height, '0');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Enter 1–2048 pixels'), findsOneWidget);
    expect(creations, isEmpty);
    await tester.enterText(height, '32');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(creations.single['width'], 48);
    expect(creations.single['height'], 32);
    await openDialog();
    expect(value(width), '48');
    expect(value(height), '32');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
