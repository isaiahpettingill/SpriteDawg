import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/preset_color_editor.dart';

Future<void> openEditor(
  WidgetTester tester, {
  required List<int> colors,
  required List<String> names,
  required ValueChanged<PresetDraft?> onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => onResult(
              await showPresetColorEditor(
                context,
                name: 'Test palette',
                colors: colors,
                colorNames: names,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  test('Draft copies color and name lists into immutable snapshots', () {
    final colors = [0x80123456];
    final names = ['Water'];
    final draft = PresetDraft(name: 'Water', colors: colors, colorNames: names);
    colors[0] = 0;
    names[0] = 'Changed';
    expect(draft.colors, [0x80123456]);
    expect(draft.colorNames, ['Water']);
    expect(() => draft.colors.add(0), throwsUnsupportedError);
    expect(() => draft.colorNames.add(''), throwsUnsupportedError);
  });

  testWidgets('Cancel discards staged changes without mutating inputs', (
    tester,
  ) async {
    final colors = [0x80123456, 0xffabcdef];
    final names = ['Water', 'Stone'];
    var returned = false;
    PresetDraft? result;
    await openEditor(
      tester,
      colors: colors,
      names: names,
      onResult: (value) {
        returned = true;
        result = value;
      },
    );
    await tester.enterText(
      find.byKey(const Key('preset-edit-name')),
      'Changed',
    );
    await tester.ensureVisible(find.byTooltip('Remove color 1'));
    await tester.tap(find.byTooltip('Remove color 1'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('preset-edit-cancel')));
    await tester.tap(find.byKey(const Key('preset-edit-cancel')));
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    expect(result, isNull);
    expect(colors, [0x80123456, 0xffabcdef]);
    expect(names, ['Water', 'Stone']);
  });

  testWidgets('Save retains edited RGBA, names and reordered slots', (
    tester,
  ) async {
    PresetDraft? result;
    await openEditor(
      tester,
      colors: [0xff123456, 0xffabcdef],
      names: ['Water', 'Stone'],
      onResult: (value) => result = value,
    );
    await tester.enterText(
      find.byKey(const Key('preset-edit-name')),
      'My materials',
    );
    await tester.ensureVisible(find.byKey(const Key('preset-edit-color-0')));
    await tester.tap(find.byKey(const Key('preset-edit-color-0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('color-hex')), '40123456');
    await tester.ensureVisible(find.text('Use color'));
    await tester.tap(find.text('Use color'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Move color 1 down'));
    await tester.tap(find.byTooltip('Move color 1 down'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('preset-edit-save')));
    await tester.tap(find.byKey(const Key('preset-edit-save')));
    await tester.pumpAndSettle();
    expect(result?.name, 'My materials');
    expect(result?.colors, [0xffabcdef, 0x40123456]);
    expect(result?.colorNames, ['Stone', 'Water']);
  });

  testWidgets('A one-color palette cannot remove its final color', (
    tester,
  ) async {
    await openEditor(tester, colors: [0xff123456], names: [], onResult: (_) {});
    final remove = find.byKey(const Key('preset-edit-remove-0'));
    await tester.ensureVisible(remove);
    expect(tester.widget<IconButton>(remove).onPressed, isNull);
    await tester.ensureVisible(find.byKey(const Key('preset-edit-name')));
    await tester.enterText(find.byKey(const Key('preset-edit-name')), '   ');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('preset-edit-save')))
          .onPressed,
      isNull,
    );
  });
  testWidgets('Long Unicode swatch labels retain exact whitespace on Save', (
    tester,
  ) async {
    final label = '  ${List.filled(200, '水').join()}  ';
    PresetDraft? result;
    await openEditor(
      tester,
      colors: [0x40123456],
      names: [label],
      onResult: (value) => result = value,
    );
    await tester.tap(find.byKey(const Key('preset-edit-save')));
    await tester.pumpAndSettle();
    expect(result?.colorNames, [label]);
    expect(result?.colors, [0x40123456]);
  });
  testWidgets('Editor fits landscape while the keyboard is open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await openEditor(
      tester,
      colors: [0x40123456, 0xffabcdef],
      names: ['Water', 'Stone'],
      onResult: (_) {},
    );
    await tester.showKeyboard(find.byKey(const Key('preset-edit-name')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('preset-edit-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preset-edit-cancel')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
