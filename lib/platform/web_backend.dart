import '../drafts/workspace_session.dart';
import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart' as picker;
import 'package:web/web.dart' as web;

import '../drafts/draft_autosave.dart';
import '../drafts/draft_repository.dart';
import '../drafts/draft_storage.dart';
import '../engine/aseprite.dart';
import '../engine/default_user_data.dart';
import '../engine/document.dart';
import '../engine/editor_engine.dart';
import '../engine/editor_sessions.dart';
import '../engine/png.dart';
import '../export/export_snapshot.dart';
import 'draft_storage_web.dart';

/// Browser drafts stay in origin-private IndexedDB, separate from downloads.
/// A download creates a copy, never filesystem overwrite access. Browser site
/// data can be cleared/evicted; important drawings should also be downloaded.
class DesktopBackend {
  DesktopBackend({
    Future<picker.XFile?> Function()? openFile,
    Future<void> Function(String, Uint8List)? download,
    DraftStorage? draftStorage,
  }) : _openFile = openFile ?? _pickOpen,
       _download = download ?? _downloadFile,
       _drafts = DraftRepository(draftStorage ?? IndexedDbDraftStorage()) {
    _autosave = DraftAutosave(
      flush: () async {
        if (!_closing) await invoke('flushDrafts', null);
      },
    );
    _beforeUnload = ((web.Event event) {
      if (sessions.documents.any((s) => s.engine.dirty)) {
        event.preventDefault();
        (event as web.BeforeUnloadEvent).returnValue = '';
      }
    }).toJS;
    _visibility = ((web.Event _) {
      if (web.document.visibilityState == 'hidden') _flushInBackground();
    }).toJS;
    _pageHide = ((web.Event _) => _flushInBackground()).toJS;
    web.window.addEventListener('beforeunload', _beforeUnload);
    web.document.addEventListener('visibilitychange', _visibility);
    web.window.addEventListener('pagehide', _pageHide);
  }
  final Future<picker.XFile?> Function() _openFile;
  final Future<void> Function(String, Uint8List) _download;
  final DraftRepository _drafts;
  late final workspace = WorkspaceSession(_drafts, sessions);
  late final DraftAutosave _autosave;
  late final JSFunction _beforeUnload, _visibility, _pageHide;
  final sessions = EditorSessions();
  EditorEngine get engine => sessions.active.engine;
  Future<void> _queue = Future<void>.value();
  final Set<int> _failed = {};
  List<DraftInfo> _catalog = [];
  String? _storageIssue;
  bool _initialized = false, _closing = false;
  Future<void>? _disposeFuture;
  int _untitled = 1;
  final _random = math.Random.secure();

  void _prepareCreation() {
    final used = {
      ..._catalog.map((draft) => draft.id),
      ...sessions.documents.map((session) => session.id),
    };
    do {
      sessions.nextId =
          _random.nextInt(1 << 26) * (1 << 26) + _random.nextInt(1 << 26) + 2;
    } while (used.contains(sessions.nextId));
  }

  void _flushInBackground() {
    // Browsers need not wait for asynchronous pagehide handlers. Frequent
    // foreground snapshots are the primary protection, not this last chance.
    if (!_closing && _initialized) {
      unawaited(
        invoke('flushDrafts', null).then<void>(
          (_) {},
          onError: (Object error) {
            _storageIssue = 'Browser drafts could not be flushed: $error';
          },
        ),
      );
    }
  }

  Future<void> _init() async {
    if (_initialized) return;
    _initialized = true;
    // Independent tabs must not both allocate document 2 and overwrite one
    // another. Keep a random 52-bit namespace below JavaScript's safe integer
    // ceiling; IDs remain stable in the persisted records and on recovery.
    try {
      _catalog = await _drafts.list();
    } catch (error) {
      _storageIssue =
          'Browser draft storage is unavailable: $error. Download a copy now.';
    }
    _prepareCreation();
    await workspace.restore();
  }

