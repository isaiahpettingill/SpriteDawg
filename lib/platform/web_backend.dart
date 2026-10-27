import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart' as picker;
import 'package:web/web.dart' as web;

import '../engine/aseprite.dart';
import '../engine/document.dart';
import '../engine/editor_engine.dart';
import '../engine/editor_sessions.dart';
import '../engine/png.dart';
import '../export/export_snapshot.dart';

/// Browser files stay on-device. A download creates a copy, never filesystem
/// overwrite access. Sessions remain in memory; closing the tab warns if dirty.
class DesktopBackend {
  DesktopBackend({
    Future<picker.XFile?> Function()? openFile,
    Future<void> Function(String, Uint8List)? download,
  }) : _openFile = openFile ?? _pickOpen,
       _download = download ?? _downloadFile {
    web.window.addEventListener(
      'beforeunload',
      ((web.Event event) {
        if (sessions.documents.any((s) => s.engine.dirty)) {
          event.preventDefault();
          (event as web.BeforeUnloadEvent).returnValue = '';
        }
      }).toJS,
    );
  }
  final Future<picker.XFile?> Function() _openFile;
  final Future<void> Function(String, Uint8List) _download;
  final sessions = EditorSessions();
  EditorEngine get engine => sessions.active.engine;
  Future<void> _queue = Future<void>.value();
  static Future<picker.XFile?> _pickOpen() => picker.openFile(
    acceptedTypeGroups: [
      const picker.XTypeGroup(
        label: 'Aseprite project',
        extensions: ['ase', 'aseprite'],
      ),
    ],
  );
  static Future<void> _downloadFile(String name, Uint8List bytes) =>
      picker.XFile.fromData(
        bytes,
        name: name,
        mimeType: 'application/octet-stream',
      ).saveTo(name);

  Future<Map<String, dynamic>?> invoke(
    String method,
    Map<String, dynamic>? arguments,
  ) {
    final result = _queue.then((_) => _invoke(method, arguments ?? {}));
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<Map<String, dynamic>?> _invoke(
    String method,
    Map<String, dynamic> args,
  ) async {
    switch (method) {
      case 'open':
        if (sessions.documents.length >= 8) {
          throw StateError(
            'Close a document before opening another (8 maximum).',
          );
        }
        final chosen = await _openFile();
        if (chosen == null) break;
        if (await chosen.length() > AsepriteCodec.maxFile) {
          throw const FormatException('File exceeds the 64 MiB safety limit');
        }
        final document = AsepriteCodec.decode(await chosen.readAsBytes());
        sessions.add(document, title: chosen.name);
      case 'openExternal':
        throw UnsupportedError('Use Open to choose a local Aseprite file.');
      case 'save':
      case 'saveAs':
        final bytes = engine.encode();
        AsepriteCodec.decode(bytes);
        var name = sessions.active.title;
        if (!name.toLowerCase().endsWith('.aseprite') &&
            !name.toLowerCase().endsWith('.ase')) {
          name = '$name.aseprite';
        }
        await _download(name, bytes);
      // Browsers cannot confirm that the user kept a download. Keep dirty so
      // closing the tab still warns; do not falsely claim filesystem saving.
      case 'exportPng':
        await _download(
          'sprite.png',
          encodeRgbaPng(
            engine.state()['pixels'] as Uint8List,
            width: engine.document.width,
            height: engine.document.height,
          ),
        );
      case 'exportSnapshot':
        return exportSnapshot(engine.document, engine.frame, args);
      case 'saveExport':
        final files = Map<String, Uint8List>.from(args['files'] as Map);
        final name = args['name'] as String;
        if (files.isEmpty ||
            files.length > 2 ||
            files.keys.any(
              (key) =>
                  !RegExp(r'^[A-Za-z0-9][A-Za-z0-9 _.-]{0,80}$').hasMatch(key),
            ) ||
            !RegExp(r'^[A-Za-z0-9][A-Za-z0-9 _.-]{0,63}$').hasMatch(name) ||
            files.values.fold<int>(0, (n, b) => n + b.length) >
                128 * 1024 * 1024) {
          throw const FormatException('Invalid export files');
        }
        if (files.length == 1) {
          await _download(files.keys.single, files.values.single);
        } else {
          final archive = Archive();
          for (final entry in files.entries) {
            archive.addFile(
              ArchiveFile(entry.key, entry.value.length, entry.value),
            );
          }
          await _download('$name.zip', ZipEncoder().encodeBytes(archive));
        }
        return {'saved': true};
      case 'selectDocument':
        sessions.select((args['id'] as num).toInt());
      case 'closeDocument':
        sessions.close(
          (args['id'] as num).toInt(),
          discard: args['discard'] == true,
        );
      case 'copyTag':
        sessions.copyTag((args['index'] as num).toInt());
      case 'clearTagClipboard':
        sessions.clearClipboard();
      case 'pasteTag':
        if (args['asNew'] == true) {
          sessions.pasteTagAsNew();
        } else {
          sessions.pasteTag(after: (args['after'] as num?)?.toInt());
        }
      case 'new':
        sessions.add(
          SpriteDocument.create(
            (args['width'] as num?)?.toInt() ?? 32,
            (args['height'] as num?)?.toInt() ?? 32,
          ),
          unsaved: true,
        );
      case 'recover':
      case 'discardRecovery':
        break;
      case 'frameImage':
      case 'thumbnails':
      case 'previewStroke':
        return engine.invoke(method, args);
      default:
        engine.invoke(method, args);
    }
    return sessions.state();
  }
}
