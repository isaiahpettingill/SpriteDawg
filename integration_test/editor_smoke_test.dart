// Run only on a clean, disposable emulator: this exercises app-private recovery.
// No mocks, document picker, external files, or persistent signing keys are used.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android native engine and Flutter touch canvas work together', (
    tester,
  ) async {
    expect(defaultTargetPlatform, TargetPlatform.android);
    // Refuse to replace somebody's existing recovery file if run on a real device.
    final initial = await Editor.channel.invokeMapMethod<String, dynamic>(
      'init',
    );
    expect(initial, isNotNull);
    expect(
      initial!['recoveryAvailable'],
      false,
      reason: 'Use a clean emulator; this test will not discard existing work.',
    );

    final editor = Editor(); // Real MethodChannel transport, not a test double.
    await tester.pumpWidget(PocketPixelApp(editor: editor));
    Future<void> settleNative() async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      do {
        await tester.pump(const Duration(milliseconds: 40));
        if (DateTime.now().isAfter(deadline)) {
          fail('Native operation did not complete: ${editor.error}');
        }
      } while (editor.busy || editor.state.isEmpty);
      await tester.pumpAndSettle();
      expect(editor.error, isNull);
      expect(editor.state['recoveryError'], isNull);
      expect(tester.takeException(), isNull);
    }

    await settleNative();
    expect(await editor.call('new', {'width': 16, 'height': 16}), true);
    await settleNative();
    expect(editor.width, 16);
    expect(editor.image, isNotNull);

    expect(
      await editor.call('stroke', {
        'tool': 'pencil',
        'points': [
          [0, 0],
          [3, 0],
        ],
        'color': 0xffed7614,
        'size': 1,
      }),
      true,
    );
    await settleNative();
    final colored = Uint8List.fromList(editor.state['pixels'] as Uint8List);
    expect(colored.sublist(0, 16), [
      237,
      118,
      20,
      255,
      237,
      118,
      20,
      255,
      237,
      118,
      20,
      255,
      237,
      118,
      20,
      255,
    ]);
    expect(editor.canUndo, true);
    expect(editor.state['recoveryAvailable'], true);
    expect(await editor.call('undo'), true);
    expect((editor.state['pixels'] as Uint8List).every((v) => v == 0), true);
    expect(await editor.call('redo'), true);
    expect(editor.state['pixels'], orderedEquals(colored));

    const metadata = '{"strength":12,"animation":"walk"}';
    expect(
      await editor.edit('userData', {'target': 'sprite', 'text': metadata}),
      true,
    );
    expect((editor.state['userData'] as Map)['sprite'], metadata);
    // Recovery serializes and decodes the actual Aseprite bytes, exercising more
    // than just a transient channel state map. No external/user file is touched.
    expect(await editor.call('recover'), true);
    expect((editor.state['userData'] as Map)['sprite'], metadata);
    expect(editor.state['pixels'], orderedEquals(colored));
    expect(editor.dirty, true);
    await settleNative();

    await tester.tap(find.byTooltip('Fit canvas'));
    await settleNative();
    final canvas = find.byKey(const Key('pixel-canvas'));
    final center = tester.getCenter(canvas);
    final beforeTouch = Uint8List.fromList(editor.state['pixels'] as Uint8List);
    await tester.tapAt(center);
    await settleNative();
    expect(
      editor.state['pixels'],
      isNot(orderedEquals(beforeTouch)),
      reason:
          'A real Flutter touch must commit pixels through the native bridge.',
    );

    final beforePinch = Uint8List.fromList(editor.state['pixels'] as Uint8List);
    final first = await tester.startGesture(
      center - const Offset(20, 0),
      pointer: 1,
    );
    await first.moveBy(const Offset(4, 0));
    final second = await tester.startGesture(
      center + const Offset(20, 0),
      pointer: 2,
    );
    await first.moveTo(center - const Offset(35, 0));
    await second.moveTo(center + const Offset(35, 0));
    await second.up();
    await first.up();
    await settleNative();
    expect(await editor.call('state'), true);
    expect(
      editor.state['pixels'],
      orderedEquals(beforePinch),
      reason: 'Adding a second pointer must cancel the uncommitted stroke.',
    );

    // Tag ranges are contiguous Aseprite ranges, equally useful for tile variants
    // and animation. Exercise the real bridge and recovery codec, not UI mocks.
    expect(await editor.edit('duplicateFrame'), true);
    expect(await editor.edit('duplicateFrame'), true);
    expect(
      await editor.edit('addTag', {
        'name': 'Terrain variants',
        'from': 0,
        'to': 2,
        'direction': 0,
      }),
      true,
    );
    expect(
      await editor.edit('userData', {
        'target': 'tag',
        'index': 0,
        'text': 'game:terrain',
      }),
      true,
    );
    expect(
      await editor.edit('updateTag', {
        'index': 0,
        'name': 'Grass variants',
        'from': 1,
        'to': 2,
        'direction': 2,
        'repeat': 3,
      }),
      true,
    );
    expect(editor.maps('tags').single['text'], 'game:terrain');
    expect(await editor.call('undo'), true);
    expect(editor.maps('tags').single['name'], 'Terrain variants');
    expect(editor.maps('tags').single['from'], 0);
    expect(await editor.call('redo'), true);
    expect(editor.maps('tags').single['from'], 1);
    final selectedFrame = editor.frame;
    final thumbnailResult = await Editor.channel
        .invokeMapMethod<String, dynamic>('thumbnails', {
          'frames': [0, 1, 2],
          'maxSize': 24,
        });
    expect((thumbnailResult!['thumbnails'] as List).length, 3);
    expect(await editor.call('state'), true);
    expect(editor.frame, selectedFrame);
    expect(
      await editor.edit('duplicateTag', {'index': 0, 'name': 'NPC walk'}),
      true,
    );
    expect(
      await editor.edit('userData', {
        'target': 'tag',
        'index': 1,
        'text': 'game:npc',
      }),
      true,
    );
    expect(editor.maps('tags')[0]['text'], 'game:terrain');
    final savedTags = editor.maps('tags');
    expect(await editor.call('recover'), true);
    expect(editor.maps('tags'), equals(savedTags));
    await settleNative();

    final sourceDocument = editor.state['documentId'];
    expect(await editor.call('copyTag', {'index': 0}), true);
    expect(editor.state['hasTagClipboard'], true);
    expect(await editor.call('new', {'width': 16, 'height': 16}), true);
    final targetDocument = editor.state['documentId'];
    expect(targetDocument, isNot(sourceDocument));
    expect(await editor.call('pasteTag'), true);
    expect(editor.maps('frames').length, 3);
    expect(editor.maps('tags').single['name'], 'Grass variants');
    expect(editor.maps('tags').single['text'], 'game:terrain');
    expect(await editor.call('undo'), true);
    expect(editor.maps('frames').length, 1);
    expect(editor.maps('tags'), isEmpty);
    expect(await editor.call('redo'), true);
    expect(editor.maps('frames').length, 3);
    expect(await editor.call('selectDocument', {'id': sourceDocument}), true);
    expect(editor.maps('tags'), equals(savedTags));

    expect(await editor.call('new', {'width': 3, 'height': 1}), true);
    expect(
      await editor.call('stroke', {
        'tool': 'fill',
        'points': [
          [0, 0],
        ],
        'color': 0xffff0000,
        'gradient': true,
        'secondaryColor': 0xff0000ff,
        'gradientDirection': 'horizontal',
        'size': 1,
      }),
      true,
    );
    final gradient = editor.state['pixels'] as Uint8List;
    expect(gradient.sublist(0, 4), [255, 0, 0, 255]);
    expect(gradient.sublist(8, 12), [0, 0, 255, 255]);
    expect(await editor.call('undo'), true);
    expect((editor.state['pixels'] as Uint8List).every((v) => v == 0), true);
    expect(await editor.call('new', {'width': 16, 'height': 16}), true);
    final sprayArgs = <String, dynamic>{
      'tool': 'spray',
      'points': [
        [8, 8],
        [10, 8],
      ],
      'color': 0xff10e080,
      'size': 7,
      'density': 12,
      'seed': 12345,
    };
    expect(await editor.call('stroke', sprayArgs), true);
    final sprayed = Uint8List.fromList(editor.state['pixels'] as Uint8List);
    expect(sprayed.any((v) => v != 0), true);
    expect(await editor.call('undo'), true);
    expect((editor.state['pixels'] as Uint8List).every((v) => v == 0), true);
    expect(await editor.call('stroke', sprayArgs), true);
    expect(editor.state['pixels'], orderedEquals(sprayed));
    await settleNative();

    // Remove only the recovery generated by this test after the clean-start guard.
    for (final document in editor.maps('documents')) {
      expect(
        await editor.call('closeDocument', {
          'id': document['id'],
          'discard': true,
        }),
        true,
      );
    }
    expect(await editor.call('discardRecovery'), true);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
