import 'dart:io';
import 'dart:typed_data';

import '../drafts/draft_repository.dart';
import '../drafts/draft_storage.dart';

class FileDraftStorage implements SizedDraftStorage {
  FileDraftStorage(this.directory);
  final Directory directory;
  static final _ownedPaths = <String>{};
  RandomAccessFile? _lock;
  bool _ownsPath = false;
  Future<void>? _opening;

  Future<void> _open() => _opening ??= () async {
    await directory.create(recursive: true);
    final key = directory.absolute.path;
    if (!_ownedPaths.add(key)) {
      throw StateError('Internal drafts are open in another SpriteDawg editor.');
    }
    _ownsPath = true;
    RandomAccessFile? lock;
    try {
      lock = await File('${directory.path}/drafts.lock').open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      _lock = lock;
      await for (final file in directory.list()) {
        if (file is File && RegExp(r'^draft-[0-9]+\.(?:sdd|previous)\.[0-9]+\.tmp$').hasMatch(file.path.split(Platform.pathSeparator).last)) {
          await file.delete();
        }
      }
    } catch (_) {
      await lock?.close();
      _ownedPaths.remove(key);
      _ownsPath = false;
      throw StateError('Internal drafts are open in another SpriteDawg process, or storage is unavailable. Save a copy.');
    }
  }();

  Future<void> close() async {
    if (_opening != null) {
      try { await _opening; } catch (_) {}
    }
    final lock = _lock;
    _lock = null;
    if (_ownsPath) _ownedPaths.remove(directory.absolute.path);
    _ownsPath = false;
    if (lock != null) {
      await lock.unlock();
      await lock.close();
    }
  }

  @override
  Future<int> totalBytes() async {
    await _open();
    var total = 0;
    await for (final file in directory.list()) {
      if (file is File && RegExp(r'^(?:draft-[0-9]+\.|recovery(?:-[0-9]+)?\.aseprite)').hasMatch(file.path.split(Platform.pathSeparator).last)) {
        total += await file.length();
      }
    }
    return total;
  }
  File _current(int id) => File('${directory.path}/draft-$id.sdd');
  File _previous(int id) => File('${directory.path}/draft-$id.previous');
  File _legacy(int id) => File(
    '${directory.path}/recovery${id == 0 ? '' : '-$id'}.aseprite',
  );

  @override
  Future<List<int>> ids() async {
    await _open();
    final ids = <int>{};
    await for (final file in directory.list()) {
      if (file is! File) continue;
      final name = file.path.split(Platform.pathSeparator).last;
      final draft = RegExp(r'^draft-([0-9]+)\.(?:sdd|previous)$').firstMatch(name);
      final old = RegExp(r'^recovery(?:-([0-9]+))?\.aseprite$').firstMatch(name);
      if (draft != null) ids.add(int.parse(draft.group(1)!));
      if (old != null) ids.add(int.parse(old.group(1) ?? '0'));
    }
    return ids.toList()..sort();
  }

  @override
  Future<List<Uint8List>> read(int id) async {
    await _open();
    final result = <Uint8List>[];
    for (final file in [_current(id), _previous(id), _legacy(id)]) {
      if (!await file.exists()) continue;
      if (await file.length() > DraftRepository.maxRecordBytes) {
        // Keep its position so fallback status remains accurate; refuse to load
        // unbounded bytes into memory. A corrupt draft never blocks another.
        result.add(Uint8List(0));
      } else {
        result.add(await file.readAsBytes());
      }
    }
    return result;
  }

  Future<void> _atomic(File file, Uint8List bytes) async {
    final temp = File('${file.path}.$pid.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  @override
  Future<void> write(int id, Uint8List bytes, {Uint8List? previous}) async {
    await _open();
    // If either rename is interrupted, at least one previously valid generation
    // remains. Never replace the backup with an unvalidated corrupt current file.
    if (previous != null) await _atomic(_previous(id), previous);
    await _atomic(_current(id), bytes);
    final legacy = _legacy(id);
    if (await legacy.exists()) await legacy.delete();
  }

  @override
  Future<void> delete(int id) async {
    await _open();
    for (final file in [_current(id), _previous(id), _legacy(id)]) {
      if (await file.exists()) await file.delete();
    }
  }
}
