// Disposable Android emulator only. Run through scripts/check-draft-restart.sh.
// This phase deliberately leaves two committed drafts for a NEW app process.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spritedawg/editor.dart';

const restartFixtureFileName = 'spritedawg-draft-restart-ci-v1.json';
const restartFixtureSentinel = 'spritedawg-draft-restart-ci-v1';
const restartDraftFixtures = [
  (
    width: 7,
    height: 5,
    color: 0xffdf2948,
    accent: 0xfff4cb31,
    tag: 'CI red draft',
    metadata: 'spritedawg:draft-restart:v1:red',
  ),
  (
    width: 11,
    height: 3,
    color: 0xff287ad6,
    accent: 0xff42d486,
    tag: 'CI blue draft',
    metadata: 'spritedawg:draft-restart:v1:blue',
  ),
];

Future<Map<String, dynamic>> restartInvoke(
  String method, [
  Map<String, dynamic>? arguments,
]) async {
  final state = await Editor.channel.invokeMapMethod<String, dynamic>(
    method,
    arguments,
  );
  expect(state, isNotNull);
  final result = state!;
  expect(result['recoveryError'], isNull);
  return result;
}

List<Map<String, dynamic>> restartMaps(
  Map<String, dynamic> state,
  String key,
) => (state[key] as List)
    .map((value) => Map<String, dynamic>.from(value as Map))
    .toList();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('seed two durable native drafts for a later process', (
    tester,
  ) async {
    expect(defaultTargetPlatform, TargetPlatform.android);
    final directory = await getApplicationSupportDirectory();
    final manifest = File('${directory.path}/$restartFixtureFileName');
    expect(
      await manifest.exists(),
      false,
      reason: 'Refusing to overwrite an existing restart fixture.',
    );
    final initial = await restartInvoke('init');
    expect(
      restartMaps(initial, 'drafts'),
      isEmpty,
      reason: 'Use a clean disposable emulator; never replace existing drafts.',
    );
    expect(initial['recoveryAvailable'], false);
    expect(initial['externalPending'], false);
    expect(initial['dirty'], false);
    expect(initial['canUndo'], false);
    expect(initial['hasTagClipboard'], false);
    expect(initial['hasDocument'], false);
    expect(initial['width'], 0);
    expect(initial['height'], 0);
    expect((initial['pixels'] as Uint8List).every((value) => value == 0), true);
    expect((initial['userData'] as Map)['sprite'], isNull);
    final initialDocuments = restartMaps(initial, 'documents');
    expect(initialDocuments, isEmpty);

    final seeded = <Map<String, dynamic>>[];
    for (final fixture in restartDraftFixtures) {
      var state = await restartInvoke('new', {
        'width': fixture.width,
        'height': fixture.height,
      });
      final id = state['documentId'];
      await restartInvoke('stroke', {
        'tool': 'fill',
        'points': [
          [0, 0],
        ],
        'color': fixture.color,
        'size': 1,
      });
      await restartInvoke('stroke', {
        'tool': 'pencil',
        'points': [
          [fixture.width - 1, fixture.height - 1],
        ],
        'color': fixture.accent,
        'size': 1,
      });
      await restartInvoke('edit', {
        'action': 'addTag',
        'name': fixture.tag,
        'from': 0,
        'to': 0,
        'direction': 0,
      });
      await restartInvoke('edit', {
        'action': 'userData',
        'target': 'tag',
        'index': 0,
        'text': '${fixture.metadata}:tag',
      });
      state = await restartInvoke('edit', {
        'action': 'userData',
        'target': 'sprite',
        'text': fixture.metadata,
      });
      final document = restartMaps(state, 'documents').firstWhere(
        (document) => document['id'] == id,
      );
      seeded.add({'id': id, 'title': document['title']});
      expect(document['dirty'], true);
    }
    await restartInvoke('selectDocument', {'id': seeded.first['id']});
    final flushed = await restartInvoke('flushDrafts');
    final documents = restartMaps(flushed, 'documents');
    expect(documents, hasLength(2));
    expect(documents.map((document) => document['id']).toSet(), hasLength(2));
    for (final document in documents) {
      expect(document['dirty'], true);
      expect(document['draftPending'], false);
      expect(document['draftSavedAt'], greaterThan(0));
      expect(document['recoveryError'], isNull);
    }
    await manifest.writeAsString(
      jsonEncode({
        'sentinel': restartFixtureSentinel,
        'seedProcessId': pid,
        'drafts': seeded,
        'activeId': flushed['documentId'],
      }),
      flush: true,
    );
    // No close/discard, no Save, and no fixture cleanup in this phase. The next
    // entrypoint must prove that these exact IDs survive app process termination.
  });
}
