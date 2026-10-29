import 'dart:convert';

import '../engine/editor_sessions.dart';
import 'draft_repository.dart';
import 'draft_storage.dart';

/// Only a successfully committed open set is restored. Closed recovery copies
/// remain in the independent draft catalog, never silently reopened.
class WorkspaceSession {
  WorkspaceSession(this.drafts, this.sessions);
  final DraftRepository drafts;
  final EditorSessions sessions;
  int lastNewWidth = 32, lastNewHeight = 32;
  String? _restoreError, _saveError;
  String? get error => _saveError ?? _restoreError;
  bool _readable = true;

  Map<String, dynamic> get state => {
    'lastNewWidth': lastNewWidth,
    'lastNewHeight': lastNewHeight,
    if (error != null) 'recoveryError': error,
  };

  static int dimension(dynamic value) {
    if (value is! int || value < 1 || value > 2048) {
      throw const FormatException(
        'Canvas dimensions must be whole numbers from 1 to 2048',
      );
    }
    return value;
  }

  Future<void> restore() async {
    final storage = drafts.storage;
    if (storage is! WorkspaceStorage) return;
    List<dynamic> tabs;
    int? active;
    try {
      final raw = await storage.readWorkspace();
      if (raw == null) return;
      if (raw.length > 65536) {
        throw const FormatException('Workspace too large');
      }
      final data = jsonDecode(raw);
      if (data is! Map || data['version'] != 1 || data['tabs'] is! List) {
        throw const FormatException('Invalid workspace metadata');
      }
      tabs = data['tabs'] as List;
      if (tabs.length > 8) {
        throw const FormatException('Too many workspace tabs');
      }
      lastNewWidth = dimension(data['width']);
      lastNewHeight = dimension(data['height']);
      active = data['active'] as int?;
    } catch (issue) {
      // Do not replace unreadable evidence with an empty startup session.
      _readable = false;
      _restoreError =
          'Last open tabs could not be read. Stored drafts were kept. '
          'Automatic tab remembering is paused. Creating, opening or recovering '
          'a drawing will start a new session while preserving this metadata: $issue';
      return;
    }
    final seen = <int>{};
    for (final tab in tabs) {
      try {
        if (tab is! Map || tab['id'] is! int || !seen.add(tab['id'] as int)) {
          throw const FormatException('Invalid workspace tab');
        }
        final id = tab['id'] as int;
        final snapshot = await drafts.load(id);
        final restored = sessions.restoreDecoded([
          MapEntry(id, snapshot.document),
        ]).single;
        restored.title = snapshot.info.title;
        restored.source = snapshot.source;
        restored.engine.recoveryAvailable = true;
        // Provenance is not write permission. Recovered documents use Save As;
        // startup never touches the original file, including inaccessible files.
        if (snapshot.info.fallback) {
          _restoreError =
              'An older validated draft was restored. Save a copy to keep it.';
        }
      } catch (issue) {
        _readable = false;
        _restoreError =
            'Some open tabs could not be restored. Their drafts were kept: $issue';
      }
    }
    if (sessions.documents.any((s) => s.id == active)) sessions.select(active!);
  }

  Future<bool> save({int? excluding, bool repair = false}) async {
    final storage = drafts.storage;
    if (storage is! WorkspaceStorage) return true;
    if (!_readable && !repair) return false;
    try {
      if (!_readable) await storage.archiveWorkspace();
      var activeId = sessions.activeId;
      if (activeId == excluding) {
        final index = sessions.documents.indexWhere((s) => s.id == excluding);
        final remaining = sessions.documents
            .where((s) => s.id != excluding)
            .toList();
        activeId = remaining.isEmpty
            ? 0
            : remaining[index.clamp(0, remaining.length - 1)].id;
      }
      await storage.writeWorkspace(
        jsonEncode({
          'version': 1,
          'width': lastNewWidth,
          'height': lastNewHeight,
          'active': activeId,
          'tabs': [
            for (final session in sessions.documents)
              if (session.id != excluding)
                {'id': session.id, 'dirty': session.engine.dirty},
          ],
        }),
      );
      _readable = true;
      _saveError = null;
      if (repair) _restoreError = null;
      return true;
    } catch (issue) {
      _saveError = 'Open tabs could not be remembered: $issue. Save a copy now.';
      return false;
    }
  }
}
