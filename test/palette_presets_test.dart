import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/palette_editor.dart';
import 'package:spritedawg/palette_presets.dart';
import 'package:spritedawg/engine/palette_presets.dart';

void main() {
  test('Presets have stable identities, opaque colors and attribution', () {
    expect(palettePresets.length, greaterThanOrEqualTo(6));
    expect(
      palettePresets.map((p) => p.id).toSet().length,
      palettePresets.length,
    );
    for (final p in palettePresets) {
      expect(p.name, isNotEmpty);
      expect(p.credit, isNotEmpty);
      expect(p.description, isNotEmpty);
      expect(p.colors.length, inInclusiveRange(1, 255));
      expect(p.colors.every((c) => c >= 0xff000000 && c <= 0xffffffff), isTrue);
    }
  });

  for (final size in [
    const Size(320, 568),
    const Size(568, 320),
    const Size(1024, 768),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Preset library fits $size at text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const Scaffold(body: PalettePresetPicker()),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.enterText(
          find.byKey(const Key('palette-preset-search')),
          'pico',
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('PICO-8'), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('palette-preset-search')),
          'no such palette',
        );
        await tester.pumpAndSettle();
        expect(find.text('No matching palettes'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'Landscape keyboard keeps preset search usable at scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(568, 320);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        PalettePreset? selected;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    selected = await showPalettePresets(context);
                  },
                  child: const Text('Open presets'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open presets'));
        await tester.pumpAndSettle();
        final field = find.byKey(const Key('palette-preset-search'));
        await tester.showKeyboard(field);
        final editable = find.descendant(
          of: field,
          matching: find.byType(EditableText),
        );
        final focus = tester.widget<EditableText>(editable).focusNode;
        tester.view.viewInsets = const FakeViewPadding(bottom: 200);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(focus.hasFocus, isTrue);

        // Send input through the existing keyboard connection, rather than
        // enterText(), which would refocus the field and hide focus regressions.
        for (final query in ['pico', 'no such palette', 'pico']) {
          tester.testTextInput.enterText(query);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(tester.widget<EditableText>(editable).focusNode, same(focus));
          expect(focus.hasFocus, isTrue);
          expect(
            find.text(query == 'pico' ? 'PICO-8 · 16' : 'No matching palettes'),
            findsOneWidget,
          );
        }
        final result = find.text('PICO-8 · 16');
        await tester.ensureVisible(result);
        await tester.pumpAndSettle();
        await tester.tap(result);
        await tester.pumpAndSettle();
        expect(selected?.id, 'pico-8');
        expect(find.byType(PalettePresetPicker), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Browsing and closing presets never edits custom palette', (
    tester,
  ) async {
    final calls = <Map<String, dynamic>>[];
    final state = <String, dynamic>{
      'palette': [0xff123456],
      'depth': 32,
    };
    final e = Editor(
      transport: (m, a) async {
        if (m == 'edit') calls.add(a!);
        return state;
      },
    )..state = state;
    addTearDown(e.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaletteEditor(editor: e, onSelect: (_, _) {}),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-palette-presets')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close presets'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(e.palette, [0xff123456]);
  });

  testWidgets(
    'Preset application uses one edit and indexed changes require confirmation',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      final state = <String, dynamic>{
        'palette': [0xff123456],
        'depth': 8,
      };
      final e = Editor(
        transport: (m, a) async {
          if (m == 'edit') {
            calls.add(a!);
            state['palette'] = a['colors'];
          }
          return state;
        },
      )..state = state;
      addTearDown(e.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaletteEditor(editor: e, onSelect: (_, _) {}),
          ),
        ),
      );
      Future<void> choose() async {
        await tester.tap(find.byKey(const Key('open-palette-presets')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('palette-preset-search')),
          'pico',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('PICO-8'));
        await tester.pumpAndSettle();
      }

      await choose();
      expect(calls, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(e.palette, [0xff123456]);
      await choose();
      await tester.tap(find.text('Remap colors'));
      await tester.pumpAndSettle();
      expect(calls.length, 1);
      expect(calls.single['action'], 'palettePreset');
      expect(calls.single['remap'], isTrue);
      expect((calls.single['colors'] as List).length, 16);
    },
  );
  testWidgets(
    'Failed preset keeps selected swatch and RGBA needs no remap prompt',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      var reject = true;
      final state = <String, dynamic>{
        'palette': [0xff123456, 0xffabcdef],
        'depth': 32,
      };
      final e = Editor(
        transport: (m, a) async {
          if (m == 'edit') {
            calls.add(a!);
            if (reject) throw Exception('Recovery storage unavailable');
            state['palette'] = a['colors'];
          }
          return state;
        },
      )..state = state;
      addTearDown(e.dispose);
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaletteEditor(editor: e, onSelect: (_, i) => selected = i),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Swatch 2 · #ffabcdef'));
      Future<void> choose() async {
        await tester.tap(find.byKey(const Key('open-palette-presets')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('palette-preset-search')),
          'pico',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('PICO-8'));
        await tester.pumpAndSettle();
      }

      await choose();
      expect(e.palette, [0xff123456, 0xffabcdef]);
      expect(selected, 1);
      expect(find.text('Swatch 2'), findsOneWidget);
      reject = false;
      await choose();
      expect(find.text('Remap colors'), findsNothing);
      expect(calls.last['remap'], isFalse);
      expect(selected, 0);
      expect(e.palette.length, 16);
    },
  );
}
