import 'dart:typed_data';

/// App-owned persistent storage. Implementations commit the new generation
/// atomically and keep the supplied last validated generation independently.
abstract interface class DraftStorage {
  Future<List<int>> ids();
  Future<List<Uint8List>> read(int id);
  Future<void> write(int id, Uint8List bytes, {Uint8List? previous});
  Future<void> delete(int id);
}

/// Optional physical accounting, including damaged generations and write temps.
abstract interface class SizedDraftStorage implements DraftStorage {
  Future<int> totalBytes();
}

/// The last open tab set is separate from recoverable, explicitly closed drafts.
/// Implementations use the same exclusive ownership as the draft store.
abstract interface class WorkspaceStorage implements DraftStorage {
  Future<String?> readWorkspace();
  Future<void> writeWorkspace(String value);
  Future<void> archiveWorkspace();
}