  List<DraftInfo> get _closedDrafts {
    final open = sessions.documents.map((session) => session.id).toSet();
    return _catalog.where((draft) => !open.contains(draft.id)).toList();
  }

  Map<String, dynamic> _state() => {
    ...sessions.state(),
    'drafts': _closedDrafts.map((draft) => draft.toMap()).toList(),
    'recoveryAvailable': _closedDrafts.isNotEmpty,
    'recoveryError':
        _storageIssue ??
        (sessions.hasDocument ? sessions.active.recoveryError : null),
    ...workspace.state,
  };

  Future<void> _persist(EditorSession session) async {
    try {
      final info = await _drafts.save(
        id: session.id,
        title: session.title,
        source: session.source,
        document: session.engine.document,
      );
      _catalog.removeWhere((draft) => draft.id == session.id);
      _catalog.add(info);
      session.engine.recoveryAvailable = true;
      session.recoveryError = null;
      _storageIssue = null;
      _failed.remove(session.id);
    } catch (error) {
      session.recoveryError =
          'Draft could not be saved: $error. Download a copy now.';
      _failed.add(session.id);
    }
  }

  Future<void> _flush() async {
    final ids = {..._autosave.takePending(), ..._failed};
    for (final session in sessions.documents.where((s) => ids.contains(s.id))) {
      await _persist(session);
    }
    await workspace.save();
  }

  Future<void> _refresh() async {
    try {
      _catalog = await _drafts.list();
      _storageIssue = null;
    } catch (error) {
      _storageIssue = 'Browser drafts could not be listed: $error';
    }
  }

  Future<void> _recover(int id) async {
    require(
      !sessions.documents.any((session) => session.id == id),
      'This draft is already open.',
    );
    final snapshot = await _drafts.load(id);
    final restored = sessions.restoreDecoded([
      MapEntry(id, snapshot.document),
    ]).single;
    restored.title = snapshot.info.title;
    restored.source = snapshot.source;
    restored.engine.recoveryAvailable = true;
    sessions.select(restored.id);
  }

  /// Reject new input, but finish every command already accepted by [invoke].
  /// The final snapshot completes before another tab can acquire ownership.
  /// Disposal never throws asynchronously: Flutter's dispose cannot await it.
  Future<void> dispose() {
    final pending = _disposeFuture;
    if (pending != null) return pending;
    _closing = true;
    _autosave.dispose();
    web.document.removeEventListener('visibilitychange', _visibility);
    web.window.removeEventListener('pagehide', _pageHide);
    return _disposeFuture = _finishDispose();
  }

