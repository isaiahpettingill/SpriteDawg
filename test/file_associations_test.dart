import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/main.dart';
import 'package:spritedawg/platform/desktop_backend.dart';
import 'package:spritedawg/engine/aseprite.dart';
import 'package:spritedawg/engine/document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'External local files append and invalid input preserves dirty documents',
    () async {
      final dir = await Directory.systemTemp.createTemp('association-');
      addTearDown(() => dir.delete(recursive: true));
      final backend = DesktopBackend(
        supportDirectory: () async => Directory('${dir.path}/support'),
      );
      await backend.invoke('init', null);
      await backend.invoke('new', null);
      await backend.invoke('stroke', {
        'tool': 'pencil',
        'points': [
          [1, 1],
        ],
        'color': 0xff123456,
      });
      final original = backend.sessions.activeId;
      final bytes = backend.engine.encode();
      final project = File('${dir.path}/space name.aseprite');
      await project.writeAsBytes(
        AsepriteCodec.encode(SpriteDocument.create(7, 9)),
      );
      await backend.invoke('openExternal', {'path': project.uri.toString()});
      expect(backend.sessions.documents.length, 2);
      expect(backend.engine.document.width, 7);
      expect(backend.sessions.documents.first.engine.dirty, isTrue);
      final selected = backend.sessions.activeId;
      final invalid = File('${dir.path}/invalid.ase');
      await invalid.writeAsString('not an Aseprite file');
      await expectLater(
        backend.invoke('openExternal', {'path': invalid.path}),
        throwsA(isA<FormatException>()),
      );
      expect(backend.sessions.activeId, selected);
      expect(backend.sessions.documents.length, 2);
      await expectLater(
        backend.invoke('openExternal', {
          'path': 'https://example.org/file.ase',
        }),
        throwsA(isA<FormatException>()),
      );
      backend.sessions.select(original);
      expect(backend.engine.encode(), bytes);
      expect(backend.engine.state()['canUndo'], isTrue);
      await backend.dispose();
    },
  );

  testWidgets('Startup and warm file-manager opens reach editor in order', (
    tester,
  ) async {
    const external = MethodChannel('pocketpixel/external');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      external,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        external,
        null,
      ),
    );
    final opened = <String>[];
    final editor = Editor(
      transport: (method, args) async {
        if (method == 'openExternal') opened.add(args!['path'] as String);
        return {
          'width': 8,
          'height': 8,
          'frames': [
            {'duration': 100},
          ],
          'layers': [
            {'name': 'Layer', 'visible': true, 'opacity': 255},
          ],
          'palette': [0xff000000],
          'tags': [],
          'documents': [],
        };
      },
    );
    await tester.pumpWidget(
      PocketPixelApp(
        editor: editor,
        initialFiles: const ['/tmp/first.ase', '/tmp/second.aseprite'],
      ),
    );
    await tester.pumpAndSettle();
    expect(opened, ['/tmp/first.ase', '/tmp/second.aseprite']);
    final data = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('files', ['/tmp/warm file.aseprite']),
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'pocketpixel/external',
      data,
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(opened.last, '/tmp/warm file.aseprite');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
