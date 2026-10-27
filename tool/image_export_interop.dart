// Run after flutter pub get. Optional second argument: freshly built native
// libflutter_avif.so path, enabling independent AVIF validation on Linux.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_avif_platform_interface/flutter_avif_platform_interface.dart'
    as avif;
import 'package:spritedawg/export/image_export.dart';
import 'package:spritedawg/export/spritesheet.dart';

Future<void> main(List<String> args) async {
  final directory = Directory(args.isEmpty ? 'build/export-interop' : args[0]);
  await directory.create(recursive: true);
  if (args.length > 1) {
    avif.FlutterAvifPlatform.api = avif.FlutterAvifImpl(
      DynamicLibrary.open(args[1]),
    );
  }
  final frames = [
    [
      255,
      0,
      0,
      255,
      0,
      255,
      0,
      255,
      0,
      0,
      255,
      255,
      120,
      80,
      40,
      128,
      0,
      0,
      0,
      0,
      255,
      255,
      255,
      255,
    ],
    [
      0,
      0,
      0,
      0,
      0,
      255,
      0,
      255,
      0,
      0,
      255,
      255,
      120,
      80,
      40,
      128,
      255,
      0,
      255,
      255,
      255,
      255,
      255,
      255,
    ],
    [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      255,
      255,
      120,
      80,
      40,
      128,
      255,
      0,
      255,
      255,
      0,
      0,
      0,
      0,
    ],
  ].map(Uint8List.fromList).toList();
  // Repeat the 3x2 pattern to an 18x16 image; rav1e needs both dimensions >=16.
  final expanded = frames
      .map(
        (frame) => Uint8List.fromList([
          for (var y = 0; y < 16; y++)
            for (var x = 0; x < 18; x++)
              ...frame.sublist(
                ((y % 2) * 3 + x % 3) * 4,
                ((y % 2) * 3 + x % 3) * 4 + 4,
              ),
        ]),
      )
      .toList();
  const durations = [70, 110, 130];
  for (final format in ImageExportFormat.values) {
    if (format == ImageExportFormat.avif && args.length < 2) continue;
    final still =
        format == ImageExportFormat.qoi || format == ImageExportFormat.avif;
    final payload = ImageExportPayload(
      width: 18,
      height: 16,
      rgbaFrames: still ? [expanded.first] : expanded,
      durationMs: still ? [durations.first] : durations,
      loopCount: 2,
    );
    final bytes = await encodeImageExport(payload, format);
    await File('${directory.path}/fixture.${format.name}').writeAsBytes(bytes);
  }
  final atlas = encodeSpritesheet(
    {
      'width': 18,
      'height': 16,
      'frames': expanded,
      'durations': durations,
      'indices': [0, 1, 2],
      'tags': [
        {'name': 'fixture', 'from': 0, 'to': 2, 'direction': 0, 'repeat': 2},
      ],
    },
    name: 'atlas',
    columns: 2,
    padding: 1,
  );
  for (final entry in atlas.entries) {
    await File('${directory.path}/${entry.key}').writeAsBytes(entry.value);
  }
  await File('${directory.path}/expected.json').writeAsString(
    jsonEncode({
      'width': 18,
      'height': 16,
      'frames': expanded,
      'durationMs': durations,
      'totalPlays': 2,
    }),
  );
}
