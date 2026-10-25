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
import 'package:spritedawg/main.dart';

void main() {
  for (final entry in {
    'phone': const Size(390, 844),
    'tablet': const Size(900, 1100),
    'desktop': const Size(1440, 900),
  }.entries) {
    testWidgets('${entry.key} visual tag workspace render', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = EditorEngine();
      final document = SpriteDocument.create(24, 24);
      document.frames.clear();
      for (var f = 0; f < 8; f++) {
        final pixels = Uint32List(24 * 24);
        final shade = [0xff95e1c0, 0xff71c7f3, 0xffffd77a, 0xffffa7b5][f % 4];
        for (var y = 5; y < 20; y++) {
          for (var x = 5; x < 19; x++) {
            if ((y == 5 || y == 19) && (x == 5 || x == 18)) continue;
            pixels[y * 24 + x] = shade;
            if ((y == 10 || y == 11) && (x == 9 || x == 15) ||
                (y == 16 && x >= 10 && x <= 14)) {
              pixels[y * 24 + x] = 0xff171d29;
            }
          }
        }
        document.frames.add(
          Frame(cels: [Cel(0, 0, 24, 24, pixels)], duration: 100 + f * 20),
        );
      }
      document.tags = [Tag(0, 3, 'Tile variants'), Tag(4, 7, 'NPC walk')];
      engine.replace(document);
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
                'title': 'Game sprites',
                'dirty': false,
                'active': true,
              },
              {'id': 2, 'title': 'Player', 'dirty': false, 'active': false},
            ],
            'hasTagClipboard': false,
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
        for (var frame = 0; frame < 8; frame++) {
          (await editor.thumbnail(frame))?.dispose();
        }
      });
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: PocketPixelApp(editor: editor),
        ),
      );
      await tester.pumpAndSettle();
      final playback = find.widgetWithIcon(
        IconButton,
        Icons.play_circle_outline,
      );
      expect(tester.widget<IconButton>(playback).iconSize, 32);
      expect(tester.getSize(playback).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(playback).height, greaterThanOrEqualTo(48));
      await tester.tap(playback);
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.pause_circle),
            )
            .iconSize,
        32,
      );
      await tester.tap(find.byTooltip('Stop animation'));
      await tester.pump();
      await tester.tap(find.text('Tags').first);
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Tile variants').first);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byKey(const Key('browse-tag'))).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const Key('tag-frame-strip'))).top + 1,
        ),
        reason: 'Pinned thumbnails must not obscure the tag range controls.',
      );
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/ui').create(recursive: true);
          await File(
            'build/ui/${entry.key}-tags.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
