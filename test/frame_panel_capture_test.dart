import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/engine/document.dart';
import 'package:spritedawg/engine/editor_engine.dart';
import 'package:spritedawg/frame_panel.dart';
import 'package:spritedawg/main.dart';

void main() {
  for (final entry in {
    'phone320': const Size(320, 568),
    'phone390': const Size(390, 844),
    'desktop': const Size(1440, 900),
  }.entries) {
    testWidgets('${entry.key} compact frame workspace render', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pixels = Uint32List(24 * 24);
      for (var y = 5; y < 20; y++) {
        for (var x = 5; x < 19; x++) {
          if ((y == 5 || y == 19) && (x == 5 || x == 18)) continue;
          pixels[y * 24 + x] = 0xff95e1c0;
          if ((y == 10 || y == 11) && (x == 9 || x == 15) ||
              (y == 16 && x >= 10 && x <= 14)) {
            pixels[y * 24 + x] = 0xff171d29;
          }
        }
      }
      final document = SpriteDocument.create(24, 24);
      document.frames.clear();
      for (var frame = 0; frame < 80; frame++) {
        document.frames.add(
          Frame(
            cels: [Cel(0, 0, 24, 24, Uint32List.fromList(pixels))],
            duration: 100 + frame,
          ),
        );
      }
      final engine = EditorEngine()..replace(document);
      engine.frame = 69;
      var initialized = false;
      final editor = Editor(
        transport: (method, args) async {
          if (method == 'init') {
            if (initialized) return null;
            initialized = true;
          }
          if (method == 'thumbnails') return engine.thumbnails(args!);
          if (method != 'init') engine.invoke(method, args ?? {});
          return {
            ...engine.state(),
            'documentId': 1,
            'documents': [
              {
                'id': 1,
                'title': 'Character walk',
                'dirty': false,
                'active': true,
              },
            ],
          };
        },
      );
      await tester.runAsync(() async {
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
        await editor.call('init');
      });
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: PocketPixelApp(editor: editor),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Frames').first);
      await tester.pumpAndSettle();
      final strip = find.byKey(const Key('frame-strip'));
      final selected = find.byKey(const Key('frame-card-69'));
      expect(selected.hitTestable(), findsOneWidget);
      final viewport = tester.getRect(strip);
      final card = tester.getRect(selected);
      expect(card.left, greaterThanOrEqualTo(viewport.left));
      expect(card.right, lessThanOrEqualTo(viewport.right));
      expect(tester.getSize(find.byType(FramePanel)).height, 120);
      expect(find.text('Hold to time'), findsNothing);
      expect(find.text('169 ms'), findsNothing);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/ui').create(recursive: true);
          await File(
            'build/ui/frames-${entry.key}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
