import 'document.dart';
import 'aseprite.dart';
import 'editor_engine.dart';
import 'tag_transfer.dart';

class EditorSession {
  EditorSession(this.id, {String? title}) : title = title ?? 'Untitled $id';
  final int id;
  final EditorEngine engine = EditorEngine();
  String title;
  bool placeholder = true;
  String? path, recoveryError;
}

/// Document ownership is independent from viewport selection. Switching never
/// serializes through a shared engine, so undo and selected layer/frame survive.
class EditorSessions {
  EditorSessions({this.residentBudget = 64 * 1024 * 1024}) {
    configure(documents.first);
  }
  final int residentBudget;
  static int _userBytes(UserData? d) =>
      (d?.text?.length ?? 0) * 2 + (d?.properties?.length ?? 0) + 16;
  static int documentBytes(SpriteDocument d) =>
      1024 +
      (d.header?.length ?? 0) +
      _userBytes(d.data) +
      d.layers.fold<int>(
        0,
        (n, l) =>
            n + l.name.length * 2 + (l.uuid?.length ?? 0) + _userBytes(l.data),
      ) +
      d.tags.fold<int>(
        0,
        (n, t) => n + t.name.length * 2 + t.color.length + _userBytes(t.data),
      ) +
      d.frames.fold<int>(
        0,
        (n, f) =>
            n +
            64 +
            f.palette.length * 8 +
            f.paletteNames.values.fold<int>(0, (n, v) => n + v.length * 2) +
            f.metadata.fold<int>(0, (n, m) => n + m.bytes.length) +
            f.cels.fold<int>(
              0,
              (n, c) =>
                  n +
                  (c == null
                      ? 0
                      : 64 + c.pixels.length * 4 + _userBytes(c.data)),
            ),
      );
  void configure(EditorSession session) {
    session.engine.historyBudgetBytes = 8 * 1024 * 1024;
    session.engine.validateCandidate = (candidate) =>
        _checkBudget(candidate: candidate, replacing: session.id);
  }

  void _checkBudget({
    SpriteDocument? candidate,
    int? replacing,
    SpriteDocument? newClipboard,
  }) {
    final clip = newClipboard ?? clipboard;
    final total =
        documents
            .where((s) => s.id != replacing)
            .fold<int>(0, (n, s) => n + documentBytes(s.engine.document)) +
        (candidate == null ? 0 : documentBytes(candidate)) +
        (clip == null ? 0 : documentBytes(clip));
    require(
      total <= residentBudget,
      'Open documents and copied tag exceed the 64 MiB editing budget. Close a document or clear the copied tag; no work was changed.',
    );
  }

  final List<EditorSession> documents = [EditorSession(1)];
  int activeId = 1, nextId = 2;
  SpriteDocument? clipboard;
  EditorSession get active => documents.firstWhere((s) => s.id == activeId);
  EditorSession add(
    SpriteDocument document, {
    String? title,
    bool unsaved = false,
  }) {
    _checkBudget(
      candidate: document,
      replacing:
          documents.length == 1 &&
              documents.first.placeholder &&
              !documents.first.engine.dirty
          ? documents.first.id
          : null,
    );
    if (documents.length == 1 &&
        documents.first.placeholder &&
        !documents.first.engine.dirty) {
      documents.clear();
    }
    require(
      documents.length < 8,
      'Close a document before opening another (8 maximum).',
    );
    final session = EditorSession(nextId++, title: title);
    configure(session);
    session.placeholder = false;
    session.engine.replace(document, unsaved: unsaved);
    documents.add(session);
    activeId = session.id;
    return session;
  }

  void select(int id) {
    require(documents.any((s) => s.id == id), 'Document is no longer open');
    activeId = id;
  }

  void close(int id, {bool discard = false}) {
    final index = documents.indexWhere((s) => s.id == id);
    require(index >= 0, 'Document is no longer open');
    require(
      !documents[index].engine.dirty || discard,
      'Save this document or confirm discarding its unsaved changes.',
    );
    documents.removeAt(index);
    if (documents.isEmpty) {
      final blank = EditorSession(nextId++);
      configure(blank);
      documents.add(blank);
    }
    if (activeId == id) {
      activeId = documents[index.clamp(0, documents.length - 1)].id;
    }
  }

  void copyTag(int index) {
    final section = copyTagSection(active.engine.document, index);
    _checkBudget(newClipboard: section);
    clipboard = section;
  }

  void clearClipboard() {
    clipboard = null;
  }

  void validateRecoveryCandidates(
    List<SpriteDocument> recovered,
    Set<int> replacing,
  ) {
    final remaining = documents.where(
      (s) =>
          !replacing.contains(s.id) &&
          !(documents.length == 1 && s.placeholder && !s.engine.dirty),
    );
    final total =
        remaining.fold<int>(0, (n, s) => n + documentBytes(s.engine.document)) +
        recovered.fold<int>(0, (n, d) => n + documentBytes(d)) +
        (clipboard == null ? 0 : documentBytes(clipboard!));
    require(
      total <= residentBudget,
      'Recovered documents exceed the 64 MiB editing budget. Existing documents and recovery files were retained.',
    );
  }

  List<EditorSession> restoreDecoded(
    List<MapEntry<int?, SpriteDocument>> items,
  ) {
    final replacing = items.map((i) => i.key).whereType<int>().toSet();
    validateRecoveryCandidates(items.map((i) => i.value).toList(), replacing);
    final staged = documents
        .where(
          (s) => !(documents.length == 1 && s.placeholder && !s.engine.dirty),
        )
        .toList();
    var next = nextId;
    final restored = <EditorSession>[];
    for (final item in items) {
      final index = staged.indexWhere((s) => s.id == item.key);
      final previous = index < 0 ? null : staged[index];
      final id = previous?.id ?? next++;
      final session = EditorSession(
        id,
        title: previous?.title ?? 'Recovered $id',
      );
      session.placeholder = false;
      session.engine.replace(item.value, unsaved: true);
      configure(session);
      if (index < 0) {
        staged.add(session);
      } else {
        staged[index] = session;
      }
      restored.add(session);
    }
    require(
      staged.length <= 8,
      'Close documents before recovering more (8 maximum).',
    );
    if (items.isEmpty) return restored;
    documents
      ..clear()
      ..addAll(staged);
    nextId = next;
    if (!documents.any((s) => s.id == activeId)) activeId = restored.last.id;
    return restored;
  }

  void pasteTag({int? after}) {
    final section = clipboard;
    require(section != null, 'Copy a tag section first');
    active.engine.applyDocumentEdit(
      (d) => pasteTagSection(d, after ?? active.engine.frame, section!),
    );
  }

  void pasteTagAsNew() {
    final section = clipboard;
    require(section != null, 'Copy a tag section first');
    add(
      AsepriteCodec.decode(AsepriteCodec.encode(section!)),
      title: section.tags.single.name,
      unsaved: true,
    );
  }

  Map<String, dynamic> state() => {
    ...active.engine.state(),
    'documentId': activeId,
    'hasTagClipboard': clipboard != null,
    'recoveryError': active.recoveryError,
    'documents': documents
        .map(
          (s) => {
            'id': s.id,
            'title': s.title,
            'dirty': s.engine.dirty,
            'recoveryError': s.recoveryError,
            'active': s.id == activeId,
          },
        )
        .toList(),
  };
}
