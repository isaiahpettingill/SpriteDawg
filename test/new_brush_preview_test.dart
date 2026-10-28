import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/pixel_canvas.dart';

void main() {
  for (final tool in ['leaves', 'splatter']) {
    testWidgets(
      '$tool restarts preview after cancellation and never commits canceled strokes',
      (tester) async {
        final first = Completer<Map<String, dynamic>?>();
        final calls = <Map<String, dynamic>>[];
        var commits = 0;
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
                tool: tool,
                color: 0xff000000,
                brush: 12,
                grid: false,
                onion: false,
                fitToken: 0,
                onPick: (_) {},
                onStroke: (_, _) {
                  commits++;
                },
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
        expect(calls.last['tool'], tool);
        await b.cancel();
        expect(commits, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        editor.dispose();
      },
    );
  }
}
