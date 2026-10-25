import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/palette_editor.dart';

void main() {
  for (final size in [const Size(320, 568), const Size(568, 320)]) {
    testWidgets('Palette stays usable at $size with keyboard', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final e = Editor(transport: (_, _) async => null);
      e.state = {
        'palette': [0xff000000, 0xffffffff],
        'paletteNames': ['Black', 'White'],
        'depth': 8,
        'transparentIndex': 0,
      };
      addTearDown(e.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaletteEditor(editor: e, onSelect: (_, _) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(TextField).first);
      await tester.tap(find.byType(TextField).first);
      tester.view.viewInsets = const FakeViewPadding(bottom: 140);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Palette uses exact index and explicit edit transaction', (
    tester,
  ) async {
    final calls = <Map<String, dynamic>>[];
    final state = <String, dynamic>{
      'palette': [0xff000000, 0xff000000],
      'paletteNames': ['', 'Duplicate'],
      'depth': 8,
      'transparentIndex': 0,
    };
    final e = Editor(
      transport: (method, args) async {
        if (method == 'edit') calls.add(args!);
        return state;
      },
    );
    e.state = state;
    addTearDown(e.dispose);
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaletteEditor(
            editor: e,
            onSelect: (_, index) => selected = index,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Swatch 2 · #ff000000'));
    expect(selected, 1);
    await tester.enterText(find.byType(TextField).first, '8044AA88');
    await tester.enterText(find.byType(TextField).last, 'Variant shade');
    await tester.ensureVisible(find.text('Apply swatch'));
    await tester.tap(find.text('Apply swatch'));
    await tester.pumpAndSettle();
    expect(calls.single, {
      'action': 'paletteEdit',
      'index': 1,
      'color': 0x8044aa88,
      'name': 'Variant shade',
    });
    expect(tester.takeException(), isNull);
  });
}
