import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/canvas_view_mode.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/engine/document.dart';
import 'package:spritedawg/engine/editor_engine.dart';
import 'package:spritedawg/pixel_canvas.dart';
import 'package:spritedawg/main.dart';
import 'editor_test.dart' as fixture;

const _scale = 280 / 24;
const _origin = (320 - 8 * _scale) / 2;

class Harness {
  Harness() {
    engine.replace(SpriteDocument.create(8, 8));
    editor = Editor(
      transport: (method, args) async {
        if (method == 'stroke') commits.add(args!);
        if (method == 'previewStroke') previews.add(args!);
        return engine.invoke(method, args ?? {});
      },
    );
  }
  final engine = EditorEngine();
  late final Editor editor;
  final commits = <Map<String, dynamic>>[];
  final previews = <Map<String, dynamic>>[];
  final picks = <int>[];
  final key = GlobalKey();

  Future<void> host(
    WidgetTester t, {
    String tool = 'pencil',
    int size = 1,
    bool filled = false,
    bool diagonal = false,
  }) async {
    await t.runAsync(() => editor.call('state'));
    await t.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 320,
            height: 320,
            child: RepaintBoundary(
              key: key,
              child: PixelCanvas(
                editor: editor,
                tool: tool,
                color: 0x80ff0000,
                brush: size,
                grid: false,
                onion: false,
                fitToken: 0,
                viewMode: CanvasViewMode.tiled,
                filled: filled,
                mirrorDiagonal: diagonal,
                onPick: picks.add,
                onStroke: (value, points) async {
                  await editor.call('stroke', {
                    'tool': value,
                    'color': 0x80ff0000,
                    'size': size,
                    'wrap': true,
                    'filled': filled,
                    'mirrorDiagonal': diagonal,
                    'points': points
                        .map((p) => [p.dx.floor(), p.dy.floor()])
                        .toList(),
                  });
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Offset point(WidgetTester t, double x, double y) =>
      t.getTopLeft(find.byKey(const Key('pixel-canvas'))) +
      Offset(_origin + (x + .5) * _scale, _origin + (y + .5) * _scale);

  Future<void> flush(WidgetTester t) async {
    // Transport completes in the widget test's fake-async zone, while image
    // decoding is real asynchronous work. Pump both, not only wall-clock time.
    await t.pump();
    for (var i = 0; editor.busy && i < 100; i++) {
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await t.pump();
    }
    expect(editor.busy, isFalse);
    await t.pump();
  }

  Future<List<int>> screenshot(WidgetTester t, [String? name]) async =>
      (await t.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        if (name != null && const bool.fromEnvironment('CAPTURE_UI')) {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/ui/tiled-$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(png!.buffer.asUint8List());
        }
        image.dispose();
        return bytes.toList();
      }))!;

  Future<void> dispose(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    editor.dispose();
  }
}

void main() {
  testWidgets('app forwards tiled mode to preview and committed strokes', (
    t,
  ) async {
    final calls = <(String, Map<String, dynamic>?)>[];
    final editor = Editor(
      transport: (method, args) async {
        calls.add((method, args));
        return fixture.state();
      },
    );
    await t.pumpWidget(PocketPixelApp(editor: editor));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Project and view options'));
    await t.pumpAndSettle();
    await t.tap(find.text('View · Tiled (3×3)'));
    await t.pumpAndSettle();
    final canvas = t.widget<PixelCanvas>(find.byType(PixelCanvas));
    expect(canvas.viewMode, CanvasViewMode.tiled);
    await canvas.onStroke('pencil', const [Offset(-1, 2), Offset(1, 2)]);
    await t.pumpAndSettle();
    final args = calls.lastWhere((c) => c.$1 == 'stroke').$2!;
    expect(args['wrap'], isTrue);
    expect(args['points'], [
      [-1, 2],
      [1, 2],
    ]);
    final gesture = await t.startGesture(
      t.getCenter(find.byKey(const Key('pixel-canvas'))),
    );
    await t.pump(const Duration(milliseconds: 100));
    final preview = calls.lastWhere((c) => c.$1 == 'previewStroke').$2!;
    expect(preview['wrap'], isTrue);
    expect(preview['filled'], canvas.filled);
    expect(preview['gradient'], isFalse);
    expect(preview['gradientDirection'], isNotNull);
    await gesture.cancel();
    // PocketPixelApp owns and disposes its supplied Editor.
    await t.pumpWidget(const SizedBox());
  });

  for (final hand in [true, false]) {
    testWidgets(
      '${hand ? "Hand tool" : "Right mouse drag"} explicitly pans tiled view',
      (t) async {
        final h = Harness();
        await h.host(t, tool: hand ? 'pan' : 'pencil');
        final pan = await t.startGesture(
          h.point(t, -2, 3),
          kind: hand ? ui.PointerDeviceKind.touch : ui.PointerDeviceKind.mouse,
          buttons: hand ? 1 : 2,
        );
        await pan.moveBy(const Offset(35, 0));
        await pan.up();
        expect(h.commits, isEmpty);
        await h.host(t);
        await t.tapAt(h.point(t, 4, 4));
        await h.flush(t);
        expect(h.commits.last['points'], [
          [1, 4],
        ], reason: '35px pan shifts three pixels');
        await h.dispose(t);
      },
    );
  }

  testWidgets('second finger keeps an initial dot even before a drag', (
    t,
  ) async {
    final h = Harness();
    await h.host(t);
    final a = await t.startGesture(h.point(t, -1, 2), pointer: 1);
    final b = await t.startGesture(h.point(t, 4, 4), pointer: 2);
    await h.flush(t);
    expect(h.commits, hasLength(1));
    expect(h.engine.document.composite(0)[2 * 8 + 7], 0x80ff0000);
    await b.up();
    await a.up();
    expect(h.commits, hasLength(1));
    await h.dispose(t);
  });

  testWidgets('all nine repeats draw the same pixel; each tap undoes once', (
    t,
  ) async {
    final h = Harness();
    await h.host(t);
    for (var row = -1; row <= 1; row++) {
      for (var col = -1; col <= 1; col++) {
        await t.tapAt(h.point(t, 2 + col * 8.0, 3 + row * 8.0));
        await h.flush(t);
        final pixels = h.engine.document.composite(0);
        expect(pixels[3 * 8 + 2], 0x80ff0000);
        expect(pixels.where((p) => p != 0), hasLength(1));
        expect(h.commits.last['points'], [
          [2 + col * 8, 3 + row * 8],
        ]);
        await t.runAsync(() => h.editor.call('undo'));
        expect(h.engine.document.composite(0).every((p) => p == 0), isTrue);
        expect(h.engine.state()['canUndo'], isFalse);
      }
    }
    expect(h.commits, hasLength(9));
    await h.dispose(t);
  });

  testWidgets(
    'seam stroke preview, pending and final pixels agree without a center line',
    (t) async {
      final h = Harness();
      await h.host(t);
      final g = await t.startGesture(h.point(t, 7, 2));
      await g.moveTo(h.point(t, 9, 2));
      await t.pump(const Duration(milliseconds: 100));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pump();
      expect(h.previews.last['wrap'], isTrue);
      expect(h.previews.last['points'], [
        [7, 2],
        [9, 2],
      ]);
      final before = await h.screenshot(t, 'seam-live');
      await g.up();
      await h.flush(t);
      expect(await h.screenshot(t, 'seam-committed'), orderedEquals(before));
      expect(h.engine.document.composite(0).sublist(16, 24), [
        0x80ff0000,
        0x80ff0000,
        0,
        0,
        0,
        0,
        0,
        0x80ff0000,
      ]);
      expect(h.commits, hasLength(1));
      await t.runAsync(() => h.editor.call('undo'));
      expect(h.engine.document.composite(0).every((p) => p == 0), isTrue);
      await h.dispose(t);
    },
  );

  testWidgets(
    'two-finger navigation keeps ink; remaining finger neither draws nor pans',
    (t) async {
      final h = Harness();
      await h.host(t);
      final a = await t.startGesture(h.point(t, -2, 2), pointer: 1);
      await a.moveTo(h.point(t, 1, 2));
      final b = await t.startGesture(h.point(t, 5, 5), pointer: 2);
      await h.flush(t);
      expect(h.commits, hasLength(1));
      final ink = h.engine.document.composite(0).toList();
      final before = await h.screenshot(t);
      await a.moveBy(const Offset(20, 30));
      await b.moveBy(const Offset(40, 30));
      await t.pump();
      expect(
        await h.screenshot(t, 'two-finger-pan-zoom'),
        isNot(orderedEquals(before)),
      );
      await b.up();
      await t.pump();
      final after = await h.screenshot(t);
      await a.moveBy(const Offset(50, 20));
      await t.pump();
      expect(await h.screenshot(t), orderedEquals(after));
      await a.up();
      expect(h.engine.document.composite(0), ink);
      expect(h.commits, hasLength(1));
      await t.runAsync(() => h.editor.call('undo'));
      expect(h.engine.document.composite(0).every((p) => p == 0), isTrue);
      await h.dispose(t);
    },
  );

  testWidgets('margin and outer edge never turn one finger into a pan', (
    t,
  ) async {
    final h = Harness();
    await h.host(t);
    final top = t.getTopLeft(find.byKey(const Key('pixel-canvas')));
    final outside = await t.startGesture(top + const Offset(5, 5));
    await outside.moveTo(h.point(t, 4, 4));
    await outside.up();
    expect(h.commits, isEmpty);
    final a = await t.startGesture(h.point(t, 15, 3));
    await a.moveTo(top + const Offset(319, 160));
    await a.up();
    await h.flush(t);
    expect((h.commits.last['points'] as List).last[0], 15);
    await t.tapAt(h.point(t, 4, 4));
    await h.flush(t);
    expect(h.commits.last['points'], [
      [4, 4],
    ], reason: 'Viewport did not move');
    await h.dispose(t);
  });

  testWidgets(
    'stylus draws repeats, cancellation leaves no ink, picker wraps',
    (t) async {
      final h = Harness();
      await h.host(t);
      final canceled = await t.startGesture(h.point(t, -1, -1));
      await canceled.moveTo(h.point(t, 1, 1));
      await canceled.cancel();
      expect(h.commits, isEmpty);
      expect(h.engine.document.composite(0).every((p) => p == 0), isTrue);
      final stylus = await t.startGesture(
        h.point(t, -1, -1),
        kind: ui.PointerDeviceKind.stylus,
      );
      await stylus.up();
      await h.flush(t);
      expect(h.engine.document.composite(0)[63], 0x80ff0000);
      await h.host(t, tool: 'eyedropper');
      await t.tapAt(h.point(t, 15, 15));
      expect(h.picks, [0x80ff0000]);
      expect(h.commits, hasLength(1));
      await h.dispose(t);
    },
  );

  testWidgets('wrapped eraser preview is the actual transparent result', (
    t,
  ) async {
    final h = Harness();
    h.engine.stroke({
      'tool': 'rectangle',
      'filled': true,
      'color': 0xff2080dd,
      'points': [
        [0, 0],
        [7, 7],
      ],
    });
    await h.host(t, tool: 'eraser', size: 3);
    final g = await t.startGesture(h.point(t, -1, 2));
    await g.moveTo(h.point(t, 1, 2));
    await t.pump(const Duration(milliseconds: 100));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump();
    final preview = await h.screenshot(t, 'eraser-live');
    await g.up();
    await h.flush(t);
    expect(await h.screenshot(t, 'eraser-committed'), orderedEquals(preview));
    expect(h.engine.document.composite(0)[2 * 8 + 7], 0);
    expect(h.engine.document.composite(0)[2 * 8], 0);
    await h.dispose(t);
  });
}
