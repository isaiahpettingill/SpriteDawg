import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/main.dart';

Map<String, dynamic> snapshot({bool dirty = true}) => {
  'width': 32,
  'height': 32,
  'depth': 32,
  'frame': 0,
  'layer': 0,
  'dirty': dirty,
  'canUndo': dirty,
  'canRedo': false,
  'palette': [0xff000000, 0xffffffff],
  'frames': [
    {'duration': 100},
  ],
  'layers': [
    {
      'name': 'Layer 1',
      'visible': true,
      'opacity': 255,
      'editable': true,
      'background': false,
    },
  ],
  'tags': [],
  'userData': {},
};

void main() {
  test(
    'Pixel-only strokes notify canvas and thumbnails, not all controls',
    () async {
      final editor = Editor(transport: (_, _) async => snapshot());
      await editor.call('init');
      var controls = 0, images = 0, thumbnails = 0;
      editor.addListener(() => controls++);
      editor.imageChanges.addListener(() => images++);
      editor.documentChanges.addListener(() => thumbnails++);
      await editor.call('stroke');
      await editor.call('stroke');
      expect(controls, 0);
      expect(images, 2);
      expect(thumbnails, 2);
      editor.dispose();
    },
  );

  test(
    'First edit still updates dirty and undo controls; file operations notify',
    () async {
      var dirty = false;
      final editor = Editor(transport: (_, _) async => snapshot(dirty: dirty));
      await editor.call('init');
      var controls = 0;
      editor.addListener(() => controls++);
      dirty = true;
      await editor.call('stroke');
      expect(controls, 1);
      expect(editor.dirty, isTrue);
      expect(editor.canUndo, isTrue);
      await editor.call('save');
      expect(controls, 3);
      editor.dispose();
    },
  );

  test(
    'Rapid consecutive strokes wait for decode instead of being dropped',
    () async {
      final first = Completer<void>();
      final calls = <int>[];
      final editor = Editor(
        transport: (_, args) async {
          final id = args!['id'] as int;
          calls.add(id);
          if (id == 1) await first.future;
          return snapshot();
        },
      );
      final a = editor.call('stroke', {'id': 1});
      expect(editor.busyDrawing, isTrue);
      final b = editor.call('stroke', {'id': 2});
      expect(calls, [1]);
      first.complete();
      expect(await a, isTrue);
      expect(await b, isTrue);
      expect(calls, [1, 2]);
      expect(editor.busyDrawing, isFalse);
      editor.dispose();
    },
  );

  test('Drawing during a file operation stays blocked', () async {
    final pending = Completer<Map<String, dynamic>?>();
    final editor = Editor(transport: (_, _) => pending.future);
    final opening = editor.call('open');
    expect(editor.busy, isTrue);
    expect(editor.busyDrawing, isFalse);
    expect(await editor.call('stroke'), isFalse);
    pending.complete(snapshot());
    await opening;
    editor.dispose();
  });

  testWidgets(
    'Unchanged stroke metadata preserves the surrounding screen widget',
    (tester) async {
      final editor = Editor(transport: (_, _) async => snapshot());
      await tester.pumpWidget(PocketPixelApp(editor: editor));
      await tester.pumpAndSettle();
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      await editor.call('stroke');
      await tester.pumpAndSettle();
      expect(
        identical(
          scaffold,
          tester.widget<Scaffold>(find.byType(Scaffold).first),
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
