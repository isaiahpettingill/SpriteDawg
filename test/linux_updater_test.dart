import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/linux_updater.dart';

void main() {
  test('stable versions compare numerically and reject untrusted tags', () {
    expect(LinuxRelease('v0.10.0').newerThan('v0.9.99'), isTrue);
    expect(LinuxRelease('v1.0.0').newerThan('v1.0.0'), isFalse);
    expect(LinuxRelease('v0.9.0').newerThan('v1.0.0'), isFalse);
    for (final tag in ['latest', 'v01.2.3', 'v1.2.3-beta', 'v1.2.3;id']) {
      expect(() => LinuxRelease(tag), throwsFormatException);
    }
  });

  test(
    'validates release metadata, command failure and install version',
    () async {
      for (final output in [
        '[]',
        '{"tag":"v1.2.3","arch":"mips"}',
        '{"tag":"v1.2.3-beta","arch":"x64"}',
      ]) {
        final updater = LinuxUpdater(
          command: (_) async => ProcessResult(0, 0, output, ''),
        );
        await expectLater(updater.check(), throwsFormatException);
      }
      final failed = LinuxUpdater(
        command: (_) async => ProcessResult(0, 1, '', 'GitHub rate limit'),
      );
      await expectLater(failed.check(), throwsStateError);
      final wrong = LinuxUpdater(
        command: (_) async => ProcessResult(0, 0, '{"tag":"v1.2.2"}', ''),
      );
      await expectLater(
        wrong.install(LinuxRelease('v1.2.3')),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'checking never installs; explicit confirmation pins version and keeps editor open',
    (tester) async {
      final calls = <List<String>>[];
      final installation = Completer<ProcessResult>();
      final updater = LinuxUpdater(
        installedTag: 'v0.3.65',
        command: (args) async {
          calls.add(args);
          if (args.first == '--check')
            return ProcessResult(0, 0, '{"tag":"v0.3.66","arch":"x64"}', '');
          return installation.future;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  const Text('Unsaved drawing'),
                  TextButton(
                    onPressed: () =>
                        showLinuxUpdater(context, updater: updater),
                    child: const Text('Updates'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Updates'));
      await tester.pumpAndSettle();
      expect(calls, [
        ['--check'],
      ]);
      await tester.tap(find.text('Install update'));
      await tester.pump();
      expect(calls, [
        ['--check'],
        ['--version', 'v0.3.66'],
      ]);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      installation.complete(ProcessResult(0, 0, '{"tag":"v0.3.66"}', ''));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('open drawings are unchanged'),
        findsOneWidget,
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved drawing'), findsOneWidget);
    },
  );

  testWidgets('up to date and errors do not offer installation', (
    tester,
  ) async {
    for (final result in [
      ProcessResult(0, 0, '{"tag":"v1.0.0","arch":"arm64"}', ''),
      ProcessResult(0, 1, '', 'No Linux asset'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showLinuxUpdater(
                context,
                updater: LinuxUpdater(
                  installedTag: 'v1.0.0',
                  command: (_) async => result,
                ),
              ),
              child: const Text('Updates'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Updates'));
      await tester.pumpAndSettle();
      expect(find.text('Install update'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    }
  });
}
