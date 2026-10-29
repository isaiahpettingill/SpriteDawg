import '../drafts/workspace_session.dart';
import 'dart:io';

import '../drafts/draft_autosave.dart';
import '../drafts/draft_repository.dart';
import '../drafts/draft_storage.dart';
import 'draft_storage_io.dart';
import 'dart:isolate';

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

import '../engine/aseprite.dart';
import '../engine/editor_engine.dart';
import '../engine/editor_sessions.dart';
import '../engine/document.dart';
import '../engine/default_user_data.dart';
import '../engine/png.dart';
import '../export/export_snapshot.dart';
import 'export_files.dart';

/// Desktop filesystem adapter. The editor always retains a recoverable copy
/// before replacing a project; a cancelled dialog never changes saved state.
class DesktopBackend {
  DesktopBackend({
    Future<String?> Function()? openPath,
    Future<String?> Function(bool png)? savePath,
    Future<Directory> Function()? supportDirectory,
    DraftStorage? draftStorage,
  }) : _openPath = openPath ?? _pickOpen,
       _savePath = savePath ?? _pickSave,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _providedStorage = draftStorage;
  final Future<String?> Function() _openPath;
  final Future<String?> Function(bool png) _savePath;
  final Future<Directory> Function() _supportDirectory;
  final DraftStorage? _providedStorage;
  late DraftRepository drafts;
  late WorkspaceSession workspace;
  String? _storageIssue;
  bool _storeReady = false;
  List<DraftInfo> _catalog = [];
  late final _autosave = DraftAutosave(
    flush: () async {
      if (!_disposed) await invoke('flushDrafts', null);
    },
  );
  bool _disposed = false;
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _autosave.dispose();
    await _queue;
    if (_storeReady) await _flush();
    _autosave.dispose();
    if (_storeReady && drafts.storage is FileDraftStorage) {
      await (drafts.storage as FileDraftStorage).close();
    }
  }

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
  set _recoveryError(String? value) {
    if (sessions.hasDocument) {
      sessions.active.recoveryError = value;
    } else {
      _storageIssue = value;
    }
  }

  static const _ase = XTypeGroup(
    label: 'Aseprite project',
    extensions: ['ase', 'aseprite'],
  );

  Future<void> _refreshDrafts() async {
    try {
      _catalog = await drafts.list();
    } catch (error) {
      _recoveryError =
          'Draft storage could not be read: $error. Save a copy now.';
    }
  }

  Future<void> _init() async {
    if (_base != null) return;
    _base = await _supportDirectory();
    await _base!.create(recursive: true);
    drafts = DraftRepository(_providedStorage ?? FileDraftStorage(_base!));
    _storeReady = true;
    await _refreshDrafts();
    for (final draft in _catalog) {
      if (draft.id >= sessions.nextId) sessions.nextId = draft.id + 1;
    }
    workspace = WorkspaceSession(drafts, sessions);
    await workspace.restore();
  }

  Map<String, dynamic> _state() {
    final opened = sessions.documents.map((s) => s.id).toSet();
    final available = _catalog.where((d) => !opened.contains(d.id)).toList();
    return {
      ...sessions.state(),
      'drafts': available.map((d) => d.toMap()).toList(),
      'recoveryAvailable': available.isNotEmpty,
      if (_storageIssue != null) 'recoveryError': _storageIssue,
      ...workspace.state,
    };
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

  Future<void> _persist(EditorSession session) async {
    try {
      final info = await drafts.save(
        id: session.id,
        title: session.title,
        source: session.source ?? session.path,
        document: session.engine.document,
      );
      _catalog.removeWhere((d) => d.id == session.id);
      _catalog.add(info);
      session.engine.recoveryAvailable = true;
      session.recoveryError = null;
    } catch (error) {
      session.recoveryError =
          'Draft could not be written: $error. Save a copy now.';
    }
  }

  Future<void> _flush() async {
    final pending = _autosave.takePending().toSet();
    // Retry failed writes at an explicit lifecycle/save boundary too.
    for (final session in sessions.documents) {
      if (pending.contains(session.id) || session.recoveryError != null) {
        await _persist(session);
      }
    }
    await workspace.save();
  }

  Future<Map<String, dynamic>?> invoke(
    String method,
    Map<String, dynamic>? arguments,
  ) {
    if (_disposed) return Future.error(StateError('Editor has been closed'));
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
    final defaultText = const {'init', 'new', 'closeDocument'}.contains(method)
        ? defaultUserData(args)
        : '';
    if (!sessions.hasDocument &&
        !const {
          'init',
          'state',
          'new',
          'open',
          'openExternal',
          'recover',
          'listDrafts',
          'discardRecovery',
          'flushDrafts',
          'clearTagClipboard',
        }.contains(method) &&
        !(method == 'pasteTag' && args['asNew'] == true)) {
      throw StateError('Create or open a drawing first.');
    }
    switch (method) {
      case 'init':
        sessions.initializePlaceholder(defaultText);
      case 'state':
        break;
      case 'saveExport':
        await _flush();
        return ExportFiles().save(args);
      case 'exportSnapshot':
        // Isolate message transfer detaches the model; avoid a second deep copy.
        final snapshot = engine.document;
        final frame = engine.frame;
        return Isolate.run(() => exportSnapshot(snapshot, frame, args));
      case 'thumbnails':
      case 'copyRegion':
      case 'frameImage':
      case 'previewStroke':
        return engine.invoke(method, args);
      case 'open':
      case 'openExternal':
        // A modal picker blocks this command queue; protect pending edits first.
        await _flush();
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
        opened.source = file.path;
        _autosave.mark(opened.id);
        await _flush();
      case 'save':
      case 'saveAs':
        var path = method == 'save' ? _path : null;
        if (path == null) {
          await _flush();
          final chosen = await _savePath(false);
          if (chosen == null) break;
          path = chosen;
        }
        final bytes = _validated();
        await _persist(sessions.active);
        await _atomic(File(path), bytes);
        _path = path;
        sessions.active.source = path;
        sessions.active.title = path.split('/').last;
        engine.saved();
        await _persist(sessions.active);
      case 'exportPng':
        await _flush();
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
      case 'flushDrafts':
        await _flush();
      case 'listDrafts':
        await _refreshDrafts();
      case 'recover':
        await _refreshDrafts();
        final requested = (args['id'] as num?)?.toInt();
        final opened = sessions.documents.map((s) => s.id).toSet();
        final candidates = _catalog
            .where(
              (d) => requested == null
                  ? !opened.contains(d.id) && d.error == null
                  : d.id == requested,
            )
            .toList();
        require(
          candidates.isNotEmpty,
          'No readable draft was selected. Stored drafts were kept.',
        );
        String? remainingIssue;
        for (final candidate in candidates) {
          try {
            require(
              !opened.contains(candidate.id),
              'This draft is already open.',
            );
            final snapshot = await drafts.load(candidate.id);
            final restored = sessions.restoreDecoded([
              MapEntry(candidate.id, snapshot.document),
            ]).single;
            restored.title = snapshot.info.title;
            restored.source = snapshot.source;
            restored.engine.recoveryAvailable = true;
            sessions.select(restored.id);
          } catch (error) {
            if (requested != null) rethrow;
            remainingIssue =
                'Some drafts could not be opened and were kept: $error';
          }
        }
        if (remainingIssue != null) _recoveryError = remainingIssue;
      case 'discardRecovery':
        final requested = (args['id'] as num?)?.toInt();
        final opened = sessions.documents.map((s) => s.id).toSet();
        require(
          requested == null || !opened.contains(requested),
          'Close the open document before discarding its draft.',
        );
        for (final candidate in _catalog.toList()) {
          if (!opened.contains(candidate.id) &&
              (requested == null || candidate.id == requested)) {
            await drafts.delete(candidate.id);
            _catalog.removeWhere((d) => d.id == candidate.id);
          }
        }
      case 'selectDocument':
        sessions.select((args['id'] as num).toInt());
      case 'closeDocument':
        final id = (args['id'] as num).toInt();
        final matches = sessions.documents.where((s) => s.id == id);
        require(matches.isNotEmpty, 'Document is no longer open');
        final session = matches.first;
        final keep = args['keepDraft'] == true;
        require(
          !session.engine.dirty || args['discard'] == true || keep,
          'Save this document, keep its draft, or confirm discarding changes.',
        );
        if (keep) {
          await _persist(session);
          require(
            session.recoveryError == null,
            'Draft could not be kept. This document remains open. Save a copy first.',
          );
        }
        require(
          await workspace.save(excluding: id, repair: true),
          'The closed tab could not be remembered. This drawing remains open.',
        );
        if (!keep) {
          try {
            await drafts.delete(id);
          } catch (_) {
            // The tab remains open; restore its manifest entry on failed delete.
            await workspace.save(repair: true);
            rethrow;
          }
          _catalog.removeWhere((d) => d.id == id);
        }
        _autosave.forget(id);
        sessions.close(id, discard: args['discard'] == true || keep);
        sessions.initializePlaceholder(defaultText);
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
        _autosave.mark(sessions.activeId);
        await _flush();
      case 'new':
        sessions.add(
          newSprite(
            WorkspaceSession.dimension(args['width'] ?? workspace.lastNewWidth),
            WorkspaceSession.dimension(
              args['height'] ?? workspace.lastNewHeight,
            ),
            defaultText,
          ),
          unsaved: true,
        );
        _autosave.mark(sessions.activeId);
        workspace.lastNewWidth = engine.document.width;
        workspace.lastNewHeight = engine.document.height;
        await _flush();
      default:
        engine.invoke(method, args);
        if (method == 'new') {
          _path = null;
          engine.dirty = true;
        }
        if (['new', 'stroke', 'edit', 'undo', 'redo'].contains(method)) {
          _autosave.mark(sessions.activeId);
        }
    }
    if (const {
      'init',
      'new',
      'open',
      'openExternal',
      'save',
      'saveAs',
      'selectDocument',
      'closeDocument',
      'recover',
      'pasteTag',
    }.contains(method)) {
      await workspace.save(
        repair: const {
          'new',
          'open',
          'openExternal',
          'recover',
          'pasteTag',
          'closeDocument',
        }.contains(method),
      );
    }
    return _state();
  }
}
