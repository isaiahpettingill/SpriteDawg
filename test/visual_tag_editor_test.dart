import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/main.dart';
import 'package:spritedawg/pixel_canvas.dart';
import 'package:spritedawg/visual_tag_editor.dart';
import 'package:spritedawg/engine/editor_engine.dart';
import 'package:spritedawg/engine/editor_sessions.dart';
import 'package:spritedawg/engine/document.dart';

EditorEngine fixture({int frames = 6}) {
  final engine = EditorEngine()..document = SpriteDocument.create(4, 4);
  for (var i = 1; i < frames; i++) {
    engine.edit({'action': 'addFrame'});
  }
  engine.frame = 0;
  engine.edit({
    'action': 'addTag',
    'name': 'Grass tiles',
    'from': 1,
    'to': 3,
    'direction': 3,
    'repeat': 2,
  });
  engine.document.tags[0].data = UserData(
    text: '{"kind":"ground"}',
    color: 0xffaabbcc,
  );
  engine.saved();
  return engine;
}

Editor uiEditor(EditorEngine engine, List<String> calls) => Editor(
  transport: (method, args) async {
    calls.add(method);
    if (method == 'thumbnails') return {'thumbnails': []};
    final result = engine.invoke(method, args ?? {});
    result.remove('pixels');
    result.remove('previousPixels');
    return {
      ...result,
      'documents': [
        {
          'id': 1,
          'title': 'Tiles.aseprite',
          'dirty': engine.dirty,
          'active': true,
        },
      ],
      'documentId': 1,
    };
  },
);

Future<void> openTags(
  WidgetTester tester,
  Editor editor, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(PocketPixelApp(editor: editor));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Tags').first);
  await tester.pumpAndSettle();
}

