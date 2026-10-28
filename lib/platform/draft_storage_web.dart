import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../drafts/draft_storage.dart';

/// Origin-private IndexedDB storage. Both generations commit in one transaction;
/// quota failures leave the last committed drawing untouched. Browsers may still
/// evict site data, and private sessions may remove it when their window closes.
class IndexedDbDraftStorage implements SizedDraftStorage {
  IndexedDbDraftStorage({this.databaseName = 'spritedawg.drafts.v1'});

  final String databaseName;
  Future<web.IDBDatabase>? _opening;
  Future<void>? _acquiring;
  Completer<JSAny?>? _release;
  Future<JSAny?>? _held;
  static const _current = 'current';
  static const _previous = 'previous';
  static const _sizes = 'sizes';

  Future<web.IDBDatabase> _open() => _opening ??= _openOwnedDatabase();

  Future<web.IDBDatabase> _openOwnedDatabase() async {
    try {
      await (_acquiring ??= _acquireOwnership());
      return await _openDatabase();
    } catch (_) {
      _opening = null;
      await _releaseOwnership();
      rethrow;
    }
  }

  Future<void> _acquireOwnership() async {
    final manager = web.window.navigator.locks;
    if (manager.isUndefinedOrNull) {
      throw UnsupportedError(
        'This browser does not support safe draft ownership. Download your drawing.',
      );
    }
    final acquired = Completer<void>();
    final release = Completer<JSAny?>();
    _release = release;
    _held = manager
        .request(
          '$databaseName.writer',
          web.LockOptions(mode: 'exclusive', ifAvailable: true),
          ((web.Lock? lock) {
            if (lock == null) {
              acquired.completeError(
                StateError(
                  'Draft storage is open in another tab. Close that tab and retry.',
                ),
              );
              return null;
            }
            acquired.complete();
            return release.future.toJS;
          }).toJS,
        )
        .toDart;
    unawaited(
      _held!.then<void>(
        (_) {
          if (!acquired.isCompleted) {
            acquired.completeError(
              StateError('Browser draft ownership was not granted'),
            );
          }
        },
        onError: (Object error) {
          if (!acquired.isCompleted) acquired.completeError(error);
        },
      ),
    );
    await acquired.future;
  }

  Future<void> _releaseOwnership() async {
    final release = _release;
    if (release != null && !release.isCompleted) release.complete(null);
    final held = _held;
    if (held != null) {
      try {
        await held;
      } catch (_) {
        // Ownership denial has already been surfaced by the opening operation.
      }
    }
    _release = null;
    _held = null;
    _acquiring = null;
  }

  Future<web.IDBDatabase> _openDatabase() {
    final done = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(databaseName, 1);
    request.addEventListener(
      'upgradeneeded',
      ((web.Event _) {
        final database = request.result as web.IDBDatabase;
        database.createObjectStore(_current);
        database.createObjectStore(_previous);
        database.createObjectStore(_sizes);
      }).toJS,
    );
    request.addEventListener(
      'success',
      ((web.Event _) {
        final database = request.result as web.IDBDatabase;
        database.addEventListener(
          'versionchange',
          ((web.Event _) {
            database.close();
            _opening = null;
          }).toJS,
        );
        if (done.isCompleted) {
          database.close();
        } else {
          done.complete(database);
        }
      }).toJS,
    );
    void fail(String message) {
      _opening = null;
      if (!done.isCompleted) done.completeError(StateError(message));
    }

    request.addEventListener(
      'error',
      ((web.Event _) {
        fail(request.error?.message ?? 'Browser draft storage is unavailable');
      }).toJS,
    );
    request.addEventListener(
      'blocked',
      ((web.Event _) {
        fail(
          'Another browser tab is blocking draft storage. Close it and retry.',
        );
      }).toJS,
    );
    return done.future;
  }

  Future<JSAny?> _request(web.IDBRequest request) {
    final done = Completer<JSAny?>();
    request.addEventListener(
      'success',
      ((web.Event _) => done.complete(request.result)).toJS,
    );
    request.addEventListener(
      'error',
      ((web.Event _) {
        done.completeError(
          StateError(request.error?.message ?? 'Could not read browser drafts'),
        );
      }).toJS,
    );
    return done.future;
  }