  Future<void> _finishDispose() async {
    try {
      await _queue;
      await _flush();
    } catch (error) {
      _storageIssue =
          'Browser drafts could not be flushed while closing: $error';
    } finally {
      // Keep the close warning until accepted work has had its final flush.
      web.window.removeEventListener('beforeunload', _beforeUnload);
      // Drained commands may have marked another pending debounce timer.
      _autosave.dispose();
      final storage = _drafts.storage;
      if (storage is IndexedDbDraftStorage) {
        try {
          await storage.close();
        } catch (error) {
          _storageIssue =
              'Browser draft storage could not close safely: $error';
        }
      }
    }
  }

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
    if (_closing) {
      return Future.error(
        StateError('The editor is closing; no new commands were accepted.'),
      );
    }
    final result = _queue.then((_) => _invoke(method, arguments ?? {}));
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<Map<String, dynamic>?> _invoke(
    String method,
    Map<String, dynamic> args,
  ) async {
    await _init();
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
      case 'listDrafts':
        await _refresh();
      case 'flushDrafts':
        await _flush();
      case 'open':
        if (sessions.documents.length >= 8) {
          throw StateError(
            'Close a document before opening another (8 maximum).',
          );
        }
        // The picker can remain open indefinitely while blocking this queue.
        await _flush();
        final chosen = await _openFile();
        if (chosen == null) break;
        if (await chosen.length() > AsepriteCodec.maxFile) {
          throw const FormatException('File exceeds the 64 MiB safety limit');
        }
        final document = AsepriteCodec.decode(await chosen.readAsBytes());
        _prepareCreation();
        final imported = sessions.add(document, title: chosen.name);
        imported.source = chosen.name;
        _autosave.mark(imported.id);
        await _flush();
      case 'openExternal':
        throw UnsupportedError('Use Open to choose a local Aseprite file.');
      case 'save':
      case 'saveAs':
        await _flush();
        final bytes = engine.encode();
        AsepriteCodec.decode(bytes);
        var name = sessions.active.title;
        if (!name.toLowerCase().endsWith('.aseprite') &&
            !name.toLowerCase().endsWith('.ase')) {
          name = '$name.aseprite';
        }
        await _download(name, bytes);
        await _flush();
      // Browsers cannot confirm that the user kept a download. Keep dirty so
      // closing the tab still warns; do not falsely claim filesystem saving.
      case 'exportPng':
        await _flush();
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
        await _flush();
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
        final id = (args['id'] as num).toInt();
        final session = sessions.documents.firstWhere((s) => s.id == id);
        final keep = args['keepDraft'] == true;
        require(
          !session.engine.dirty || keep || args['discard'] == true,
          'Save this document or confirm discarding its unsaved changes.',
        );
        if (keep) {
          await _persist(session);
          require(
            session.recoveryError == null,
            session.recoveryError ?? 'Draft save failed',
          );
        }
        require(
          await workspace.save(excluding: id, repair: true),
          'The closed tab could not be remembered. This drawing remains open.',
        );
        if (!keep) {
          try {
            await _drafts.delete(id);
          } catch (_) {
            // The tab remains open; restore its manifest entry on failed delete.
            await workspace.save(repair: true);
            rethrow;
          }
          _catalog.removeWhere((d) => d.id == id);
        }
        _autosave.forget(id);
        _failed.remove(id);
        _prepareCreation();
        sessions.close(id, discard: keep || args['discard'] == true);
        sessions.initializePlaceholder(defaultText);
      case 'copyTag':
        sessions.copyTag((args['index'] as num).toInt());
      case 'clearTagClipboard':
        sessions.clearClipboard();
      case 'pasteTag':
        if (args['asNew'] == true) {
          _prepareCreation();
          sessions.pasteTagAsNew();
        } else {
          sessions.pasteTag(after: (args['after'] as num?)?.toInt());
        }
        _autosave.mark(sessions.activeId);
        await _flush();
      case 'new':
        _prepareCreation();
        sessions.add(
          newSprite(
            WorkspaceSession.dimension(args['width'] ?? workspace.lastNewWidth),
            WorkspaceSession.dimension(
              args['height'] ?? workspace.lastNewHeight,
            ),
            defaultText,
          ),
          title: 'Untitled ${_untitled++}',
          unsaved: true,
        );
        _autosave.mark(sessions.activeId);
        workspace.lastNewWidth = engine.document.width;
        workspace.lastNewHeight = engine.document.height;
        await _flush();
      case 'recover':
        final requested = (args['id'] as num?)?.toInt();
        if (requested != null) {
          await _recover(requested);
        } else {
          for (final draft in _closedDrafts) {
            try {
              await _recover(draft.id);
            } catch (error) {
              _storageIssue =
                  'Some drafts could not be opened and were kept: $error';
            }
          }
        }
      case 'discardRecovery':
        final requested = (args['id'] as num?)?.toInt();
        final ids = requested == null
            ? _closedDrafts.map((draft) => draft.id).toList()
            : [requested];
        for (final id in ids) {
          require(
            !sessions.documents.any((session) => session.id == id),
            'Close this drawing before discarding its draft.',
          );
          await _drafts.delete(id);
          _catalog.removeWhere((draft) => draft.id == id);
          _autosave.forget(id);
          _failed.remove(id);
        }
      case 'copyRegion':
      case 'frameImage':
      case 'thumbnails':
      case 'previewStroke':
        return engine.invoke(method, args);
      default:
        engine.invoke(method, args);
        if (const {'stroke', 'edit', 'undo', 'redo'}.contains(method)) {
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
