import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spritedawg/editor.dart';
import 'package:spritedawg/main.dart';
import 'package:spritedawg/pixel_canvas.dart';
import 'package:spritedawg/rgba_image.dart';

Map<String, dynamic> state({bool dirty = false}) => {
  'width': 32,
  'height': 32,
  'depth': 32,
  'frame': 0,
  'layer': 0,
  'dirty': dirty,
  'canUndo': false,
  'canRedo': false,
  'recoveryAvailable': false,
  'palette': [0xff000000, 0xffffffff, 0xffff0000],
  'layers': [
    {
      'name': 'Layer 1',
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
  'userData': {'sprite': '', 'layer': '', 'cel': ''},
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Transport errors preserve document and release busy guard', () async {
    var fail = false;
    final e = Editor(
      transport: (method, args) async {
        if (fail) {
          throw PlatformException(
            code: 'unsafe',
            message: 'Unsupported layer blend',
          );
        }
        return state();
      },
    );
    expect(await e.call('init'), isTrue);
    fail = true;
    expect(await e.call('open'), isFalse);
    expect(e.width, 32);
    expect(e.error, 'Unsupported layer blend');
    expect(e.busy, isFalse);
    e.dispose();
  });
  test(
    'Native RGBA bytes are decoded without channel color conversion',
    () async {
      final e = Editor(
        transport: (m, a) async => {
          ...state(),
          'width': 1,
          'height': 1,
          'pixels': Uint8List.fromList([255, 0, 0, 255]),
        },
      );
      await e.call('init');
      expect(e.image?.width, 1);
      final bytes = await e.image!.toByteData();
      expect(bytes!.getUint8(0), 255);
      e.dispose();
    },
  );
  test('Straight-alpha RGBA composites retain translucent colors', () async {
    final pixels = Uint8List.fromList([
      for (final alpha in [1, 17, 128, 254]) ...[200, 100, 50, alpha],
    ]);
    final e = Editor(
      transport: (m, a) async => {
        ...state(),
        'width': 4,
        'height': 1,
        'pixels': pixels,
        'previousPixels': pixels,
      },
    );
    await e.call('init');
    for (final image in [e.image!, e.previous!]) {
      final bytes = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      expect(bytes!.buffer.asUint8List(), pixels);
    }
    e.dispose();
  });
  test('RGBA image helper rejects invalid dimensions and lengths', () async {
    for (final dimensions in [
      (0, 1),
      (1, 0),
      (-1, 1),
      (65536, 1),
      (2049, 2048),
    ]) {
      await expectLater(
        decodeStraightRgba(
          Uint8List(4),
          width: dimensions.$1,
          height: dimensions.$2,
        ),
        throwsFormatException,
      );
    }
    await expectLater(
      decodeStraightRgba(Uint8List(3), width: 1, height: 1),
      throwsFormatException,
    );
  });
  Future<void> canvas(
    WidgetTester tester,
    Editor e,
    void Function(String, List<Offset>) onStroke, {
    String tool = 'pencil',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PixelCanvas(
            editor: e,
            tool: tool,
            color: 0xff000000,
            brush: 1,
            grid: false,
            onion: false,
            fitToken: 0,
            onPick: (_) {},
            onStroke: onStroke,
          ),
        ),
      ),
    );
  }

  testWidgets('A completed drag commits exactly one stroke', (tester) async {
    final e = Editor();
    final strokes = <List<Offset>>[];
    await canvas(tester, e, (_, p) => strokes.add(p));
    final center = tester.getCenter(find.byKey(const Key('pixel-canvas')));
    final finger = await tester.startGesture(center);
    await finger.moveBy(const Offset(24, 0));
    await finger.up();
    expect(strokes, hasLength(1));
    expect(strokes.single.length, greaterThan(1));
    e.dispose();
  });
  testWidgets(
    'Adding a second finger preserves the stroke and pans without drawing',
    (tester) async {
      final e = Editor();
      var count = 0;
      await canvas(tester, e, (_, p) => count++);
      final center = tester.getCenter(find.byKey(const Key('pixel-canvas')));
      final one = await tester.startGesture(center, pointer: 1);
      await one.moveBy(const Offset(10, 0));
      final two = await tester.startGesture(
        center + const Offset(40, 0),
        pointer: 2,
      );
      await two.moveBy(const Offset(10, 10));
      await two.up();
      await one.moveBy(const Offset(30, 0));
      await one.up();
      expect(count, 1);
      await tester.tapAt(center);
      expect(count, 2);
      e.dispose();
    },
  );
  for (final continuousTool in ['spray', 'airbrush']) {
    testWidgets('$continuousTool accumulates while held, then stops on pan', (
      tester,
    ) async {
      final e = Editor();
      final strokes = <List<Offset>>[];
      await canvas(
        tester,
        e,
        (_, points) => strokes.add(points),
        tool: continuousTool,
      );
      final center = tester.getCenter(find.byKey(const Key('pixel-canvas')));
      final one = await tester.startGesture(center, pointer: 1);
      await tester.pump(const Duration(milliseconds: 220));
      final two = await tester.startGesture(
        center + const Offset(40, 0),
        pointer: 2,
      );
      expect(strokes, hasLength(1));
      expect(strokes.single.length, greaterThanOrEqualTo(5));
      expect(strokes.single.toSet(), hasLength(1));
      await tester.pump(const Duration(milliseconds: 200));
      await two.up();
      await one.up();
      expect(strokes, hasLength(1));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(const SizedBox());
      e.dispose();
    });
  }
  testWidgets('Canceled pointer and pan never commit pixels', (tester) async {
    final e = Editor();
    var count = 0;
    await canvas(tester, e, (_, p) => count++);
    final center = tester.getCenter(find.byKey(const Key('pixel-canvas')));
    final finger = await tester.startGesture(center);
    await finger.cancel();
    expect(count, 0);
    await canvas(tester, e, (_, p) => count++, tool: 'pan');
    await tester.drag(
      find.byKey(const Key('pixel-canvas')),
      const Offset(40, 20),
    );
    expect(count, 0);
    e.dispose();
  });
  testWidgets('Phone UI opens layers and exposes working frame controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      Editor.channel,
      (call) async {
        calls.add(call);
        return state();
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        Editor.channel,
        null,
      ),
    );
    await tester.pumpWidget(
      PocketPixelApp(
        editor: Editor(
          transport: (method, args) =>
              Editor.channel.invokeMapMethod<String, dynamic>(method, args),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('SpriteDawg'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Layers'));
    await tester.pumpAndSettle();
    expect(find.text('Layer 1'), findsOneWidget);
    await tester.tap(find.text('Frames'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add blank frame'));
    await tester.pumpAndSettle();
    expect(
      calls.any(
        (c) =>
            c.method == 'edit' && (c.arguments as Map)['action'] == 'addFrame',
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('Closed drafts remain available without a startup prompt', (
    tester,
  ) async {
    final calls = <String>[];
    final editor = Editor(
      transport: (method, args) async {
        calls.add(method);
        return {
          ...state(),
          'recoveryAvailable': method == 'init',
          'drafts': [
            {
              'id': 7,
              'title': 'Hero draft',
              'updatedAt': 0,
              'width': 16,
              'height': 16,
              'frames': 1,
            },
          ],
        };
      },
    );
    await tester.pumpWidget(PocketPixelApp(editor: editor));
    await tester.pumpAndSettle();
    expect(find.text('Internal drafts'), findsNothing);
    expect(calls, ['init']);
    await tester.tap(find.byTooltip('Project and view options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Internal drafts…'));
    await tester.pumpAndSettle();
    expect(find.text('Internal drafts'), findsOneWidget);
    await tester.tap(find.text('Hero draft'));
    await tester.pumpAndSettle();
    expect(calls, ['init', 'flushDrafts', 'listDrafts', 'recover']);
  });
  testWidgets('Recovery failure stays visible with save-copy action', (
    tester,
  ) async {
    final calls = <String>[];
    final editor = Editor(
      transport: (method, args) async {
        calls.add(method);
        return {...state(), 'recoveryError': 'Storage is full'};
      },
    );
    await tester.pumpWidget(PocketPixelApp(editor: editor));
    await tester.pumpAndSettle();
    expect(find.textContaining('Recovery unavailable:'), findsOneWidget);
    await tester.tap(find.text('Save as'));
    await tester.pumpAndSettle();
    expect(calls, contains('saveAs'));
  });
  testWidgets(
    'Changing tools during a held stroke cancels the entire gesture',
    (tester) async {
      final e = Editor();
      var count = 0;
      await canvas(tester, e, (_, p) => count++);
      final center = tester.getCenter(find.byKey(const Key('pixel-canvas')));
      final finger = await tester.startGesture(center);
      await finger.moveBy(const Offset(10, 0));
      await canvas(tester, e, (_, p) => count++, tool: 'eraser');
      await finger.moveBy(const Offset(10, 0));
      await finger.up();
      expect(count, 0);
      await tester.tapAt(center);
      expect(count, 1);
      e.dispose();
    },
  );
  testWidgets('Landscape phone panels retain canvas without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final editor = Editor(transport: (method, args) async => state());
    await tester.pumpWidget(PocketPixelApp(editor: editor));
    await tester.pumpAndSettle();
    for (final label in ['Layers', 'Frames', 'Tags']) {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label in landscape');
      final visibleWorkspace = label == 'Tags'
          ? find.byKey(const Key('tag-frame-strip'))
          : find.byKey(const Key('pixel-canvas'));
      expect(tester.getSize(visibleWorkspace).height, greaterThan(0));
    }
    await tester.tap(find.text('Tags').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pencil'), findsOneWidget);
  });
}

