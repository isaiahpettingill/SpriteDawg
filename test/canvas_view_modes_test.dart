import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/canvas_view_mode.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/pixel_canvas.dart';

Uint8List solid(int red, int green, int blue) => Uint8List.fromList([
  for (var i = 0; i < 64; i++) ...[red, green, blue, 255],
]);

Future<void> host(
  WidgetTester tester,
  Editor editor,
  CanvasViewMode mode, {
  FutureOr<void> Function(String, List<Offset>)? onStroke,
  bool onion = false,
}) => tester.pumpWidget(
  MaterialApp(
    home: Center(
      child: SizedBox(
        width: 320,
        height: 320,
        child: RepaintBoundary(
          key: const Key('view-capture'),
          child: PixelCanvas(
            editor: editor,
            tool: 'pencil',
            color: 0x80ffffff,
            brush: 1,
            grid: false,
            onion: onion,
            fitToken: 0,
            viewMode: mode,
            onPick: (_) {},
            onStroke: onStroke ?? (_, _) {},
          ),
        ),
      ),
    ),
  ),
);

Future<Uint8List> capture(WidgetTester tester) async =>
    (await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('view-capture')),
      );
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      image.dispose();
      return bytes;
    }))!;

List<int> pixel(Uint8List bytes, int x, int y) =>
    bytes.sublist((y * 320 + x) * 4, (y * 320 + x) * 4 + 4);

void main() {
  test(
    'Tiled geometry is bounded and central hit bounds exclude neighbors',
    () {
      expect(canvasContextOffsets(CanvasViewMode.normal), isEmpty);
      expect(canvasContextOffsets(CanvasViewMode.tiled), hasLength(8));
      expect(
        canvasContextOffsets(CanvasViewMode.tiled),
        isNot(contains(Offset.zero)),
      );
      expect(canvasContextOffsets(CanvasViewMode.slide), [
        const Offset(-1, 0),
        const Offset(1, 0),
      ]);
      expect(isEditableCanvasPoint(const Offset(0, 0), 8, 8), isTrue);
      expect(isEditableCanvasPoint(const Offset(7.99, 7.99), 8, 8), isTrue);
      for (final p in [
        const Offset(-.01, 0),
        const Offset(8, 0),
        const Offset(0, 8),
      ]) {
        expect(isEditableCanvasPoint(p, 8, 8), isFalse);
      }
    },
  );

  testWidgets(
    'Tiled repeats cached image in nine cells; neighbors never draw',
    (tester) async {
      final strokes = <List<Offset>>[];
      final editor = Editor(
        transport: (_, _) async => {
          'width': 8,
          'height': 8,
          'pixels': solid(220, 20, 30),
        },
      );
      await tester.runAsync(() => editor.call('init'));
      await host(
        tester,
        editor,
        CanvasViewMode.tiled,
        onStroke: (_, points) => strokes.add(points),
      );
      await tester.pump();
      final bytes = await capture(tester);
      for (final y in [66, 160, 253]) {
        for (final x in [66, 160, 253]) {
          expect(pixel(bytes, x, y), [220, 20, 30, 255]);
        }
      }
      final top = tester.getTopLeft(find.byKey(const Key('pixel-canvas')));
      await tester.tapAt(top + const Offset(66, 160));
      expect(strokes, isEmpty);
      await tester.tapAt(top + const Offset(160, 160));
      expect(strokes, hasLength(1));
      expect(
        strokes.single.every((p) => isEditableCanvasPoint(p, 8, 8)),
        isTrue,
      );
      final gesture = await tester.startGesture(top + const Offset(160, 160));
      await gesture.moveTo(top + const Offset(175, 160));
      await gesture.moveTo(top + const Offset(253, 160));
      await gesture.up();
      expect(
        strokes,
        hasLength(2),
        reason:
            'Leaving the center commits once, not into the neighboring tile',
      );
      expect(strokes.last.every((p) => isEditableCanvasPoint(p, 8, 8)), isTrue);
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
    },
  );

  for (final frame in [0, 1, 2]) {
    testWidgets(
      'Slide displays adjacent frames without wrapping at frame $frame',
      (tester) async {
        final editor = Editor(
          transport: (method, _) async {
            if (method == 'frameImage') {
              return {
                'frame': frame + 1,
                'width': 8,
                'height': 8,
                'pixels': solid(0, 0, 255),
              };
            }
            return {
              'width': 8,
              'height': 8,
              'frame': frame,
              'frames': [{}, {}, {}],
              'pixels': solid(255, 0, 0),
              'previousPixels': solid(0, 255, 0),
            };
          },
        );
        await tester.runAsync(() => editor.call('init'));
        await host(tester, editor, CanvasViewMode.slide, onion: true);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        final bytes = await capture(tester);
        expect(pixel(bytes, 160, 160), [255, 0, 0, 255]);
        expect(
          pixel(bytes, 66, 160),
          frame == 0 ? [16, 20, 29, 255] : [0, 255, 0, 255],
        );
        expect(
          pixel(bytes, 253, 160),
          frame == 2 ? [16, 20, 29, 255] : [0, 0, 255, 255],
        );
        await tester.pumpWidget(const SizedBox());
        editor.dispose();
      },
    );
  }

  testWidgets(
    'Tiled live stroke and pending commit remain visually identical',
    (tester) async {
      final gate = Completer<void>();
      final editor = Editor(
        transport: (_, _) async => {
          'width': 8,
          'height': 8,
          'pixels': solid(30, 50, 80),
        },
      );
      await tester.runAsync(() => editor.call('init'));
      await host(
        tester,
        editor,
        CanvasViewMode.tiled,
        onStroke: (_, _) => gate.future,
      );
      final top = tester.getTopLeft(find.byKey(const Key('pixel-canvas')));
      final gesture = await tester.startGesture(top + const Offset(145, 145));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      final before = await capture(tester);
      await gesture.up();
      await tester.pump();
      expect(await capture(tester), orderedEquals(before));
      await tester.pump(const Duration(seconds: 1));
      expect(await capture(tester), orderedEquals(before));
      gate.complete();
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
    },
  );
  testWidgets(
    'Neighbor drag pans and wheel zoom preserves central edit mapping',
    (tester) async {
      final strokes = <List<Offset>>[];
      final editor = Editor(
        transport: (_, _) async => {'width': 8, 'height': 8},
      );
      await editor.call('init');
      await host(
        tester,
        editor,
        CanvasViewMode.tiled,
        onStroke: (_, points) => strokes.add(points),
      );
      final top = tester.getTopLeft(find.byKey(const Key('pixel-canvas')));
      final pan = await tester.startGesture(top + const Offset(66, 160));
      await pan.moveBy(const Offset(40, 0));
      await pan.up();
      await tester.pump();
      expect(strokes, isEmpty);
      await tester.tapAt(top + const Offset(160, 160));
      expect(strokes.single.single.dx, closeTo(4 - 40 / (280 / 24), .01));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: top + const Offset(160, 160),
          scrollDelta: const Offset(0, -277.258872),
        ),
      );
      await tester.pump();
      await tester.tapAt(top + const Offset(180, 160));
      expect(
        strokes.last.single.dx,
        closeTo(strokes.first.single.dx + 20 / (2 * 280 / 24), .01),
      );
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
    },
  );
}
