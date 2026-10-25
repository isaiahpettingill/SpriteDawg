import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import '../engine/aseprite.dart';
import '../engine/editor_engine.dart';
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
  final engine = EditorEngine();
  String? _path;
  File? _recovery;
  String? _recoveryError;
  static const _ase = XTypeGroup(
    label: 'Aseprite project',
    extensions: ['ase', 'aseprite'],
  );
  Future<void> _init() async {
    if (_recovery != null) return;
    final base = await _supportDirectory();
    await base.create(recursive: true);
    _recovery = File('${base.path}/recovery.aseprite');
    engine.recoveryAvailable = await _recovery!.exists();
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
      await _atomic(_recovery!, _validated());
      engine.recoveryAvailable = true;
      _recoveryError = null;
    } catch (e) {
      _recoveryError = 'Recovery could not be written: $e. Save a copy now.';
    }
  }

  Future<void> _clearRecovery() async {
    try {
      if (await _recovery!.exists()) await _recovery!.delete();
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
      case 'open':
        final chosen = await _openPath();
        if (chosen == null) break;
        final file = File(chosen);
        if (await file.length() > AsepriteCodec.maxFile) {
          throw const FormatException('File exceeds the 64 MiB safety limit');
        }
        final bytes = await file.readAsBytes();
        // Decode must succeed completely before changing document/path/history.
        final decoded = AsepriteCodec.decode(bytes);
        engine.replace(decoded);
        _path = chosen;
        await _clearRecovery();
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
        engine.load(await _recovery!.readAsBytes(), unsaved: true);
        _path = null;
      case 'discardRecovery':
        await _clearRecovery();
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
    return {...engine.state(), 'recoveryError': _recoveryError};
  }
}
