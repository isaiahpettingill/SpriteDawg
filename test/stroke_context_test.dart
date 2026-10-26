import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/pixel_canvas.dart';
import 'stroke_handoff_test.dart' as helpers;

Future<void> hostContext(WidgetTester tester, Editor editor, int token) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 320,
          height: 320,
          child: RepaintBoundary(
            key: const Key('capture'),
            child: PixelCanvas(
              editor: editor,
              tool: 'pencil',
              color: 0x80ff0000,
              brush: 1,
              grid: false,
              onion: false,
              fitToken: token,
              onPick: (_) {},
              onStroke: (_, _) async {
                await editor.call('stroke');
              },
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('editor swap discards retained ink despite late old commit', (
    tester,
  ) async {
    final gate = Completer<void>();
    final painted = Uint8List(4096);
    for (var i = 0; i < painted.length; i += 4) {
      painted[i] = 255;
      painted[i + 3] = 128;
    }
    final old = Editor(
      transport: (method, _) async {
        if (method == 'stroke') {
          await gate.future;
          return helpers.state(painted);
        }
        return helpers.state(Uint8List(4096));
      },
    );
    final next = Editor(
      transport: (_, _) async => helpers.state(Uint8List(4096)),
    );
    await tester.runAsync(() async {
      await old.call('init');
      await next.call('init');
    });
    await hostContext(tester, old, 0);
    final blank = await helpers.capture(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('pixel-canvas'))),
    );
    await gesture.moveBy(const Offset(80, 0));
    await gesture.up();
    await tester.pump();
    expect(await helpers.capture(tester), isNot(orderedEquals(blank)));
    await hostContext(tester, next, 0);
    expect(await helpers.capture(tester), orderedEquals(blank));
    gate.complete();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pump();
    expect(await helpers.capture(tester), orderedEquals(blank));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    old.dispose();
    next.dispose();
  });

  testWidgets('fit boundary clears pending ink and late callback is safe', (
    tester,
  ) async {
    final gate = Completer<void>();
    final editor = Editor(
      transport: (method, _) async {
        if (method == 'stroke') await gate.future;
        return helpers.state(Uint8List(4096));
      },
    );
    await tester.runAsync(() => editor.call('init'));
    await hostContext(tester, editor, 0);
    final blank = await helpers.capture(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('pixel-canvas'))),
    );
    await gesture.moveBy(const Offset(80, 0));
    await gesture.up();
    await tester.pump();
    expect(await helpers.capture(tester), isNot(orderedEquals(blank)));
    await hostContext(tester, editor, 1);
    await tester.pump();
    expect(await helpers.capture(tester), orderedEquals(blank));
    gate.complete();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pump();
    expect(await helpers.capture(tester), orderedEquals(blank));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    editor.dispose();
  });
}
