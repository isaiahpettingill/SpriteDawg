import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/pixel_canvas.dart';
import 'package:spritedawg/rgba_image.dart';

Map<String, dynamic> state(Uint8List pixels) => {
  'width': 32,
  'height': 32,
  'pixels': pixels,
};

Future<Uint8List> capture(WidgetTester tester) async =>
    (await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('capture')),
      );
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      image.dispose();
      return bytes;
    }))!;

Future<void> host(
  WidgetTester tester,
  Editor editor, {
  String tool = 'pencil',
  int color = 0x80ff0000,
}) async {
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
              tool: tool,
              color: color,
              brush: 1,
              grid: false,
              onion: false,
              fitToken: 0,
              onPick: (_) {},
              onStroke: (tool, points) async {
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
  testWidgets(
    'long translucent stroke stays visible through commit without alpha doubling',
    (tester) async {
      final gate = Completer<void>();
      final initial = Uint8List(32 * 32 * 4);
      final finalPixels = Uint8List.fromList(initial);
      // Host fits 32px at 8.75x, origin 20; row 9, x2..29.
      for (var x = 2; x <= 29; x++) {
        final i = (9 * 32 + x) * 4;
        finalPixels[i] = 255;
        finalPixels[i + 3] = 128;
      }
      final editor = Editor(
        transport: (method, _) async {
          if (method == 'stroke') {
            await gate.future;
            return state(finalPixels);
          }
          return state(initial);
        },
      );
      await tester.runAsync(() => editor.call('init'));
      await host(tester, editor);
      final top = tester.getTopLeft(find.byKey(const Key('pixel-canvas')));
      final gesture = await tester.startGesture(top + const Offset(42, 103));
      for (var x = 3; x <= 29; x++) {
        await gesture.moveTo(top + Offset(20 + x * 8.75 + 4, 103));
      }
      await tester.pump();
      final before = await capture(tester);
      await gesture.up();
      await tester.pump();
      expect(await capture(tester), orderedEquals(before));
      await tester.pump(const Duration(seconds: 2));
      expect(
        await capture(tester),
        orderedEquals(before),
        reason: 'No old-frame flash during slow backend',
      );
      gate.complete();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pump();
      expect(
        await capture(tester),
        orderedEquals(before),
        reason: 'Committed alpha must not blend with retained overlay twice',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      editor.dispose();
    },
  );

  testWidgets('preview remains until replacement pixels finish decoding', (
    tester,
  ) async {
    final decodeGate = Completer<void>();
    var decodes = 0;
    final editor = Editor(
      decodeImage: (pixels, {required width, required height}) async {
        if (++decodes == 2) await decodeGate.future;
        return decodeStraightRgba(pixels, width: width, height: height);
      },
      transport: (method, _) async => state(Uint8List(4096)),
    );
    await tester.runAsync(() => editor.call('init'));
    await host(tester, editor);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('pixel-canvas'))),
    );
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    final before = await capture(tester);
    await gesture.up();
    await tester.pump();
    expect(decodes, 2);
    expect(
      await capture(tester),
      orderedEquals(before),
      reason: 'Transport returned but GPU image not ready',
    );
    decodeGate.complete();
    await tester.pump();
    for (var i = 0; editor.busy && i < 20; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
    }
    expect(editor.busy, false);
    await tester.pump();
    await tester.pump();
    expect(await capture(tester), isNot(orderedEquals(before)));
    await tester.pumpWidget(const SizedBox.shrink());
    editor.dispose();
  });

  testWidgets('canceled stroke never becomes a retained commit', (
    tester,
  ) async {
    var commits = 0;
    final editor = Editor(
      transport: (method, _) async {
        if (method == 'stroke') commits++;
        return state(Uint8List(4096));
      },
    );
    await tester.runAsync(() => editor.call('init'));
    await host(tester, editor);
    final blank = await capture(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('pixel-canvas'))),
    );
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    expect(await capture(tester), isNot(orderedEquals(blank)));
    await gesture.cancel();
    await tester.pump();
    expect(await capture(tester), orderedEquals(blank));
    expect(commits, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    editor.dispose();
  });

  testWidgets('second finger retains committed segment while pan begins', (
    tester,
  ) async {
    final gate = Completer<void>();
    var commits = 0;
    final editor = Editor(
      transport: (method, _) async {
        if (method == 'stroke') {
          commits++;
          await gate.future;
        }
        return state(Uint8List(4096));
      },
    );
    await tester.runAsync(() => editor.call('init'));
    await host(tester, editor);
    final center = tester.getCenter(find.byKey(const Key('pixel-canvas')));
    final a = await tester.startGesture(center, pointer: 1);
    await a.moveBy(const Offset(60, 0));
    await tester.pump();
    final before = await capture(tester);
    final b = await tester.startGesture(
      center + const Offset(0, 40),
      pointer: 2,
    );
    await tester.pump();
    expect(commits, 1);
    expect(await capture(tester), orderedEquals(before));
    await a.up();
    await b.up();
    await tester.pump();
    expect(await capture(tester), orderedEquals(before));
    gate.complete();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    editor.dispose();
  });

  testWidgets(
    'queued translucent strokes hand off independently without double paint',
    (tester) async {
      final gates = [Completer<void>(), Completer<void>()];
      final frames = [Uint8List(4096), Uint8List(4096), Uint8List(4096)];
      for (var step = 1; step <= 2; step++) {
        for (var row in [9, if (step == 2) 15]) {
          for (var x = 2; x <= 20; x++) {
            final i = (row * 32 + x) * 4;
            frames[step][i] = 255;
            frames[step][i + 3] = 128;
          }
        }
      }
      var count = 0;
      final editor = Editor(
        transport: (method, _) async {
          if (method != 'stroke') return state(frames[0]);
          final n = count++;
          await gates[n].future;
          return state(frames[n + 1]);
        },
      );
      await tester.runAsync(() => editor.call('init'));
      await host(tester, editor);
      final top = tester.getTopLeft(find.byKey(const Key('pixel-canvas')));
      for (final row in [9, 15]) {
        final a = await tester.startGesture(
          top + Offset(42, 20 + row * 8.75 + 4),
        );
        await a.moveTo(top + Offset(199, 20 + row * 8.75 + 4));
        await a.up();
        await tester.pump();
      }
      final both = await capture(tester);
      gates[0].complete();
      await tester.pump();
      for (var i = 0; count < 2 && i < 20; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
      }
      await tester.pump();
      expect(count, 2);
      expect(await capture(tester), orderedEquals(both));
      gates[1].complete();
      await tester.pump();
      for (var i = 0; editor.busy && i < 20; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
      }
      await tester.pump();
      expect(editor.busy, false);
      expect(await capture(tester), orderedEquals(both));
      await tester.pumpWidget(const SizedBox.shrink());
      editor.dispose();
    },
  );

  testWidgets('failed commit removes retained ink', (tester) async {
    final gate = Completer<void>();
    final editor = Editor(
      transport: (method, _) async {
        if (method == 'stroke') {
          await gate.future;
          throw StateError('failed write');
        }
        return state(Uint8List(4096));
      },
    );
    await tester.runAsync(() => editor.call('init'));
    await host(tester, editor);
    final blank = await capture(tester);
    final a = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('pixel-canvas'))),
    );
    await a.moveBy(const Offset(60, 0));
    await a.up();
    await tester.pump();
    expect(await capture(tester), isNot(orderedEquals(blank)));
    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(editor.error, contains('failed write'));
    expect(await capture(tester), orderedEquals(blank));
    await tester.pumpWidget(const SizedBox.shrink());
    editor.dispose();
    expect(tester.takeException(), isNull);
  });

  for (final tool in ['blur', 'jumble', 'spray', 'airbrush']) {
    testWidgets('$tool retains exact decoded preview during slow commit', (
      tester,
    ) async {
      final gate = Completer<void>();
      final original = Uint8List(4096);
      final changed = Uint8List(4096);
      // Deliberately translucent entire-frame preview exercises replacement,
      // not source-over compositing the same frame over itself.
      for (var i = 0; i < changed.length; i += 4) {
        changed[i + 2] = 255;
        changed[i + 3] = 96;
      }
      final editor = Editor(
        transport: (method, _) async {
          if (method == 'stroke') {
            await gate.future;
            return state(changed);
          }
          return state(method == 'previewStroke' ? changed : original);
        },
      );
      await tester.runAsync(() => editor.call('init'));
      await host(tester, editor, tool: tool);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('pixel-canvas'))),
      );
      await tester.pump(const Duration(milliseconds: 80));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pump();
      final before = await capture(tester);
      await gesture.up();
      await tester.pump();
      expect(await capture(tester), orderedEquals(before));
      await tester.pump(const Duration(seconds: 1));
      expect(await capture(tester), orderedEquals(before));
      gate.complete();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pump();
      expect(await capture(tester), orderedEquals(before));
      await tester.pumpWidget(const SizedBox.shrink());
      editor.dispose();
    });
  }
}
