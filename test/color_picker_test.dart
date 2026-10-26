import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/color_picker.dart';

void main() {
  testWidgets('Visual pad and hue choose colors while alpha survives', (
    tester,
  ) async {
    var color = 0x80445566;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: SpriteColorPicker(
                initialColor: color,
                onChanged: (value) => color = value,
              ),
            ),
          ),
        ),
      ),
    );
    final square = find.byKey(const Key('color-saturation-value'));
    final rect = tester.getRect(square);
    await tester.tapAt(Offset(rect.right - 1, rect.top + 1));
    await tester.pump();
    expect(color >> 24, 0x80);
    final hsv = HSVColor.fromColor(Color(color));
    expect(hsv.saturation, greaterThan(.98));
    expect(hsv.value, greaterThan(.98));
    final hue = tester.widget<Slider>(find.byKey(const Key('color-hue')));
    hue.onChanged!(120);
    await tester.pump();
    expect((color >> 8) & 255, greaterThan(250));
    expect((color >> 16) & 255, lessThan(5));
    expect(color >> 24, 0x80);
  });

  testWidgets('Hex accepts RGB or ARGB and retains hidden transparent color', (
    tester,
  ) async {
    var color = 0xff000000;
    var valid = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SpriteColorPicker(
              initialColor: color,
              onChanged: (v) => color = v,
              onValidityChanged: (v) => valid = v,
            ),
          ),
        ),
      ),
    );
    final field = find.byKey(const Key('color-hex'));
    await tester.enterText(field, '123456');
    expect(color, 0xff123456);
    await tester.enterText(field, '00123456');
    expect(color, 0x00123456);
    await tester.enterText(field, 'bad input');
    expect(valid, isFalse);
    expect(color, 0x00123456);
    await tester.enterText(field, '80123456');
    expect(valid, isTrue);
    expect(color, 0x80123456);
  });

  for (final size in [const Size(320, 568), const Size(568, 320)]) {
    testWidgets('Picker fits $size and invalid text cannot be saved', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      int? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showSpriteColorPicker(
                    context,
                    initialColor: 0x8044aa88,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final field = find.byKey(const Key('color-hex'));
      await tester.ensureVisible(field);
      await tester.enterText(field, 'xyz');
      tester.view.viewInsets = const FakeViewPadding(bottom: 120);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use color'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(field, '0044AA88');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use color'));
      await tester.pumpAndSettle();
      expect(result, 0x0044aa88);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Cancel does not change selected color', (tester) async {
    int? result = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showSpriteColorPicker(
                  context,
                  initialColor: 0xff123456,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('color-hex')), 'FF00FF00');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
