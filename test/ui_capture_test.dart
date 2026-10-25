import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/main.dart';

void main() {
  testWidgets('Phone editor screenshot', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pixels = Uint8List(32 * 32 * 4);
    for (var y = 9; y < 24; y++) {
      for (var x = 8; x < 24; x++) {
        if ((y == 9 || y == 23) && (x == 8 || x == 23)) continue;
        final i = (y * 32 + x) * 4;
        pixels.setRange(i, i + 4, [169, 184, 255, 255]);
        if ((y >= 13 && y <= 15 && (x == 12 || x == 19)) ||
            (y == 19 && x > 12 && x < 19)) {
          pixels.setRange(i, i + 4, [21, 26, 37, 255]);
        }
      }
    }
    var initialized = false;
    final editor = Editor(
      transport: (method, args) async {
        if (initialized) return null;
        initialized = true;
        return {
          'width': 32,
          'height': 32,
          'depth': 32,
          'frame': 0,
          'layer': 0,
          'dirty': true,
          'canUndo': true,
          'canRedo': false,
          'pixels': pixels,
          'palette': [
            0xff000000,
            0xffffffff,
            0xffa9b8ff,
            0xffffa7b5,
            0xffffd77a,
            0xff95e1c0,
            0xff71c7f3,
          ],
          'layers': [
            {
              'name': 'Drawing',
              'visible': true,
              'opacity': 255,
              'editable': true,
              'background': false,
            },
          ],
          'frames': [
            {'duration': 100},
          ],
          'tags': [],
        };
      },
    );
    await tester.runAsync(() async {
      const fontPath = String.fromEnvironment('CAPTURE_FONT');
      if (fontPath.isNotEmpty) {
        final loader = FontLoader('Roboto')
          ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
        await loader.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
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
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CAPTURE_UI')) {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/ui').create(recursive: true);
        await File(
          'build/ui/phone-editor.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