  Future<void> _commit(web.IDBTransaction transaction) {
    final done = Completer<void>();
    transaction.addEventListener(
      'complete',
      ((web.Event _) => done.complete()).toJS,
    );
    transaction.addEventListener(
      'abort',
      ((web.Event _) {
        if (!done.isCompleted) {
          done.completeError(
            StateError(
              transaction.error?.message ?? 'Browser draft transaction failed',
            ),
          );
        }
      }).toJS,
    );
    return done.future;
  }

  @override
  Future<List<int>> ids() async {
    final database = await _open();
    final transaction = database.transaction(
      [_current.toJS, _previous.toJS].toJS,
      'readonly',
    );
    // Queue every request before awaiting: IndexedDB may auto-commit once the
    // event loop has no pending requests in this transaction.
    final requests = [
      _request(transaction.objectStore(_current).getAllKeys()),
      _request(transaction.objectStore(_previous).getAllKeys()),
    ];
    final keys = <int>{};
    for (final value in await Future.wait(requests)) {
      for (final key in (value as JSArray<JSAny?>).toDart) {
        final parsed = key.dartify();
        if (parsed is num && parsed > 0 && parsed == parsed.toInt()) {
          keys.add(parsed.toInt());
        }
      }
    }
    return keys.toList()..sort();
  }

  @override
  Future<List<Uint8List>> read(int id) async {
    final database = await _open();
    final transaction = database.transaction(
      [_current.toJS, _previous.toJS].toJS,
      'readonly',
    );
    final requests = [
      _request(transaction.objectStore(_current).get(id.toJS)),
      _request(transaction.objectStore(_previous).get(id.toJS)),
    ];
    return [
      for (final value in await Future.wait(requests))
        if (value != null) Uint8List.fromList((value as JSUint8Array).toDart),
    ];
  }

  @override
  Future<void> write(int id, Uint8List bytes, {Uint8List? previous}) async {
    final database = await _open();
    final transaction = database.transaction(
      [_current.toJS, _previous.toJS, _sizes.toJS].toJS,
      'readwrite',
      web.IDBTransactionOptions(durability: 'strict'),
    );
    final committed = _commit(transaction);
    transaction.objectStore(_current).put(bytes.toJS, id.toJS);
    if (previous == null) {
      transaction.objectStore(_previous).delete(id.toJS);
    } else {
      transaction.objectStore(_previous).put(previous.toJS, id.toJS);
    }
    transaction
        .objectStore(_sizes)
        .put((bytes.length + (previous?.length ?? 0)).toJS, id.toJS);
    await committed;
  }

  @override
  Future<void> delete(int id) async {
    final database = await _open();
    final transaction = database.transaction(
      [_current.toJS, _previous.toJS, _sizes.toJS].toJS,
      'readwrite',
      web.IDBTransactionOptions(durability: 'strict'),
    );
    final committed = _commit(transaction);
    transaction.objectStore(_current).delete(id.toJS);
    transaction.objectStore(_previous).delete(id.toJS);
    transaction.objectStore(_sizes).delete(id.toJS);
    await committed;
  }

  @override
  Future<int> totalBytes() async {
    final database = await _open();
    final transaction = database.transaction(_sizes.toJS, 'readonly');
    final result = await _request(transaction.objectStore(_sizes).getAll());
    var total = 0;
    for (final value in (result as JSArray<JSAny?>).toDart) {
      final bytes = value.dartify();
      if (bytes is! num || bytes < 0 || bytes != bytes.toInt()) {
        throw StateError('Invalid browser draft size metadata');
      }
      total += bytes.toInt();
    }
    return total;
  }

  Future<void> close() async {
    final opening = _opening;
    if (opening != null) {
      try {
        (await opening).close();
      } catch (_) {
        // A failed open has no connection to close.
      }
    }
    _opening = null;
    await _releaseOwnership();
  }
}
