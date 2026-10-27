import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/engine/editor_engine.dart';

Map<String, dynamic> _state(int frame, {int count = 3}) => {
  'width': 1,
  'height': 1,
  'frame': frame,
  'frames': List.generate(count, (_) => {'duration': 100}),
};
Map<String, dynamic> _preview(int frame) => {
  'frame': frame,
  'width': 1,
  'height': 1,
  'pixels': Uint8List.fromList([frame * 50, 20, 30, 128]),
};
Future<void> _waitNext(Editor e) async {
  if (e.next != null) return;
  final done = Completer<void>();
  void changed() {
    if (e.next != null && !done.isCompleted) done.complete();
  }

  e.viewChanges.addListener(changed);
  try {
    await done.future.timeout(const Duration(seconds: 5));
  } finally {
    e.viewChanges.removeListener(changed);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Full-resolution frameImage is read-only and validates frame identity',
    () {
      final e = EditorEngine();
      e.invoke('new', {'width': 2, 'height': 1});
      e.invoke('stroke', {
        'tool': 'pencil',
        'color': 0x804488aa,
        'points': [
          [0, 0],
        ],
      });
      e.invoke('edit', {'action': 'duplicateFrame'});
      final before = e.encode();
      final frame = e.frame, dirty = e.dirty;
      final state = e.state();
      final image = e.invoke('frameImage', {'frame': 0});
      expect(image['frame'], 0);
      expect(image['width'], 2);
      expect(image['height'], 1);
      expect((image['pixels'] as Uint8List).length, 8);
      expect(e.encode(), before);
      expect(e.frame, frame);
      expect(e.dirty, dirty);
      expect(e.state()['canUndo'], state['canUndo']);
      expect(e.state()['canRedo'], state['canRedo']);
      for (final value in [-1, 2, 0.5, '0', null]) {
        expect(
          () => e.invoke('frameImage', {'frame': value}),
          throwsFormatException,
        );
        expect(e.encode(), before);
      }
    },
  );

  test(
    'Slide cache is lazy, reused across state refresh and separate from stroke signals',
    () async {
      var calls = 0, frame = 0, imageSignals = 0;
      final e = Editor(
        transport: (method, args) async {
          if (method == 'frameImage') {
            calls++;
            return _preview(args!['frame'] as int);
          }
          if (method == 'select') frame = args!['frame'] as int;
          return _state(frame);
        },
      );
      addTearDown(e.dispose);
      await e.call('init');
      expect(calls, 0);
      e.imageChanges.addListener(() => imageSignals++);
      e.setSlideViewEnabled(true);
      await _waitNext(e);
      expect(calls, 1);
      expect(imageSignals, 0);
      final pixels = await e.next!.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      expect(pixels!.buffer.asUint8List(), [50, 20, 30, 128]);
      await e.call('state');
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      await e.call('select', {'frame': 2});
      expect(e.next, isNull);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1); // Last frame never wraps to first.
      e.setSlideViewEnabled(false);
      await e.call('select', {'frame': 0});
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
    },
  );

  test(
    'Stale next-frame responses and disabled-view responses are discarded',
    () async {
      final pending = <Completer<Map<String, dynamic>?>>[];
      var frame = 0;
      final e = Editor(
        transport: (method, args) async {
          if (method == 'frameImage') {
            final result = Completer<Map<String, dynamic>?>();
            pending.add(result);
            return result.future;
          }
          if (method == 'select') frame = args!['frame'] as int;
          return _state(frame);
        },
      );
      addTearDown(e.dispose);
      await e.call('init');
      e.setSlideViewEnabled(true);
      await Future<void>.delayed(Duration.zero);
      expect(pending, hasLength(1));
      await e.call('select', {'frame': 1});
      pending[0].complete(_preview(1));
      await Future<void>.delayed(Duration.zero);
      expect(e.next, isNull);
      expect(pending, hasLength(2));
      e.setSlideViewEnabled(false);
      pending[1].complete(_preview(2));
      await Future<void>.delayed(Duration.zero);
      expect(e.next, isNull);
    },
  );

  test(
    'Enabling Slide during a failed operation still loads when idle',
    () async {
      final gate = Completer<void>();
      final e = Editor(
        transport: (method, args) async {
          if (method == 'frameImage') return _preview(1);
          if (method == 'open') {
            await gate.future;
            throw StateError('open failed');
          }
          return _state(0);
        },
      );
      addTearDown(e.dispose);
      await e.call('init');
      final opening = e.call('open');
      e.setSlideViewEnabled(true);
      await Future<void>.delayed(Duration.zero);
      expect(e.next, isNull);
      gate.complete();
      expect(await opening, isFalse);
      await _waitNext(e);
      expect(e.next, isNotNull);
    },
  );

  test(
    'Failed neighbor preview does not change document or editing availability',
    () async {
      final e = Editor(
        transport: (method, args) async {
          if (method == 'frameImage') throw StateError('preview unavailable');
          return _state(0);
        },
      );
      addTearDown(e.dispose);
      await e.call('init');
      final state = e.state;
      e.setSlideViewEnabled(true);
      await Future<void>.delayed(Duration.zero);
      expect(e.state, same(state));
      expect(e.error, isNull);
      expect(e.busy, isFalse);
      expect(e.next, isNull);
      expect(await e.call('stroke'), isTrue);
    },
  );
}
