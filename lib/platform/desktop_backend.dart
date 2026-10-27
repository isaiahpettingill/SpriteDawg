import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

import '../engine/aseprite.dart';
import '../engine/editor_engine.dart';
import '../engine/editor_sessions.dart';
import '../engine/document.dart';
import '../engine/png.dart';

/// Desktop filesystem adapter. The editor always retains a recoverable copy
/// before replacing a project; a cancelled dialog never changes saved state.
class DesktopBackend {
  DesktopBackend({
    Future<String?> Function()? openPath,
    Future<String?> Function(bool png)? savePath,
    Future<Directory> Function()? supportDirectory,
  }) : _openPath = openPath ?? _pickOpen,
       _savePath = savePath ?? _pickSave,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;
  final Future<String?> Function() _openPath;
  final Future<String?> Function(bool png) _savePath;
  final Future<Directory> Function() _supportDirectory;
  Future<void> _queue = Future<void>.value();
  static Future<String?> _pickOpen() async =>
      (await openFile(acceptedTypeGroups: [_ase]))?.path;
  static Future<String?> _pickSave(bool png) async => (await getSaveLocation(
    suggestedName: png ? 'sprite.png' : 'sprite.aseprite',
    acceptedTypeGroups: png
        ? [
            const XTypeGroup(label: 'PNG image', extensions: ['png']),
          ]
        : [_ase],
  ))?.path;
  final sessions = EditorSessions();
  EditorEngine get engine => sessions.active.engine;
  String? get _path => sessions.active.path;
  set _path(String? value) {
    sessions.active.path = value;
  }

  Directory? _base;
  File get _recovery =>
      File('${_base!.path}/recovery-${sessions.active.id}.aseprite');
  String? get _recoveryError => sessions.active.recoveryError;
  set _recoveryError(String? value) {
    sessions.active.recoveryError = value;
  }

