import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:spritedawg/platform/desktop_backend.dart';

void main() {
  test(
    'desktop thumbnail transport does not write recovery or change selection',
    () async {
      final base = await Directory.systemTemp.createTemp(
        'spritedawg-thumbnails-',
      );
      try {
        final backend = DesktopBackend(
          openPath: () async => null,
          savePath: (_) async => null,
          supportDirectory: () async => base,
        );
        await backend.invoke('init', null);
        await backend.invoke('new', null);
        final before = backend.engine.encode();
        final result = await backend.invoke('thumbnails', {
          'frames': [0],
          'maxSize': 16,
        });
        expect(result!.keys, ['thumbnails']);
        final t = (result['thumbnails'] as List).single;
        expect([t['width'], t['height']], [16, 16]);
        expect(backend.engine.encode(), before);
        expect(backend.engine.dirty, true);
        expect(backend.engine.state()['canUndo'], false);
        expect(await File('${base.path}/recovery.aseprite').exists(), false);
        await backend.dispose();
      } finally {
        await base.delete(recursive: true);
      }
    },
  );
}
