import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/main.dart';
import 'package:spritedawg/pixel_canvas.dart';

Map<String, dynamic> snapshot() => {
  'width': 32,
  'height': 32,
  'depth': 32,
  'frame': 0,
  'layer': 0,
  'dirty': false,
  'canUndo': false,
  'canRedo': false,
  'recoveryAvailable': false,
  'palette': [0xff000000, 0xffffffff],
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
  'userData': {},
};

Editor channelEditor() => Editor(
  transport: (method, arguments) =>
      Editor.channel.invokeMapMethod<String, dynamic>(method, arguments),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('320px phone panels do not overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      Editor.channel,
      (_) async => snapshot(),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        Editor.channel,
        null,
      ),
    );
    await tester.pumpWidget(PocketPixelApp(editor: channelEditor()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final label in ['Layers', 'Frames', 'Tags']) {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label at 320px');
    }
  });

  testWidgets('Pinch preserves pixel anchor and never leaves a stray stroke', (
    tester,
  ) async {
    final editor = Editor();
    final strokes = <List<Offset>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PixelCanvas(
            editor: editor,
            tool: 'pencil',
            color: 0xff000000,
            brush: 1,
            grid: false,
            onion: false,
            fitToken: 0,
            onPick: (_) {},
            onStroke: (_, points) => strokes.add(points),
          ),
        ),
      ),
    );
    final center = tester.getCenter(find.byKey(const Key('pixel-canvas')));
    final first = await tester.startGesture(
      center - const Offset(40, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(40, 0),
      pointer: 2,
    );
    await first.moveTo(center - const Offset(80, 0));
    await second.moveTo(center + const Offset(80, 0));
    final third = await tester.startGesture(center, pointer: 3);
    await third.up();
    await second.up();
    await first.up();
    expect(strokes, isEmpty);
    await tester.tapAt(center);
    expect(strokes, hasLength(1));
    expect(strokes.single.single.dx, closeTo(16, 0.001));
    expect(strokes.single.single.dy, closeTo(16, 0.001));
    await tester.pumpWidget(const SizedBox.shrink());
    editor.dispose();
  });

  testWidgets(
    'Confirmed dirty back exits instead of reopening discard dialog',
    (tester) async {
      var platformPops = 0;
      var recoveryDiscards = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        Editor.channel,
        (call) async {
          if (call.method == 'discardRecovery') recoveryDiscards++;
          return {...snapshot(), 'dirty': true};
        },
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') platformPops++;
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          Editor.channel,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });
      await tester.pumpWidget(PocketPixelApp(editor: channelEditor()));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Leave unsaved work?'), findsOneWidget);
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.text('Leave unsaved work?'), findsNothing);
      expect(platformPops, 1);
      expect(recoveryDiscards, 1);
    },
  );

  testWidgets('Changing tool cancels the entire in-flight pointer gesture', (
    tester,
  ) async {
    final editor = Editor();
    var count = 0;
    Widget canvas(String tool) => MaterialApp(
      home: Scaffold(
        body: PixelCanvas(
          editor: editor,
          tool: tool,
          color: 0xff000000,
          brush: 1,
          grid: false,
          onion: false,
          fitToken: 0,
          onPick: (_) {},
          onStroke: (_, points) => count++,
        ),
      ),
    );
    await tester.pumpWidget(canvas('pencil'));
    final center = tester.getCenter(find.byKey(const Key('pixel-canvas')));
    final finger = await tester.startGesture(center);
    await finger.moveBy(const Offset(20, 0));
    await tester.pumpWidget(canvas('eraser'));
    await finger.moveBy(const Offset(20, 0));
    await finger.up();
    expect(count, 0);
    await tester.tapAt(center);
    expect(count, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    editor.dispose();
  });
}
