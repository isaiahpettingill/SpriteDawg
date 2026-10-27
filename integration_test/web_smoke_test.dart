// CI uses a disposable Chrome profile. Only picker/download boundaries are
// injected: drawing, Aseprite import, snapshots and encoders are real browser code.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:spritedawg/user_palette_store.dart';
import 'package:spritedawg/platform/palette_storage_io.dart'
    if (dart.library.js_interop) 'package:spritedawg/platform/palette_storage_web.dart'
    as palette_storage;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:spritedawg/editor.dart';
import 'package:spritedawg/engine/aseprite.dart';
import 'package:spritedawg/export/image_export.dart';
import 'package:spritedawg/export/spritesheet.dart';
import 'package:spritedawg/main.dart';
import 'package:spritedawg/platform/web_backend.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('browser draws, imports Aseprite and encodes real exports', (
    tester,
  ) async {
    expect(kIsWeb, true);
    XFile? picked;
    final downloads = <String, Uint8List>{};
    final backend = DesktopBackend(
      openFile: () async => picked,
      download: (name, bytes) async {
        downloads[name] = Uint8List.fromList(bytes);
      },
    );
    final editor = Editor(transport: backend.invoke);
    await tester.pumpWidget(PocketPixelApp(editor: editor));
    Future<void> settle() async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      do {
        await tester.pump(const Duration(milliseconds: 40));
        if (DateTime.now().isAfter(deadline)) {
          fail('Browser operation timed out: ${editor.error}');
        }
      } while (editor.busy || editor.state.isEmpty);
      await tester.pumpAndSettle();
      expect(editor.error, isNull);
      expect(tester.takeException(), isNull);
    }

    await settle();
    expect(await editor.call('new', {'width': 16, 'height': 16}), true);
    await settle();
    // Desktop-width layouts keep Fit in the project menu, unlike Android's
    // compact toolbar. Exercise that real menu rather than assuming an icon.
    await tester.tap(find.byTooltip('Project and view options'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Fit canvas'));
    await tester.tap(find.text('Fit canvas'));
    await settle();
    final before = Uint8List.fromList(editor.state['pixels'] as Uint8List);
    await tester.tapAt(tester.getCenter(find.byKey(const Key('pixel-canvas'))));
    await settle();
    expect(editor.state['pixels'], isNot(orderedEquals(before)));
    expect(await editor.call('undo'), true, reason: editor.error);
    expect(editor.state['pixels'], orderedEquals(before));
    expect(await editor.call('redo'), true, reason: editor.error);

    // Reopen compressed Aseprite bytes through the actual browser import path.
    final savedPixels = Uint8List.fromList(editor.state['pixels'] as Uint8List);
    final project = AsepriteCodec.encode(
      backend.sessions.active.engine.document,
    );
    picked = XFile.fromData(project, name: 'browser-roundtrip.aseprite');
    expect(await editor.call('open'), true, reason: editor.error);
    await settle();
    expect(editor.state['pixels'], orderedEquals(savedPixels));
    picked = null;
    final documentId = editor.state['documentId'];
    expect(await editor.call('open'), true, reason: editor.error);
    expect(
      editor.state['documentId'],
      documentId,
      reason: 'Cancel retains work',
    );

    expect(await editor.edit('duplicateFrame'), true, reason: editor.error);
    final snapshot = (await backend.invoke('exportSnapshot', {
      'scope': 'all',
      'animation': true,
    }))!;
    final frames = (snapshot['frames'] as List).cast<Uint8List>();
    final durations = (snapshot['durations'] as List).cast<int>();
    for (final format in [
      ImageExportFormat.gif,
      ImageExportFormat.apng,
      ImageExportFormat.webp,
      ImageExportFormat.qoi,
    ]) {
      final still = format == ImageExportFormat.qoi;
      final bytes = await encodeImageExport(
        ImageExportPayload(
          width: 16,
          height: 16,
          rgbaFrames: still ? [frames.first] : frames,
          durationMs: still ? [durations.first] : durations,
        ),
        format,
      );
      expect(bytes, isNotEmpty);
      if (still) {
        expect(ascii.decode(bytes.take(4).toList()), 'qoif');
      } else {
        final decoded = img.decodeImage(bytes);
        expect(decoded, isNotNull, reason: format.name);
        expect(decoded!.width, 16);
        expect(decoded.height, 16);
        expect(decoded.frames.length, 2);
      }
      expect(
        (await backend.invoke('saveExport', {
          'name': 'browser',
          'files': {'browser.${format.name}': bytes},
        }))!['saved'],
        true,
      );
      expect(downloads['browser.${format.name}'], orderedEquals(bytes));
    }
    final sheetSnapshot = (await backend.invoke('exportSnapshot', {
      'scope': 'all',
    }))!;
    final sheet = encodeSpritesheet(
      sheetSnapshot,
      name: 'browser-sheet',
      columns: 2,
      padding: 1,
    );
    final metadata =
        jsonDecode(utf8.decode(sheet['browser-sheet.json']!)) as Map;
    expect((metadata['frames'] as List).length, 2);
    expect((metadata['meta'] as Map)['image'], 'browser-sheet.png');
    expect(img.decodePng(sheet['browser-sheet.png']!)!.width, 35);
    expect(
      (await backend.invoke('saveExport', {
        'name': 'browser-sheet',
        'files': sheet,
      }))!['saved'],
      true,
    );
    final zip = ZipDecoder().decodeBytes(downloads['browser-sheet.zip']!);
    expect(zip.files.map((file) => file.name).toSet(), sheet.keys.toSet());
    for (final file in zip.files) {
      expect(file.content, orderedEquals(sheet[file.name]!));
    }
    // Isolated localStorage key; never touches a user's normal palette library.
    final paletteFile = palette_storage.File(
      'spritedawg-ci-palette-${DateTime.now().microsecondsSinceEpoch}',
    );
    expect(await paletteFile.exists(), false);
    try {
      final library = UserPaletteStore(() async => paletteFile);
      final saved = await library.save(
        name: 'Browser transparency',
        colors: [0xff123456, 0x80123456, 0x00123456],
      );
      final reloaded = await UserPaletteStore(() async => paletteFile).load();
      expect(reloaded.single.id, saved.id);
      expect(reloaded.single.colors, [0xff123456, 0x80123456, 0x00123456]);
    } finally {
      if (await paletteFile.exists()) await paletteFile.delete();
    }
    expect(editor.state['documentId'], documentId);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
