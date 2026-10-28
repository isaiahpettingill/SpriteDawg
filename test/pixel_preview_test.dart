import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/pixel_canvas.dart';

void main() {
  testWidgets(
    'effect preview forwards all axes and changing them cancels safely',
    (t) async {
      final calls = <Map<String, dynamic>>[];
      var commits = 0;
      final editor = Editor(
        transport: (method, args) async {
          if (method == 'previewStroke') calls.add(args!);
          return null;
        },
      );
      Future<void> host(bool diagonal) => t.pumpWidget(
        MaterialApp(
          home: PixelCanvas(
            editor: editor,
            tool: 'blur',
            color: 0xff000000,
            brush: 5,
            grid: false,
            onion: false,
            fitToken: 0,
            mirrorX: true,
            mirrorY: true,
            mirrorDiagonal: diagonal,
            mirrorAntiDiagonal: diagonal,
            onPick: (_) {},
            onStroke: (_, _) {
              commits++;
            },
          ),
        ),
      );
      await host(true);
      final center = t.getCenter(find.byKey(const Key('pixel-canvas')));
      final gesture = await t.startGesture(center);
      await t.pump(const Duration(milliseconds: 80));
      expect(calls, hasLength(1));
      for (final key in [
        'mirrorX',
        'mirrorY',
        'mirrorDiagonal',
        'mirrorAntiDiagonal',
      ]) {
        expect(calls.single[key], isTrue);
      }
      await host(false);
      await gesture.moveBy(const Offset(20, 20));
      await gesture.up();
      await t.pump();
      expect(commits, 0);
      final next = await t.startGesture(center);
      await t.pump(const Duration(milliseconds: 80));
      expect(calls.last['mirrorDiagonal'], isFalse);
      expect(calls.last['mirrorAntiDiagonal'], isFalse);
      await next.cancel();
      await t.pumpWidget(const SizedBox());
      editor.dispose();
    },
  );
  testWidgets(
    'A held effect restarts preview after an older canceled request',
    (tester) async {
      final first = Completer<Map<String, dynamic>?>();
      final calls = <Map<String, dynamic>>[];
      final editor = Editor(
        transport: (method, arguments) async {
          expect(method, 'previewStroke');
          calls.add(arguments!);
          if (calls.length == 1) return first.future;
          return null;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PixelCanvas(
              editor: editor,
              tool: 'blur',
              color: 0xff000000,
              brush: 5,
              grid: false,
              onion: false,
              fitToken: 0,
              onPick: (_) {},
              onStroke: (_, _) {},
            ),
          ),
        ),
      );
      final center = tester.getCenter(find.byKey(const Key('pixel-canvas')));
      final a = await tester.startGesture(center, pointer: 1);
      await tester.pump(const Duration(milliseconds: 80));
      expect(calls, hasLength(1));
      await a.cancel();
      final b = await tester.startGesture(
        center + const Offset(30, 0),
        pointer: 2,
      );
      await tester.pump(const Duration(milliseconds: 80));
      expect(calls, hasLength(1), reason: 'Only one preview may be in flight');
      first.complete(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(calls, hasLength(2));
      expect(calls.last['points'], isNot(calls.first['points']));
      await b.cancel();
      await tester.pumpWidget(const SizedBox.shrink());
      editor.dispose();
    },
  );
}
