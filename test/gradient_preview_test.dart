import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/pixel_canvas.dart';
import 'stroke_handoff_test.dart' as handoff;

void main() {
  testWidgets(
    'Gradient previews full frame, forwards endpoints/colors and retains alpha on commit',
    (t) async {
      final gate = Completer<void>();
      final result = Uint8List(4096);
      for (var i = 0; i < result.length; i += 4) {
        result[i] = 255;
        result[i + 3] = 128;
      }
      Map<String, dynamic>? previewArgs;
      final editor = Editor(
        transport: (method, args) async {
          if (method == 'previewStroke') {
            previewArgs = args;
            return handoff.state(result);
          }
          if (method == 'stroke') {
            await gate.future;
            return handoff.state(result);
          }
          return handoff.state(Uint8List(4096));
        },
      );
      await t.runAsync(() => editor.call('init'));
      await t.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 320,
              height: 320,
              child: RepaintBoundary(
                key: const Key('capture'),
                child: PixelCanvas(
                  editor: editor,
                  tool: 'gradient',
                  color: 0x80ff0000,
                  brush: 1,
                  grid: false,
                  onion: false,
                  fitToken: 0,
                  previewOptions: const {'secondaryColor': 0x800000ff},
                  onPick: (_) {},
                  onStroke: (_, points) async {
                    await editor.call('stroke');
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final top = t.getTopLeft(find.byKey(const Key('pixel-canvas')));
      final gesture = await t.startGesture(top + const Offset(50, 50));
      await gesture.moveTo(top + const Offset(250, 250));
      await t.pump(const Duration(milliseconds: 100));
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pump();
      expect(previewArgs?['tool'], 'gradient');
      expect(previewArgs?['secondaryColor'], 0x800000ff);
      expect((previewArgs?['points'] as List).length, greaterThanOrEqualTo(2));
      final before = await handoff.capture(t);
      await gesture.up();
      await t.pump();
      expect(await handoff.capture(t), orderedEquals(before));
      gate.complete();
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pump();
      expect(
        await handoff.capture(t),
        orderedEquals(before),
        reason: 'No double-alpha or stale frame at gradient handoff',
      );
      await t.pumpWidget(const SizedBox());
      editor.dispose();
    },
  );
  testWidgets('Cancel gradient preview makes no edit', (t) async {
    var commits = 0;
    final editor = Editor(
      transport: (method, _) async => handoff.state(Uint8List(4096)),
    );
    await t.runAsync(() => editor.call('init'));
    await t.pumpWidget(
      MaterialApp(
        home: PixelCanvas(
          editor: editor,
          tool: 'gradient',
          color: 0xffff0000,
          brush: 1,
          grid: false,
          onion: false,
          fitToken: 0,
          onPick: (_) {},
          onStroke: (_, _) {
            commits++;
          },
        ),
      ),
    );
    final gesture = await t.startGesture(
      t.getCenter(find.byKey(const Key('pixel-canvas'))),
    );
    await gesture.moveBy(const Offset(50, 20));
    await gesture.cancel();
    await t.pump();
    expect(commits, 0);
    await t.pumpWidget(const SizedBox());
    editor.dispose();
  });
}
