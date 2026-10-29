// Second process only; never seeds data if installation/teardown removed it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'draft_restart_seed_test.dart'
    show
        restartDraftFixtures,
        restartFixtureFileName,
        restartFixtureSentinel,
        restartInvoke,
        restartMaps;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('automatically restore exact tabs after force-stop and relaunch', (
    tester,
  ) async {
    expect(defaultTargetPlatform, TargetPlatform.android);
    final directory = await getApplicationSupportDirectory();
    final manifest = File('${directory.path}/$restartFixtureFileName');
    expect(
      await manifest.exists(),
      true,
      reason: 'Seed data disappeared. An uninstall/fresh install is NOT a pass.',
    );
    expect(await manifest.length(), lessThanOrEqualTo(4096));
    final saved = jsonDecode(await manifest.readAsString()) as Map;
    expect(saved['sentinel'], restartFixtureSentinel);
    expect(saved['seedProcessId'], isA<int>());
    expect(saved['seedProcessId'] as int, greaterThan(0));
    expect(
      saved['seedProcessId'],
      isNot(pid),
      reason: 'Verification must run in a fresh Android application process.',
    );
    final identities = (saved['drafts'] as List)
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList();
    expect(identities, hasLength(2));
    final expectedIds = identities.map((identity) => identity['id']).toSet();
    expect(expectedIds, hasLength(2));
    for (final identity in identities) {
      expect(identity['id'], isA<int>());
      expect(identity['id'] as int, greaterThan(0));
      expect(identity['title'], 'Untitled ${identity['id']}');
    }

    final initial = await restartInvoke('init');
    expect(initial['recoveryAvailable'], false);
    expect(restartMaps(initial, 'drafts'), isEmpty);
    final documents = restartMaps(initial, 'documents');
    expect(
      documents.map((document) => document['id']).toList(),
      identities.map((identity) => identity['id']).toList(),
      reason: 'Startup must restore the same tabs in their original order.',
    );
    expect(initial['documentId'], saved['activeId']);
    expect(initial['hasDocument'], true);
    expect(initial['dirty'], true);
    expect(initial['lastNewWidth'], restartDraftFixtures.last.width);
    expect(initial['lastNewHeight'], restartDraftFixtures.last.height);
    expect(initial['externalPending'], false);
    for (var index = 0; index < restartDraftFixtures.length; index++) {
      final fixture = restartDraftFixtures[index];
      final identity = identities[index];
      final document = documents.firstWhere(
        (candidate) => candidate['id'] == identity['id'],
      );
      expect(document['title'], identity['title']);
      expect(document['draftSavedAt'], greaterThan(0));
      expect(document['recoveryError'], isNull);
      final recovered = await restartInvoke('selectDocument', {
        'id': identity['id'],
      });
      expect(recovered['documentId'], identity['id']);
      expect(recovered['width'], fixture.width);
      expect(recovered['height'], fixture.height);
      expect(recovered['dirty'], true);
      expect((recovered['userData'] as Map)['sprite'], fixture.metadata);
      final tags = restartMaps(recovered, 'tags');
      expect(tags, hasLength(1));
      expect(tags.single['name'], fixture.tag);
      expect(tags.single['text'], '${fixture.metadata}:tag');
      expect(tags.single['from'], 0);
      expect(tags.single['to'], 0);
      final pixelCount = fixture.width * fixture.height;
      final expectedPixels = Uint8List(pixelCount * 4);
      for (var pixel = 0; pixel < pixelCount; pixel++) {
        final color = pixel == pixelCount - 1 ? fixture.accent : fixture.color;
        final offset = pixel * 4;
        expectedPixels[offset] = (color >> 16) & 255;
        expectedPixels[offset + 1] = (color >> 8) & 255;
        expectedPixels[offset + 2] = color & 255;
        expectedPixels[offset + 3] = (color >> 24) & 255;
      }
      expect(recovered['pixels'], orderedEquals(expectedPixels));
    }
    // Only after BOTH identities, metadata and complete pixel buffers pass do
    // we discard these exact test IDs. Never use bulk discard or app-data clear.
    for (final id in expectedIds) {
      await restartInvoke('closeDocument', {'id': id, 'discard': true});
    }
    final finished = await restartInvoke('flushDrafts');
    expect(restartMaps(finished, 'drafts'), isEmpty);
    expect(finished['dirty'], false);
    expect(finished['hasDocument'], false);
    expect(restartMaps(finished, 'documents'), isEmpty);
    await manifest.delete();
  });
}
