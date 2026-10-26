import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/palette_editor.dart';
import 'package:spritedawg/main.dart';
import 'package:spritedawg/color_picker.dart';
import 'editor_test.dart' as fixture;

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(568, 320),
    const Size(1024, 768),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Compact palette at $size, text $scale', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final e = Editor(transport: (_, _) async => null)
          ..state = {
            'palette': List.generate(12, (i) => 0xff000000 | i * 0x142017),
            'depth': 32,
          };
        addTearDown(e.dispose);
        await tester.pumpWidget(
          MaterialApp(
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: PaletteEditor(
                  editor: e,
                  currentColor: () => 0x80ff0000,
                  onSelect: (_, _) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Apply swatch'), findsNothing);
        expect(find.text('Color · AARRGGBB'), findsNothing);
        expect(
          tester.getSize(find.byKey(const Key('palette-content'))).height,
          lessThanOrEqualTo(560),
        );
        await tester.ensureVisible(find.text('Edit selected color'));
        await tester.tap(find.text('Edit selected color'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('color-hex')));
        await tester.showKeyboard(find.byKey(const Key('color-hex')));
        tester.view.viewInsets = const FakeViewPadding(bottom: 100);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'Add current RGBA preserves alpha, ignores staged swatch and deduplicates',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      final state = <String, dynamic>{
        'palette': [0xff000000, 0xffffffff],
        'depth': 32,
      };
      final e = Editor(
        transport: (method, args) async {
          if (method == 'edit') {
            calls.add(args!);
            if (args['action'] == 'paletteAdd') {
              state['palette'] = [...state['palette'] as List, args['color']];
            }
          }
          return state;
        },
      )..state = state;
      addTearDown(e.dispose);
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaletteEditor(
              editor: e,
              currentColor: () => 0x8044aa88,
              onSelect: (_, i) => selected = i,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Add current color'));
      await tester.pumpAndSettle();
      expect(calls.single, {
        'action': 'paletteAdd',
        'color': 0x8044aa88,
        'name': '',
      });
      expect(selected, 2);
      await tester.tap(find.text('Add current color'));
      await tester.pumpAndSettle();
      expect(calls.length, 1);
      expect(
        find.text('Already in palette · swatch 3 selected'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Indexed duplicates retain explicit index, opaque avoids transparent slot',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      int? explicit = 2;
      int? selected;
      final state = <String, dynamic>{
        'palette': [0xff000000, 0xffffffff, 0xffffffff],
        'depth': 8,
        'transparentIndex': 0,
      };
      var color = 0xffffffff;
      final e = Editor(
        transport: (m, a) async {
          if (m == 'edit') {
            calls.add(a!);
            state['palette'] = [...state['palette'] as List, a['color']];
          }
          return state;
        },
      )..state = state;
      addTearDown(e.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaletteEditor(
              editor: e,
              currentColor: () => color,
              currentPaletteIndex: () => explicit,
              onSelect: (_, i) => selected = i,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Add current color'));
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(calls, isEmpty);
      color = 0xff000000;
      explicit = null;
      await tester.tap(find.text('Add current color'));
      await tester.pumpAndSettle();
      expect(selected, 3);
      expect(calls.single['color'], 0xff000000);
    },
  );

  testWidgets(
    'Full palette gives safe error and existing color still selects',
    (tester) async {
      final state = <String, dynamic>{
        'palette': List.generate(256, (i) => 0xff000000 | i),
        'depth': 8,
        'transparentIndex': 0,
      };
      var color = 0xffff0000;
      final e = Editor(
        transport: (m, a) async {
          if (m == 'edit') throw Exception('Palette is full (256 entries)');
          return state;
        },
      )..state = state;
      addTearDown(e.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaletteEditor(
              editor: e,
              currentColor: () => color,
              onSelect: (_, _) {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('Add current color'));
      await tester.pumpAndSettle();
      expect(e.palette.length, 256);
      expect(e.error, contains('Palette is full'));
      color = 0xff000002;
      await tester.tap(find.text('Add current color'));
      await tester.pumpAndSettle();
      expect(
        find.text('Already in palette · swatch 3 selected'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Visual edit cancels safely and applies only chosen selected color',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      final state = <String, dynamic>{
        'palette': [0xff000000, 0xffffffff],
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
      await tester.tap(find.text('Edit selected color'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.byTooltip('Swatch 2 · #ffffffff'));
      await tester.tap(find.text('Edit selected color'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('color-hex')), '8044AA88');
      await tester.tap(find.text('Use color'));
      await tester.pumpAndSettle();
      expect(calls.single, {
        'action': 'paletteEdit',
        'index': 1,
        'color': 0x8044aa88,
        'name': '',
      });
    },
  );

  testWidgets(
    'Brush opener differs from eyedropper at phone and desktop sizes',
    (tester) async {
      for (final size in [const Size(390, 844), const Size(1280, 900)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final e = Editor(transport: (_, _) async => fixture.state());
        await tester.pumpWidget(MaterialApp(home: EditorScreen(editor: e)));
        await tester.pumpAndSettle();
        final opener = find.byTooltip('Brush color');
        expect(opener, findsOneWidget);
        expect(
          find.descendant(of: opener, matching: find.byType(BrushColorSwatch)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: opener, matching: find.byIcon(Icons.colorize)),
          findsNothing,
        );
        await tester.tap(opener);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('color-hex')), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets('Capture cleaned phone palette', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final e = Editor(transport: (_, _) async => null)
      ..state = {
        'palette': [
          0xff000000,
          0xffffffff,
          0xff999999,
          0xffe53935,
          0xffff9800,
          0xffffeb3b,
          0xff66bb6a,
          0xff26c6da,
          0xff42a5f5,
          0xff7e57c2,
          0xffec407a,
          0xff795548,
        ],
        'depth': 32,
      };
    addTearDown(e.dispose);
    await tester.runAsync(() async {
      const fontPath = String.fromEnvironment('CAPTURE_FONT');
      if (fontPath.isNotEmpty) {
        await (FontLoader('Roboto')..addFont(
              Future.value(
                ByteData.sublistView(await File(fontPath).readAsBytes()),
              ),
            ))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      }
    });
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            body: Center(
              child: PaletteEditor(
                editor: e,
                currentColor: () => 0x80ff0000,
                onSelect: (_, _) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/ui').create(recursive: true);
      await File(
        'build/ui/palette-clean-phone.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
