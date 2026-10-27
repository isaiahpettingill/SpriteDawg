import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/palette_editor.dart';
import 'package:spritedawg/palette_presets.dart';
import 'package:spritedawg/engine/palette_presets.dart';

import 'palette_store_fake.dart';

void main() {
  late MemoryPaletteStore store;
  setUp(() => store = MemoryPaletteStore());

  testWidgets(
    'Save current snapshot, cancel, duplicate names, and reuse in another document',
    (tester) async {
      final edits = <Map<String, dynamic>>[];
      final state = <String, dynamic>{
        'palette': [0x8044aa22, 0xff112233],
        'paletteNames': ['Grass glaze', 'Stone'],
        'depth': 32,
      };
      final editor = Editor(
        transport: (method, args) async {
          if (method == 'edit') {
            edits.add(args!);
            state['palette'] = args['colors'];
            state['paletteNames'] = args['names'];
          }
          return state;
        },
      )..state = state;
      addTearDown(editor.dispose);
      Future<void> showEditor() => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaletteEditor(
              editor: editor,
              presetStore: store,
              onSelect: (_, _) {},
            ),
          ),
        ),
      );
      await showEditor();
      await tester.tap(find.byKey(const Key('save-palette-preset')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('preset-edit-cancel')));
      await tester.pumpAndSettle();
      expect(store.entries, isEmpty);
      expect(edits, isEmpty);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const Key('save-palette-preset')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('preset-edit-name')),
          'Terrain',
        );
        await tester.tap(find.byKey(const Key('preset-edit-save')));
        await tester.pumpAndSettle();
      }
      expect(store.entries.map((p) => p.name), ['Terrain', 'Terrain (2)']);
      expect(find.text('Terrain (2) saved to My palettes'), findsOneWidget);
      expect(store.entries.first.colors, [0x8044aa22, 0xff112233]);
      expect(store.entries.first.colorNames, ['Grass glaze', 'Stone']);
      expect(edits, isEmpty);
      state['palette'] = [0xffffffff];
      state['paletteNames'] = ['Other document'];
      await tester.pumpWidget(const SizedBox());
      await showEditor();
      await tester.tap(find.byKey(const Key('open-palette-presets')));
      await tester.pumpAndSettle();
      expect(find.text('My palettes'), findsOneWidget);
      await tester.tap(find.text('Terrain · 2'));
      await tester.pumpAndSettle();
      expect(edits.single['action'], 'palettePreset');
      expect(edits.single['colors'], [0x8044aa22, 0xff112233]);
      expect(edits.single['names'], ['Grass glaze', 'Stone']);
    },
  );

  testWidgets(
    'Personal edit/cancel and delete confirmation never edit a document',
    (tester) async {
      await store.save(
        name: 'Terrain',
        colors: [0x8044aa22, 0xff334455],
        colorNames: ['Grass', 'Stone'],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PalettePresetPicker(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Terrain options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit preset…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('preset-edit-name')),
        'Discard me',
      );
      await tester.tap(find.byKey(const Key('preset-edit-cancel')));
      await tester.pumpAndSettle();
      expect(store.entries.single.name, 'Terrain');
      await tester.tap(find.byTooltip('Terrain options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit preset…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('preset-edit-name')),
        'Renamed',
      );
      await tester.tap(find.byKey(const Key('preset-edit-save')));
      await tester.pumpAndSettle();
      expect(store.entries.single.name, 'Renamed');
      expect(store.entries.single.colors, [0x8044aa22, 0xff334455]);
      for (final accept in [false, true]) {
        await tester.tap(find.byTooltip('Renamed options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete preset…'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(accept ? 'Delete' : 'Cancel'));
        await tester.pumpAndSettle();
        expect(store.entries.length, accept ? 0 : 1);
      }
    },
  );

  testWidgets(
    'Built-in save copy is isolated and write failures stay visible',
    (tester) async {
      final builtin = palettePresets.first;
      final before = List<int>.of(builtin.colors);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PalettePresetPicker(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('palette-preset-search')),
        builtin.name,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('${builtin.name} options'));
      await tester.pumpAndSettle();
      expect(find.text('Edit preset…'), findsNothing);
      expect(find.text('Delete preset…'), findsNothing);
      await tester.tap(find.text('Save a copy…'));
      await tester.pumpAndSettle();
      store.failSave = true;
      await tester.tap(find.byKey(const Key('preset-edit-save')));
      await tester.pumpAndSettle();
      expect(store.entries, isEmpty);
      expect(find.textContaining('Could not save My palettes'), findsOneWidget);
      expect(builtin.colors, before);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Credits and descriptions live in optional Details, not the picker',
    (tester) async {
      final builtin = palettePresets.first;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PalettePresetPicker(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('palette-preset-search')),
        builtin.name,
      );
      await tester.pumpAndSettle();
      expect(find.text(builtin.description), findsNothing);
      expect(find.text(builtin.credit), findsNothing);
      await tester.tap(find.byTooltip('${builtin.name} options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text(builtin.description), findsOneWidget);
      expect(find.text(builtin.credit), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text(builtin.description), findsNothing);
      expect(find.byType(PalettePresetPicker), findsOneWidget);
      expect(store.entries, isEmpty);
    },
  );
}
