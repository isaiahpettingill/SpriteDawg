import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/engine/document.dart';
import 'package:spritedawg/engine/editor_engine.dart';
import 'package:spritedawg/frame_panel.dart';
import 'package:spritedawg/main.dart';

Finder get _strip => find.byKey(const Key('frame-strip'));
Finder _card(int index) => find.byKey(Key('frame-card-$index'));

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: _strip, matching: find.byType(Scrollable)).first,
    )
    .position;

void _expectVisible(WidgetTester tester, int index) {
  expect(_card(index).hitTestable(), findsOneWidget);
  final viewport = tester.getRect(_strip);
  final card = tester.getRect(_card(index));
  expect(card.left, greaterThanOrEqualTo(viewport.left - 0.1));
  expect(card.right, lessThanOrEqualTo(viewport.right + 0.1));
}

Widget _panel({
  int frame = 0,
  int count = 1000,
  Object documentId = 1,
  bool busy = false,
  double width = 320,
  int duration = 100,
  ValueChanged<int>? onSelect,
  ValueChanged<int>? onDuration,
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        height: 120,
        child: FramePanel(
          frame: frame,
          durations: List.filled(count, duration),
          documentId: documentId,
          busy: busy,
          onSelect: onSelect ?? (_) {},
          onDuration: onDuration ?? (_) {},
          onAdd: () {},
          onDuplicate: () {},
          onDelete: () {},
        ),
      ),
    ),
  ),
);

EditorEngine _engine({int count = 80, int frame = 60}) {
  final engine = EditorEngine()..document = SpriteDocument.create(4, 4);
  for (var i = 1; i < count; i++) {
    engine.document.frames.add(Frame(cels: [], duration: 100 + i));
  }
  engine.frame = frame;
  return engine;
}

Editor _editor(EditorEngine engine) => Editor(
  transport: (method, args) async {
    if (method == 'thumbnails') return {'thumbnails': []};
    final state = engine.invoke(method, args ?? {});
    state.remove('pixels');
    state.remove('previousPixels');
    return {...state, 'documentId': 1};
  },
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _dismissDuration(WidgetTester tester, String button) async {
  await tester.tap(find.text(button));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 450));
}

