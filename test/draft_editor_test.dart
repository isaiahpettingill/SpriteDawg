import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/draft_picker.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/main.dart';

Map<String, dynamic> _state({bool dirty = false}) => {
  'documentId': 7,
  'width': 32,
  'height': 32,
  'depth': 32,
  'frame': 0,
  'layer': 0,
  'dirty': dirty,
  'canUndo': dirty,
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
  'documents': [
    {
      'id': 7,
      'title': 'Drawing',
      'dirty': dirty,
      'active': true,
      'recoveryError': null,
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('quiet flush never drops a stroke or replaces newer drawing state', () async {
    final flushGate = Completer<Map<String, dynamic>>();
    final calls = <String>[];
    final editor = Editor(
      transport: (method, _) async {
        calls.add(method);
        if (method == 'flushDrafts') return flushGate.future;
        return _state(dirty: method == 'stroke');
      },
    );
    addTearDown(editor.dispose);
    expect(await editor.call('init'), true);
    final before = editor.revision;
    final flush = editor.flushDrafts();
    expect(editor.busy, false);
    expect(calls, ['init', 'flushDrafts']);
    expect(await editor.call('stroke'), true);
    expect(editor.dirty, true);
    expect(editor.canUndo, true);
    expect(editor.revision, before + 1);
    // A late response describes the old pixels/history. Only draft status is
    // allowed through, even when a newer stroke finished in the meantime.
    flushGate.complete(_state());
    expect(await flush, true);
    expect(editor.dirty, true);
    expect(editor.canUndo, true);
    expect(editor.revision, before + 1);
    expect(editor.documentRevision, 2);
    expect(calls.where((call) => call == 'stroke').length, 1);
  });


  test('quiet flush surfaces a global storage failure without losing edits', () async {
    final editor = Editor(
      transport: (method, _) async => {
        ..._state(dirty: true),
        if (method == 'flushDrafts')
          'recoveryError': 'Browser draft storage is unavailable. Download a copy now.',
      },
    );
    addTearDown(editor.dispose);
    await editor.call('init');
    expect(await editor.flushDrafts(), true);
    expect(editor.state['recoveryError'], contains('storage is unavailable'));
    expect(editor.dirty, true);
  });

  testWidgets('background flush waits for an in-flight stroke to commit', (
    tester,
  ) async {
    addTearDown(() => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    final strokeGate = Completer<void>();
    final calls = <String>[];
    var dirty = false;
    final editor = Editor(
      transport: (method, _) async {
        calls.add(method);
        if (method == 'stroke') {
          await strokeGate.future;
          dirty = true;
          calls.add('stroke committed');
        }
        return _state(dirty: dirty);
      },
    );
    await tester.pumpWidget(PocketPixelApp(editor: editor));
    await tester.pumpAndSettle();
    final stroke = editor.call('stroke');
    await tester.pump();
    expect(editor.busyDrawing, true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(calls, isNot(contains('flushDrafts')));
    strokeGate.complete();
    await tester.pumpAndSettle();
    expect(await stroke, true);
    expect(calls.indexOf('flushDrafts'), greaterThan(calls.indexOf('stroke committed')));
    expect(editor.dirty, true);
    expect(editor.busy, false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker dismissal retains drafts and deletion needs confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final drafts = <Map<String, dynamic>>[
      {
        'id': 21,
        'title': 'Hero draft',
        'updatedAt': 0,
        'width': 16,
        'height': 16,
        'frames': 2,
      },
      {
        'id': 22,
        'title': 'Damaged draft',
        'updatedAt': 0,
        'error': 'Stored copies could not be read.',
      },
    ];
    final deleted = <int>[];
    final editor = Editor(
      transport: (method, args) async {
        if (method == 'discardRecovery') {
          final id = args!['id'] as int;
          deleted.add(id);
          drafts.removeWhere((draft) => draft['id'] == id);
        }
        return {..._state(), 'drafts': List.of(drafts)};
      },
    );
    addTearDown(editor.dispose);
    await editor.call('init');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDraftPicker(context, editor),
              child: const Text('Show drafts'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show drafts'));
    await tester.pumpAndSettle();
    expect(find.text('Internal drafts'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);
    expect(drafts.length, 2);

    await tester.tap(find.text('Show drafts'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Discard Hero draft'));
    await tester.pumpAndSettle();
    expect(find.text('Permanently discard draft?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);
    expect(drafts.length, 2);

    await tester.tap(find.byTooltip('Discard Hero draft'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard draft'));
    await tester.pumpAndSettle();
    expect(deleted, [21]);
    expect(drafts.single['id'], 22);
    expect(find.text('Damaged draft'), findsOneWidget);
    expect(find.text('Hero draft'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
