import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/color_picker.dart';

void main() {
  testWidgets('Visual color picker phone render', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (const bool.fromEnvironment('CAPTURE_UI')) {
      await tester.runAsync(() async {
        const path = String.fromEnvironment('CAPTURE_FONT');
        if (path.isNotEmpty) {
          await (FontLoader('Roboto')
                ..addFont(File(path).readAsBytes().then(ByteData.sublistView)))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        }
      });
    }
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xffa9b8ff),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      showSpriteColorPicker(context, initialColor: 0xa040b4dc),
                  child: const Text('Choose color'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose color'));
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
          'build/ui/color-picker-phone.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
