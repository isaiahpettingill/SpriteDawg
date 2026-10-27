import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// Paired exports use a new directory, so an interrupted export never replaces
/// either half of an existing spritesheet. Single files use explicit Save As.
class ExportFiles {
  ExportFiles({
    Future<String?> Function(String, String)? pickFile,
    Future<String?> Function()? pickDirectory,
  }) : pickFile = pickFile ?? _pickFile,
       pickDirectory = pickDirectory ?? getDirectoryPath;
  final Future<String?> Function(String, String) pickFile;
  final Future<String?> Function() pickDirectory;

  static Future<String?> _pickFile(String name, String extension) async =>
      (await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: [
          XTypeGroup(label: extension.toUpperCase(), extensions: [extension]),
        ],
      ))?.path;

  Future<Map<String, dynamic>> save(Map<String, dynamic> args) async {
    final files = Map<String, Uint8List>.from(args['files'] as Map);
    final name = args['name'] as String;
    if (files.isEmpty ||
        files.length > 2 ||
        files.keys.any(
          (key) => !RegExp(r'^[A-Za-z0-9][A-Za-z0-9 _.-]{0,80}$').hasMatch(key),
        ) ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9 _.-]{0,63}$').hasMatch(name) ||
        files.values.fold<int>(0, (n, bytes) => n + bytes.length) >
            128 * 1024 * 1024) {
      throw const FormatException('Invalid export files');
    }
    if (files.length == 1) {
      final entry = files.entries.single;
      final path = await pickFile(entry.key, entry.key.split('.').last);
      if (path == null) return {'saved': false};
      // Unique temporary file avoids collisions between concurrent app processes.
      final folder = await Directory(
        File(path).parent.path,
      ).createTemp('.spritedawg-export-');
      try {
        final temp = File('${folder.path}/output');
        await temp.writeAsBytes(entry.value, flush: true);
        await temp.rename(path);
      } finally {
        await folder.delete(recursive: true);
      }
      return {'saved': true};
    }
    final path = await pickDirectory();
    if (path == null) return {'saved': false};
    final folder = await Directory(path).createTemp('$name-');
    try {
      for (final entry in files.entries) {
        await File(
          '${folder.path}/${entry.key}',
        ).writeAsBytes(entry.value, flush: true);
      }
    } catch (_) {
      try {
        await folder.delete(recursive: true);
      } catch (_) {
        /* Preserve original failure. */
      }
      rethrow;
    }
    return {'saved': true, 'location': folder.path};
  }
}