Future<void> tagOption(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('tag-options')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(568, 320),
    const Size(1024, 768),
    const Size(1440, 900),
  ]) {
    testWidgets('Visual tags retain canvas and frame strip at $size', (
      tester,
    ) async {
      await openTags(tester, uiEditor(fixture(), []), size: size);
      expect(find.byType(VisualTagEditor), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('tag-frame-strip'))).height,
        greaterThanOrEqualTo(40),
      );
      expect(tester.getSize(find.byType(PixelCanvas)).height, greaterThan(20));
      expect(find.byKey(const Key('tag-name')), findsNothing);
      expect(find.text('All frames'), findsOneWidget);
      expect(find.text('Browse'), findsNothing);
      expect(find.byTooltip('Play animation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Frame taps only preview; handle release commits one undo and preserves metadata',
    (tester) async {
      final engine = fixture(), calls = <String>[];
      final editor = uiEditor(engine, calls);
      await openTags(tester, editor);
      await tester.tap(find.text('Grass tiles'));
      await tester.pumpAndSettle();
      expect(engine.frame, 1);
      expect(engine.dirty, isFalse);
      await tester.tap(find.byKey(const Key('tag-frame-0')));
      await tester.pumpAndSettle();
      expect(engine.frame, 0);
      expect(engine.document.tags[0].from, 1);
      calls.clear();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('tag-start-handle'))),
      );
      await gesture.moveBy(const Offset(-76, 0));
      await tester.pump();
      expect(engine.document.tags[0].from, 1);
      expect(calls.where((m) => m == 'edit'), isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(engine.document.tags[0].from, 0);
      expect(calls.where((m) => m == 'edit'), hasLength(1));
      await editor.call('undo');
      await tester.pumpAndSettle();
      expect(engine.document.tags[0].from, 1);
      expect(engine.document.tags[0].to, 3);
      await tagOption(tester, 'Rename tag');
      await tester.enterText(
        find.byKey(const Key('tag-name')),
        'Grass variants',
      );
      await tester.tap(find.byKey(const Key('save-tag')));
      await tester.pumpAndSettle();
      final tag = engine.document.tags[0];
      expect(tag.name, 'Grass variants');
      expect(tag.direction, 3);
      expect(tag.repeat, 2);
      expect(tag.data!.text, '{"kind":"ground"}');
      expect(tag.data!.color, 0xffaabbcc);
      expect(find.byKey(const Key('tag-name')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Cancelled and interrupted drags do not change the document', (
    tester,
  ) async {
    final engine = fixture(), calls = <String>[];
    final editor = uiEditor(engine, calls);
    await openTags(tester, editor);
    await tester.tap(find.text('Grass tiles'));
    await tester.pumpAndSettle();
    calls.clear();
    var gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('tag-start-handle'))),
    );
    await gesture.moveBy(const Offset(-76, 0));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(engine.document.tags[0].from, 1);
    expect(calls.where((m) => m == 'edit'), isEmpty);
    gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('tag-start-handle'))),
    );
    await gesture.moveBy(const Offset(-76, 0));
    await editor.call('undo');
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(engine.document.tags, isEmpty);
    expect(calls.where((m) => m == 'edit'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Pending names survive panel changes, Cancel discards only the name',
    (tester) async {
      final engine = fixture();
      await openTags(tester, uiEditor(engine, []));
      await tester.tap(find.text('Grass tiles'));
      await tester.pumpAndSettle();
      await tagOption(tester, 'Rename tag');
      await tester.enterText(
        find.byKey(const Key('tag-name')),
        'Unfinished name',
      );
      await tester.tap(find.text('Frames').first);
      await tester.pumpAndSettle();
      expect(engine.document.tags[0].name, 'Grass tiles');
      await tester.tap(find.text('Tags').first);
      await tester.pumpAndSettle();
      expect(find.text('Unfinished name'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancel-tag')));
      await tester.pumpAndSettle();
      expect(engine.document.tags[0].name, 'Grass tiles');
      expect(find.byKey(const Key('tag-name')), findsNothing);
    },
  );

  for (final size in [const Size(320, 568), const Size(390, 844)]) {
    testWidgets(
      'Rename with keyboard keeps artwork and Done/Cancel visible at $size',
      (tester) async {
        await openTags(tester, uiEditor(fixture(), []), size: size);
        await tester.tap(find.text('Grass tiles'));
        await tester.pumpAndSettle();
        await tagOption(tester, 'Rename tag');
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(PixelCanvas)).height,
          greaterThan(20),
        );
        expect(
          tester.getSize(find.byKey(const Key('tag-frame-strip'))).height,
          greaterThan(24),
        );
        expect(find.byKey(const Key('tag-name')).hitTestable(), findsOneWidget);
        expect(find.byKey(const Key('save-tag')).hitTestable(), findsOneWidget);
        expect(
          find.byKey(const Key('cancel-tag')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'New tag starts at current frame, is staged until Done, and can be cancelled',
    (tester) async {
      final engine = fixture()..frame = 4;
      await openTags(tester, uiEditor(engine, []));
      await tester.tap(find.byKey(const Key('add-tag')));
      await tester.pumpAndSettle();
      expect(engine.document.tags, hasLength(1));
      await tester.drag(
        find.byKey(const Key('tag-end-handle')),
        const Offset(76, 0),
      );
      await tester.pumpAndSettle();
      expect(engine.document.tags, hasLength(1));
      await tester.enterText(find.byKey(const Key('tag-name')), 'bridge');
      await tester.tap(find.byKey(const Key('save-tag')));
      await tester.pumpAndSettle();
      expect(engine.document.tags.last.name, 'bridge');
      expect(engine.document.tags.last.from, 4);
      expect(engine.document.tags.last.to, 5);
      expect(find.textContaining('Pencil'), findsWidgets);
      await tester.tap(find.byKey(const Key('add-tag')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancel-tag')));
      await tester.pumpAndSettle();
      expect(engine.document.tags, hasLength(2));
    },
  );

  testWidgets('Duplicate label retains metadata without copying frames', (
    tester,
  ) async {
    final engine = fixture();
    await openTags(tester, uiEditor(engine, []));
    await tester.tap(find.text('Grass tiles'));
    await tester.pumpAndSettle();
    await tagOption(tester, 'Duplicate tag label');
    expect(engine.document.tags, hasLength(2));
    expect(engine.document.frames, hasLength(6));
    await tagOption(tester, 'Rename tag');
    await tester.enterText(find.byKey(const Key('tag-name')), 'Flowers');
    await tester.tap(find.byKey(const Key('save-tag')));
    await tester.pumpAndSettle();
    expect(engine.document.tags.first.name, 'Grass tiles');
    expect(engine.document.tags.last.name, 'Flowers');
    expect(
      engine.document.tags.last.data!.text,
      engine.document.tags.first.data!.text,
    );
  });

  testWidgets('Direction and repeat stay in options and preserve range/data', (
    tester,
  ) async {
    final engine = fixture();
    await openTags(tester, uiEditor(engine, []));
    await tester.tap(find.text('Grass tiles'));
    await tester.pumpAndSettle();
    await tagOption(tester, 'Direction and repeat…');
    await tester.enterText(find.byKey(const Key('tag-repeat')), '7');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(engine.document.tags[0].repeat, 7);
    expect(engine.document.tags[0].direction, 3);
    expect(engine.document.tags[0].from, 1);
    expect(engine.document.tags[0].data!.text, '{"kind":"ground"}');
  });

  testWidgets('One Play commits the pending tag before playback starts', (
    tester,
  ) async {
    final engine = fixture()..frame = 4;
    await openTags(tester, uiEditor(engine, []));
    await tester.tap(find.byKey(const Key('add-tag')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tag-name')), 'Still tile');
    await tester.tap(find.byTooltip('Play animation'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(engine.document.tags.last.name, 'Still tile');
    expect(engine.frame, 4);
    expect(find.byTooltip('Stop animation'), findsOneWidget);
    await tester.tap(find.byTooltip('Stop animation'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Long timelines allow manual scroll then reveal the newly selected frame',
    (tester) async {
      final engine = fixture(frames: 80)..frame = 69;
      engine.document.tags[0].name =
          'A deliberately long tile variant collection';
      final editor = uiEditor(engine, []);
      await openTags(tester, editor, size: const Size(320, 568));
      expect(
        find.byKey(const Key('tag-frame-69')).hitTestable(),
        findsOneWidget,
      );
      final list = tester.widget<ListView>(
        find.byKey(const Key('tag-frame-strip')),
      );
      final before = list.controller!.offset;
      await tester.drag(
        find.byKey(const Key('tag-frame-strip')),
        const Offset(180, 0),
      );
      await tester.pumpAndSettle();
      final manual = list.controller!.offset;
      expect(manual, lessThan(before));
      await editor.call('select', {'frame': 69});
      await tester.pumpAndSettle();
      expect(list.controller!.offset, manual);
      await editor.call('select', {'frame': 79});
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('tag-frame-79')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Shift-click selects a range and F2 starts explicit rename', (
    tester,
  ) async {
    final engine = fixture();
    await openTags(tester, uiEditor(engine, []), size: const Size(1440, 900));
    await tester.tap(find.text('Grass tiles'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.byKey(const Key('tag-frame-5')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(engine.document.tags[0].from, 1);
    expect(engine.document.tags[0].to, 5);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tag-name')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('tag-name')), 'bridge');
    expect(engine.document.tags[0].name, 'Grass tiles');
    await tester.tap(find.byKey(const Key('cancel-tag')));
    await tester.pumpAndSettle();
  });
  testWidgets('Holding a range handle without dragging does not resize it', (
    tester,
  ) async {
    final engine = fixture(frames: 80), calls = <String>[];
    await openTags(tester, uiEditor(engine, calls));
    await tester.tap(find.text('Grass tiles'));
    await tester.pumpAndSettle();
    final strip = tester.widget<ListView>(
      find.byKey(const Key('tag-frame-strip')),
    );
    strip.controller!.jumpTo(76);
    await tester.pump();
    calls.clear();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('tag-start-handle'))),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(engine.document.tags[0].from, 1);
    expect(calls.where((m) => m == 'edit'), isEmpty);
  });

  testWidgets(
    'Dragging beyond the viewport scrolls and still commits only once',
    (tester) async {
      final engine = fixture(frames: 80), calls = <String>[];
      await openTags(tester, uiEditor(engine, calls));
      await tester.tap(find.text('Grass tiles'));
      await tester.pumpAndSettle();
      calls.clear();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('tag-end-handle'))),
      );
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump(const Duration(milliseconds: 400));
      expect(engine.document.tags[0].to, 3);
      final list = tester.widget<ListView>(
        find.byKey(const Key('tag-frame-strip')),
      );
      expect(list.controller!.offset, greaterThan(0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(engine.document.tags[0].to, greaterThan(4));
      expect(calls.where((m) => m == 'edit'), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Hidden pending names save to the source document; whole-section transfer remains intact',
    (tester) async {
      final sessions = EditorSessions();
      final source = sessions.add(fixture().document, title: 'Source');
      final destination = sessions.add(
        SpriteDocument.create(4, 4),
        title: 'Destination',
      );
      sessions.select(source.id);
      final editor = Editor(
        transport: (method, args) async {
          if (method == 'thumbnails') return {'thumbnails': []};
          switch (method) {
            case 'selectDocument':
              sessions.select(args!['id'] as int);
            case 'copyTag':
              sessions.copyTag(args!['index'] as int);
            case 'pasteTag':
              if (args?['asNew'] == true) {
                sessions.pasteTagAsNew();
              } else {
                sessions.pasteTag(after: args?['after'] as int?);
              }
            case 'clearTagClipboard':
              sessions.clearClipboard();
            default:
              sessions.active.engine.invoke(method, args ?? {});
          }
          return sessions.state()
            ..remove('pixels')
            ..remove('previousPixels');
        },
      );
      await openTags(tester, editor, size: const Size(1440, 900));
      await tester.tap(find.text('Grass tiles'));
      await tester.pumpAndSettle();
      await tagOption(tester, 'Rename tag');
      await tester.enterText(find.byKey(const Key('tag-name')), 'Ground');
      await tester.tap(find.text('Frames').first);
      await tester.pumpAndSettle();
      expect(source.engine.document.tags[0].name, 'Grass tiles');
      await tester.tap(find.text('Destination'));
      await tester.pumpAndSettle();
      expect(source.engine.document.tags[0].name, 'Ground');
      expect(destination.engine.document.tags, isEmpty);
      await tester.tap(find.textContaining('Source').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tags').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ground'));
      await tester.pumpAndSettle();
      await tagOption(tester, 'Copy frames + tag');
      await tester.tap(find.text('Destination'));
      await tester.pumpAndSettle();
      await tagOption(tester, 'Paste after current frame');
      expect(destination.engine.document.frames, hasLength(4));
      expect(destination.engine.document.tags.single.name, 'Ground');
      expect(
        destination.engine.document.tags.single.data!.text,
        '{"kind":"ground"}',
      );
      expect(source.engine.document.frames, hasLength(6));
      await editor.call('undo');
      await tester.pumpAndSettle();
      expect(destination.engine.document.frames, hasLength(1));
      expect(destination.engine.document.tags, isEmpty);
      expect(source.engine.document.tags.single.name, 'Ground');
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Thumbnail calls batch, preserve editor state, and cache across selection',
    () async {
      var batches = 0, frame = 0;
      final editor = Editor(
        transport: (method, args) async {
          if (method == 'thumbnails') {
            batches++;
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return {
              'thumbnails': [
                for (final f in args!['frames'] as List)
                  {
                    'frame': f,
                    'width': 1,
                    'height': 1,
                    'pixels': Uint8List.fromList([200, 100, 50, 128]),
                  },
              ],
            };
          }
          if (method == 'select') frame = args!['frame'] as int;
          return {
            'width': 1,
            'height': 1,
            'frame': frame,
            'layer': 0,
            'dirty': false,
            'frames': [{}, {}],
          };
        },
      );
      await editor.call('init');
      final one = editor.thumbnail(0), two = editor.thumbnail(1);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final duplicate = editor.thumbnail(0);
      final images = await Future.wait([one, two, duplicate]);
      expect(batches, 1);
      expect(editor.frame, 0);
      expect(editor.dirty, isFalse);
      for (final image in images) {
        expect(image, isNotNull);
        image!.dispose();
      }
      await editor.call('select', {'frame': 1});
      final cached = await editor.thumbnail(0);
      cached!.dispose();
      expect(batches, 1);
      await editor.edit('renameLayer', {'name': 'New'});
      final changed = await editor.thumbnail(0);
      changed!.dispose();
      expect(batches, 2);
      editor.dispose();
    },
  );
  test(
    'Stale thumbnail request never replaces a newer document preview',
    () async {
      final response = Completer<Map<String, dynamic>?>();
      final editor = Editor(
        transport: (method, args) async => method == 'thumbnails'
            ? response.future
            : {
                'width': 1,
                'height': 1,
                'frame': 0,
                'layer': 0,
                'frames': [{}],
              },
      );
      await editor.call('init');
      final pending = editor.thumbnail(0);
      await Future<void>.delayed(Duration.zero);
      await editor.call('new', {'width': 1, 'height': 1});
      response.complete({
        'thumbnails': [
          {
            'frame': 0,
            'width': 1,
            'height': 1,
            'pixels': Uint8List.fromList([255, 0, 0, 255]),
          },
        ],
      });
      final ui.Image? image = await pending;
      expect(image, isNull);
      editor.dispose();
    },
  );
}