  static const _ase = XTypeGroup(
    label: 'Aseprite project',
    extensions: ['ase', 'aseprite'],
  );
  Future<List<File>> _recoveryFiles() async {
    final files = await _base!
        .list()
        .where(
          (f) =>
              f is File &&
              RegExp(
                r'^recovery(?:-[0-9]+)?\.aseprite$',
              ).hasMatch(f.path.split('/').last),
        )
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<void> _init() async {
    if (_base != null) return;
    _base = await _supportDirectory();
    await _base!.create(recursive: true);
    final files = await _recoveryFiles();
    // Never overwrite an earlier process's recovery before it is recovered.
    for (final file in files) {
      final match = RegExp(
        r'recovery-([0-9]+)\.aseprite$',
      ).firstMatch(file.path);
      if (match != null) {
        final id = int.parse(match.group(1)!);
        if (id >= sessions.nextId) sessions.nextId = id + 1;
      }
    }
    if (files.isNotEmpty) {
      sessions.documents.clear();
      final first = EditorSession(sessions.nextId++);
      sessions.configure(first);
      sessions.documents.add(first);
      sessions.activeId = first.id;
    }
    engine.recoveryAvailable = files.isNotEmpty;
  }

  Future<void> _atomic(File file, Uint8List bytes) async {
    // Same-directory rename is atomic on supported local Linux filesystems.
    final temp = File('${file.path}.spritedawg-$pid.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Uint8List _validated() {
    final bytes = engine.encode();
    AsepriteCodec.decode(bytes);
    return bytes;
  }

  Future<void> _persist() async {
    try {
      await _atomic(_recovery, _validated());
      engine.recoveryAvailable = true;
      _recoveryError = null;
    } catch (e) {
      _recoveryError = 'Recovery could not be written: $e. Save a copy now.';
    }
  }

  Future<void> _clearRecovery() async {
    try {
      if (await _recovery.exists()) await _recovery.delete();
      engine.recoveryAvailable = false;
      _recoveryError = null;
    } catch (e) {
      // The project has already opened/saved successfully. Return its new state
      // even if stale recovery cleanup fails; never strand UI on old pixels.
      _recoveryError =
          'Project is safe, but old recovery could not be removed: $e';
    }
  }

  Future<Map<String, dynamic>?> invoke(
    String method,
    Map<String, dynamic>? arguments,
  ) {
    final result = _queue.then((_) => _invoke(method, arguments));
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<Map<String, dynamic>?> _invoke(
    String method,
    Map<String, dynamic>? arguments,
  ) async {
    await _init();
    final args = arguments ?? <String, dynamic>{};
    switch (method) {
      case 'thumbnails':
      case 'frameImage':
      case 'previewStroke':
        return engine.invoke(method, args);
      case 'open':
      case 'openExternal':
        final chosen = method == 'openExternal'
            ? args['path'] as String?
            : await _openPath();
        if (chosen == null) break;
        if (sessions.documents.length >= 8) {
          throw StateError(
            'Close a document before opening another (8 maximum).',
          );
        }
        final uri = Uri.tryParse(chosen);
        if (uri != null && uri.hasScheme && uri.scheme != 'file') {
          throw const FormatException('Only local project files can be opened');
        }
        final file = uri?.scheme == 'file' ? File.fromUri(uri!) : File(chosen);
        if (await file.length() > AsepriteCodec.maxFile) {
          throw const FormatException('File exceeds the 64 MiB safety limit');
        }
        final bytes = await file.readAsBytes();
        // Decode must succeed completely before changing document/path/history.
        final decoded = AsepriteCodec.decode(bytes);
        final opened = sessions.add(decoded, title: file.path.split('/').last);
        opened.path = file.path;
      case 'save':
      case 'saveAs':
        var path = method == 'save' ? _path : null;
        if (path == null) {
          final chosen = await _savePath(false);
          if (chosen == null) break;
          path = chosen;
        }
        final bytes = _validated();
        await _persist();
        await _atomic(File(path), bytes);
        _path = path;
        sessions.active.title = path.split('/').last;
        engine.saved();
        await _clearRecovery();
      case 'exportPng':
        final chosen = await _savePath(true);
        if (chosen == null) break;
        final state = engine.state();
        final pixels = state['pixels'] as Uint8List;
        final encoded = encodeRgbaPng(
          pixels,
          width: engine.document.width,
          height: engine.document.height,
        );
        await _atomic(File(chosen), encoded);
      case 'recover':
        final files = await _recoveryFiles();
        final existing = sessions.documents.map((s) => s.id).toSet();
        final needed = files.where((f) {
          final m = RegExp(r'recovery-([0-9]+)\.aseprite$').firstMatch(f.path);
          return m == null || !existing.contains(int.parse(m.group(1)!));
        }).length;
        require(
          sessions.documents.length +
                  needed -
                  (sessions.documents.length == 1 &&
                          sessions.active.placeholder &&
                          !engine.dirty
                      ? 1
                      : 0) <=
              8,
          'Close documents before recovering more (8 maximum).',
        );
        var totalBytes = 0;
        for (final file in files) {
          totalBytes += await file.length();
        }
        require(
          totalBytes <= AsepriteCodec.maxFile,
          'Combined recovery exceeds the 64 MiB safety budget. Original recovery files were retained.',
        );
        var decodedPixels = 0;
        final decoded = <File, SpriteDocument>{};
        for (final file in files) {
          if (await file.length() > AsepriteCodec.maxFile) {
            throw const FormatException('Recovery exceeds 64 MiB');
          }
          final doc = AsepriteCodec.decode(await file.readAsBytes());
          decodedPixels += doc.frames.fold<int>(
            0,
            (n, f) =>
                n + f.cels.fold<int>(0, (n, c) => n + (c?.pixels.length ?? 0)),
          );
          require(
            decodedPixels <= 16 * 1024 * 1024,
            'Combined recovery exceeds the decoded-pixel budget. Original recovery files were retained.',
          );
          decoded[file] = doc;
        }
        sessions.validateRecoveryCandidates(
          decoded.values.toList(),
          files
              .map(
                (f) =>
                    RegExp(r'recovery-([0-9]+)\.aseprite$').firstMatch(f.path),
              )
              .whereType<RegExpMatch>()
              .map((m) => int.parse(m.group(1)!))
              .toSet(),
        );
        final restored = sessions.restoreDecoded(
          decoded.entries.map((entry) {
            final match = RegExp(
              r'recovery-([0-9]+)\.aseprite$',
            ).firstMatch(entry.key.path);
            return MapEntry(
              match == null ? null : int.parse(match.group(1)!),
              entry.value,
            );
          }).toList(),
        );
        final selectedAfterRestore = sessions.activeId;
        for (var i = 0; i < restored.length; i++) {
          sessions.select(restored[i].id);
          await _persist();
          final file = files[i];
          if (_recoveryError == null && file.path != _recovery.path) {
            await file.delete();
          }
        }
        sessions.select(selectedAfterRestore);
      case 'discardRecovery':
        // Explicit startup dismissal may remove old-process copies; never delete
        // another currently-open document's recovery.
        final protected = sessions.documents
            .where((s) => s.id != sessions.activeId)
            .map((s) => '${_base!.path}/recovery-${s.id}.aseprite')
            .toSet();
        for (final file in await _recoveryFiles()) {
          if (!protected.contains(file.path)) await file.delete();
        }
        engine.recoveryAvailable = false;
      case 'selectDocument':
        sessions.select((args['id'] as num).toInt());
      case 'closeDocument':
        final id = (args['id'] as num).toInt();
        final matches = sessions.documents.where((s) => s.id == id);
        require(matches.isNotEmpty, 'Document is no longer open');
        require(
          !matches.first.engine.dirty || args['discard'] == true,
          'Save this document or confirm discarding its unsaved changes.',
        );
        final file = File('${_base!.path}/recovery-$id.aseprite');
        if (await file.exists()) await file.delete();
        sessions.close(id, discard: args['discard'] == true);
      case 'clearTagClipboard':
        sessions.clearClipboard();
      case 'copyTag':
        sessions.copyTag((args['index'] as num).toInt());
      case 'pasteTag':
        if (args['asNew'] == true) {
          sessions.pasteTagAsNew();
        } else {
          sessions.pasteTag(after: (args['after'] as num?)?.toInt());
        }
        await _persist();
      case 'new':
        sessions.add(
          SpriteDocument.create(
            (args['width'] as num?)?.toInt() ?? 32,
            (args['height'] as num?)?.toInt() ?? 32,
          ),
          unsaved: true,
        );
        await _persist();
      default:
        engine.invoke(method, args);
        if (method == 'new') {
          _path = null;
          engine.dirty = true;
        }
        if (['new', 'stroke', 'edit', 'undo', 'redo'].contains(method)) {
          await _persist();
        }
    }
    return sessions.state();
  }
}
