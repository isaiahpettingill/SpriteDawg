import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/main.dart';
import 'package:spritedawg/visual_tag_editor.dart';
import 'package:spritedawg/engine/editor_engine.dart';
import 'package:spritedawg/engine/document.dart';

EditorEngine fixture() {
  final engine = EditorEngine()..document = SpriteDocument.create(4, 4);
  for (var i = 1; i < 6; i++) {
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
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [
    const Size(320, 568),
    const Size(568, 320),
    const Size(1024, 768),
    const Size(1440, 900),
  ]) {
    testWidgets(
      'Visual tags fit ${size.width}x${size.height} with visible frame strip',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final engine = fixture();
        await tester.pumpWidget(PocketPixelApp(editor: uiEditor(engine, [])));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tags').first);
        await tester.pumpAndSettle();
        expect(find.byType(VisualTagEditor), findsOneWidget);
        expect(find.byKey(const Key('tag-frame-strip')), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const Key('tag-frame-strip'))).height,
          greaterThanOrEqualTo(40),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Tag tap browses first frame, visual range edit preserves metadata',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = fixture(), calls = <String>[];
      await tester.pumpWidget(PocketPixelApp(editor: uiEditor(engine, calls)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tags').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grass tiles'));
      await tester.pumpAndSettle();
      expect(engine.frame, 1);
      expect(engine.dirty, isFalse);
      await tester.ensureVisible(find.byKey(const Key('tag-start')));
      await tester.tap(find.byKey(const Key('tag-start')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tag-frame-0')));
      await tester.pumpAndSettle();
      expect(find.text('Start 1'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('tag-name')),
        'Grass variants',
      );
      await tester.tap(find.byKey(const Key('save-tag')));
      await tester.pumpAndSettle();
      final tag = engine.document.tags[0];
      expect(tag.name, 'Grass variants');
      expect(tag.from, 0);
      expect(tag.to, 3);
      expect(tag.direction, 3);
      expect(tag.repeat, 2);
      expect(tag.data!.text, '{"kind":"ground"}');
      expect(tag.data!.color, 0xffaabbcc);
      expect(calls.where((m) => m == 'thumbnails'), isNotEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Duplicate retains tag name and metadata, edit copies independently',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = fixture();
      await tester.pumpWidget(PocketPixelApp(editor: uiEditor(engine, [])));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tags').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grass tiles'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('duplicate-tag')));
      await tester.pumpAndSettle();
      expect(engine.document.tags, hasLength(2));
      expect(engine.document.tags.last.name, 'Grass tiles');
      await tester.enterText(find.byKey(const Key('tag-name')), 'Flowers');
      await tester.pump();
      await tester.tap(find.byKey(const Key('save-tag')));
      await tester.pumpAndSettle();
      expect(engine.document.tags.first.name, 'Grass tiles');
      expect(engine.document.tags.last.name, 'Flowers');
      expect(
        engine.document.tags.last.data!.text,
        engine.document.tags.first.data!.text,
      );
    },
  );
  testWidgets(
    'New tag defaults to current frame and inline name input does not choose tools',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = fixture()..frame = 4;
      await tester.pumpWidget(PocketPixelApp(editor: uiEditor(engine, [])));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tags').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-tag')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('tag-name')));
      await tester.enterText(find.byKey(const Key('tag-name')), 'bridge');
      await tester.tap(find.byKey(const Key('save-tag')));
      await tester.pumpAndSettle();
      expect(engine.document.tags.last.name, 'bridge');
      expect(engine.document.tags.last.from, 4);
      expect(engine.document.tags.last.to, 4);
      expect(find.textContaining('Pencil'), findsWidgets);
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