void main() {
  testWidgets('Initial reveal reaches a lazy frame near the list end', (
    tester,
  ) async {
    await tester.pumpWidget(_panel(frame: 997));
    await tester.pumpAndSettle();
    _expectVisible(tester, 997);
    expect(_card(0), findsNothing);
    expect(find.text('Hold to time'), findsNothing);
    expect(find.text('100 ms'), findsNothing);
    expect(tester.getSize(_card(997)).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Selection changes reach both ends without overscroll', (
    tester,
  ) async {
    await tester.pumpWidget(_panel(frame: 0));
    await tester.pumpAndSettle();
    _expectVisible(tester, 0);
    await tester.pumpWidget(_panel(frame: 999));
    await tester.pumpAndSettle();
    _expectVisible(tester, 999);
    expect(
      _position(tester).pixels,
      lessThanOrEqualTo(_position(tester).maxScrollExtent),
    );
    await tester.pumpWidget(_panel(frame: 0));
    await tester.pumpAndSettle();
    _expectVisible(tester, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Manual browsing survives unrelated and duration rebuilds', (
    tester,
  ) async {
    await tester.pumpWidget(_panel(frame: 50));
    await tester.pumpAndSettle();
    await tester.drag(_strip, const Offset(-600, 0));
    await tester.pumpAndSettle();
    final browsedOffset = _position(tester).pixels;
    expect(_card(50).hitTestable(), findsNothing);
    await tester.pumpWidget(_panel(frame: 50, busy: true));
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, browsedOffset);
    await tester.pumpWidget(_panel(frame: 50, duration: 250));
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, browsedOffset);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Document switch reveals selection even at the same index', (
    tester,
  ) async {
    await tester.pumpWidget(_panel(frame: 50));
    await tester.pumpAndSettle();
    await tester.drag(_strip, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(_card(50).hitTestable(), findsNothing);
    await tester.pumpWidget(_panel(frame: 50, documentId: 2));
    await tester.pumpAndSettle();
    _expectVisible(tester, 50);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Added and deleted last frames stay visible after list layout', (
    tester,
  ) async {
    await tester.pumpWidget(_panel(frame: 79, count: 80));
    await tester.pumpAndSettle();
    _expectVisible(tester, 79);
    await tester.pumpWidget(_panel(frame: 80, count: 81));
    await tester.pumpAndSettle();
    _expectVisible(tester, 80);
    await tester.pumpWidget(_panel(frame: 79, count: 80));
    await tester.pumpAndSettle();
    _expectVisible(tester, 79);
    await tester.pumpWidget(_panel(frame: 0, count: 1));
    await tester.pumpAndSettle();
    _expectVisible(tester, 0);
    expect(_position(tester).pixels, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Narrowing the viewport retains the selected end frame', (
    tester,
  ) async {
    await tester.pumpWidget(_panel(frame: 999, width: 600));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_panel(frame: 999));
    await tester.pumpAndSettle();
    _expectVisible(tester, 999);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Frame timing remains available without repetitive labels', (
    tester,
  ) async {
    final selected = <int>[], timed = <int>[];
    await tester.pumpWidget(
      _panel(count: 2, onSelect: selected.add, onDuration: timed.add),
    );
    await tester.pumpAndSettle();
    await tester.tap(_card(1));
    expect(selected, [1]);
    await tester.longPress(_card(1));
    await tester.pumpAndSettle();
    expect(timed, [1]);
    await tester.tap(find.byTooltip('Frame options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duration…'));
    await tester.pumpAndSettle();
    expect(timed, [1, 0]);
    expect(find.text('Hold to time'), findsNothing);
    expect(find.text('100 ms'), findsNothing);
  });

  testWidgets('Right-click edits the targeted frame duration', (tester) async {
    final timed = <int>[];
    await tester.pumpWidget(_panel(count: 2, onDuration: timed.add));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.down(tester.getCenter(_card(1)));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(timed, [1]);
  });

  testWidgets('Frame semantics retain selection and nonvisual timing', (
    tester,
  ) async {
    await tester.pumpWidget(_panel(frame: 1, count: 2, duration: 175));
    await tester.pumpAndSettle();
    final semantics = tester.widget<Semantics>(_card(1)).properties;
    expect(semantics.label, 'Frame 2');
    expect(semantics.value, '175 milliseconds');
    expect(semantics.selected, isTrue);
    expect(semantics.onTap, isNotNull);
    expect(semantics.onLongPress, isNotNull);
    expect(find.text('175 ms'), findsNothing);
  });

  testWidgets('Menu key opens timing for a focused frame', (tester) async {
    final timed = <int>[];
    await tester.pumpWidget(_panel(count: 2, onDuration: timed.add));
    await tester.pumpAndSettle();
    final ink = find.descendant(of: _card(1), matching: find.byType(InkWell));
    Focus.of(tester.element(ink)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    expect(timed, [1]);
  });

  testWidgets('Busy frames cannot select or change duration', (tester) async {
    final selected = <int>[], timed = <int>[];
    await tester.pumpWidget(
      _panel(
        count: 2,
        busy: true,
        onSelect: selected.add,
        onDuration: timed.add,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_card(1));
    await tester.longPress(_card(1));
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
    expect(timed, isEmpty);
  });

  testWidgets('Frames reopen at selection, not stale browsing', (tester) async {
    _phone(tester);
    final engine = _engine();
    final editor = _editor(engine);
    await tester.pumpWidget(PocketPixelApp(editor: editor));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Frames'));
    await tester.pumpAndSettle();
    _expectVisible(tester, 60);
    await tester.drag(_strip, const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(_card(60).hitTestable(), findsNothing);
    await tester.tap(find.text('Layers').first);
    await tester.pumpAndSettle();
    await editor.call('select', {'frame': 79});
    await tester.pumpAndSettle();
    await tester.tap(find.text('Frames'));
    await tester.pumpAndSettle();
    _expectVisible(tester, 79);
    await tester.tap(find.text('Frames'));
    await tester.pumpAndSettle();
    expect(_strip, findsNothing);
    await tester.tap(find.text('Frames'));
    await tester.pumpAndSettle();
    _expectVisible(tester, 79);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Drawing and state notifications do not undo manual browsing', (
    tester,
  ) async {
    _phone(tester);
    final engine = _engine();
    final editor = _editor(engine);
    await tester.pumpWidget(PocketPixelApp(editor: editor));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Frames'));
    await tester.pumpAndSettle();
    await tester.drag(_strip, const Offset(600, 0));
    await tester.pumpAndSettle();
    final browsedOffset = _position(tester).pixels;
    await editor.call('state');
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, browsedOffset);
    await editor.call('stroke', {
      'tool': 'pencil',
      'color': 0xffa9b8ff,
      'size': 1,
      'points': [
        [1, 1],
      ],
    });
    await tester.pumpAndSettle();
    expect(editor.error, isNull);
    expect(_position(tester).pixels, browsedOffset);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Duration dialog preserves bounds, cancel and undo semantics', (
    tester,
  ) async {
    _phone(tester);
    final engine = _engine(count: 3, frame: 1);
    await tester.pumpWidget(PocketPixelApp(editor: _editor(engine)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Frames'));
    await tester.pumpAndSettle();
    final original = engine.document.frames[1].duration;
    await tester.longPress(_card(1));
    await tester.pumpAndSettle();
    expect(find.text('Frame duration (ms)'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '$original',
    );
    await tester.enterText(find.byType(TextField), '65535');
    await _dismissDuration(tester, 'Cancel');
    expect(engine.document.frames[1].duration, original);
    expect(engine.dirty, isFalse);
    await tester.tap(find.byTooltip('Frame options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duration…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0');
    await _dismissDuration(tester, 'Apply');
    expect(engine.document.frames[1].duration, original);
    expect(find.text('Enter a number from 1 to 65535.'), findsOneWidget);
    await tester.longPress(_card(1));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '65535');
    await _dismissDuration(tester, 'Apply');
    expect(engine.document.frames[1].duration, 65535);
    expect(engine.document.frames[0].duration, 100);
    expect(engine.document.frames[2].duration, 102);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(engine.document.frames[1].duration, original);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
