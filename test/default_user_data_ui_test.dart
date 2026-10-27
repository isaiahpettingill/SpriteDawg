import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/default_user_data_dialog.dart';
import 'package:spritedawg/default_user_data_store.dart';
import 'package:spritedawg/editor.dart';
import 'editor_test.dart' as fixture;

void main() {
  testWidgets(
    'dismissing during a delayed defaults read never touches disposed controls',
    (t) async {
      final loaded = Completer<String>();
      final store = DefaultUserDataStore(
        read: () => loaded.future,
        write: (_) async {},
      );
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => showDefaultUserDataDialog(c, store),
                child: const Text('Defaults'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Defaults'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('Cancel'));
      // Do not settle an intentionally unresolved loading animation.
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      loaded.complete('late');
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('default-user-data-text')), findsNothing);
    },
  );
  testWidgets('defaults save raw text, cancel does not change saved defaults', (
    t,
  ) async {
    final store = DefaultUserDataStore.memory('original');
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => showDefaultUserDataDialog(c, store),
              child: const Text('Defaults'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Defaults'));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const Key('default-user-data-text')),
      'not saved',
    );
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(await store.load(), 'original');
    await t.tap(find.text('Defaults'));
    await t.pumpAndSettle();
    const raw = ' credits="Artist"\ntitle="Optional"\nlicense="CC0"\n';
    await t.enterText(find.byKey(const Key('default-user-data-text')), raw);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(await store.load(), raw);
  });
  testWidgets('unreadable defaults require explicit replace confirmation', (
    t,
  ) async {
    var writes = 0;
    final store = DefaultUserDataStore(
      read: () async => throw const FormatException('bad'),
      write: (_) async {
        writes++;
      },
    );
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => showDefaultUserDataDialog(c, store),
              child: const Text('Defaults'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Defaults'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.text('Replace unreadable defaults?'), findsOneWidget);
    await t.tap(find.text('Cancel').last);
    await t.pumpAndSettle();
    expect(writes, 0);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    await t.tap(find.text('Replace'));
    await t.pumpAndSettle();
    expect(writes, 1);
  });
  testWidgets('Editor passes defaults only for fresh canvas creation paths', (
    t,
  ) async {
    final received = <String, Map<String, dynamic>?>{};
    final store = DefaultUserDataStore.memory('credits="A"');
    final e = Editor(
      defaultsStore: store,
      transport: (method, args) async {
        received[method] = args;
        return fixture.state();
      },
    );
    await e.call('init');
    await e.call('new', {'width': 16});
    await e.call('open');
    expect(received['init']?['defaultUserData'], 'credits="A"');
    expect(received['new']?['defaultUserData'], 'credits="A"');
    expect(received['new']?['width'], 16);
    expect(received['open'], isNull);
    await store.save('license="CC0"');
    await e.call('closeDocument', {'id': 1});
    expect(received['closeDocument']?['defaultUserData'], 'license="CC0"');
    e.dispose();
  });
}
