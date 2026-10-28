import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/main.dart';
import 'package:spritedawg/pixel_canvas.dart';
import 'editor_test.dart' as fixture;

void main() {
  for (final entry in {
    'phone320': const Size(320, 568),
    'phone390': const Size(390, 844),
    'tablet': const Size(768, 1024),
    'desktop': const Size(1440, 900),
  }.entries) {
    testWidgets('${entry.key}: two swatch rows and compact mirroring', (
      t,
    ) async {
      t.view.physicalSize = entry.value;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final calls = <(String, Map<String, dynamic>?)>[];
      final palette = List.generate(
        64,
        (i) => HSLColor.fromAHSL(
          1,
          (i * 47 % 360).toDouble(),
          .65,
          .30 + (i % 4) * .15,
        ).toColor().toARGB32(),
      );
      // Duplicate palette entries must still select the exact tapped index.
      palette[1] = palette[0];
      final editor = Editor(
        transport: (method, args) async {
          calls.add((method, args));
          return {...fixture.state(), 'depth': 8, 'palette': palette};
        },
      );
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await t.runAsync(() async {
          const fontPath = String.fromEnvironment('CAPTURE_FONT');
          if (fontPath.isNotEmpty) {
            await (FontLoader('Roboto')..addFont(
                  File(fontPath).readAsBytes().then(ByteData.sublistView),
                ))
                .load();
            await (FontLoader('MaterialIcons')
                  ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
                .load();
          }
        });
      }
      final boundaryKey = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: PocketPixelApp(editor: editor),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Mirror X'), findsNothing);
      expect(find.text('Mirror Y'), findsNothing);
      expect(
        find.byKey(const Key('mirroring-menu')).hitTestable(),
        findsOneWidget,
      );
      final first = find.byKey(const Key('palette-color-0'));
      final second = find.byKey(const Key('palette-color-1'));
      final third = find.byKey(const Key('palette-color-2'));
      for (final swatch in [first, second, third]) {
        expect(swatch.hitTestable(), findsOneWidget);
        expect(t.getSize(swatch).width, greaterThanOrEqualTo(44));
        expect(t.getSize(swatch).height, greaterThanOrEqualTo(44));
      }
      expect(t.getTopLeft(first).dx, t.getTopLeft(second).dx);
      expect(t.getTopLeft(second).dy, greaterThan(t.getTopLeft(first).dy));
      expect(t.getTopLeft(third).dx, greaterThan(t.getTopLeft(first).dx));
      expect(t.getSize(find.byKey(const Key('palette-strip'))).height, 96);
      await t.tap(second);
      await t.pump();
      expect(
        t
            .widget<PixelCanvas>(find.byType(PixelCanvas))
            .previewOptions['paletteIndex'],
        1,
      );
      for (final option in ['x', 'y', 'diagonal', 'antiDiagonal']) {
        await t.tap(find.byKey(const Key('mirroring-menu')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(Key('mirror-$option')));
        await t.pumpAndSettle();
      }
      var canvas = t.widget<PixelCanvas>(find.byType(PixelCanvas));
      expect(canvas.tool, 'pencil');
      expect(canvas.mirrorX && canvas.mirrorY, isTrue);
      expect(canvas.mirrorDiagonal && canvas.mirrorAntiDiagonal, isTrue);
      expect(
        t
            .widget<Badge>(find.byKey(const Key('mirroring-status')))
            .isLabelVisible,
        isTrue,
      );
      expect(calls.where((call) => call.$1 == 'stroke'), isEmpty);
      await canvas.onStroke('pencil', const [Offset(3, 4)]);
      await t.pumpAndSettle();
      final args = calls.lastWhere((call) => call.$1 == 'stroke').$2!;
      for (final key in [
        'mirrorX',
        'mirrorY',
        'mirrorDiagonal',
        'mirrorAntiDiagonal',
      ]) {
        expect(args[key], isTrue, reason: key);
      }
      expect(args['paletteIndex'], 1);
      await t.tap(find.byKey(const Key('tool-group-eraser')));
      await t.pump();
      await t.tap(find.byKey(const Key('mirroring-menu')));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      canvas = t.widget<PixelCanvas>(find.byType(PixelCanvas));
      expect(canvas.tool, 'eraser');
      expect(canvas.mirrorDiagonal && canvas.mirrorAntiDiagonal, isTrue);
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await _capture(t, boundaryKey, 'mirror-${entry.key}');
      }
      await t.tap(find.byKey(const Key('mirroring-menu')));
      await t.pumpAndSettle();
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await _capture(t, boundaryKey, 'mirror-${entry.key}-menu');
      }
      await t.tap(find.text('Turn off'));
      await t.pumpAndSettle();
      canvas = t.widget<PixelCanvas>(find.byType(PixelCanvas));
      expect(
        canvas.mirrorX ||
            canvas.mirrorY ||
            canvas.mirrorDiagonal ||
            canvas.mirrorAntiDiagonal,
        isFalse,
      );
      expect(
        t
            .widget<Badge>(find.byKey(const Key('mirroring-status')))
            .isLabelVisible,
        isFalse,
      );
      expect(canvas.tool, 'eraser');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets('landscape retains mirroring without a checkbox row', (t) async {
    t.view.physicalSize = const Size(640, 360);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final editor = Editor(transport: (_, _) async => fixture.state());
    await t.pumpWidget(PocketPixelApp(editor: editor));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('mirroring-menu')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('mirror-diagonal')));
    await t.pumpAndSettle();
    expect(
      t.widget<PixelCanvas>(find.byType(PixelCanvas)).mirrorDiagonal,
      isTrue,
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}

Future<void> _capture(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/ui').create(recursive: true);
    await File('build/ui/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
