import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'rgba_image.dart';

/// Bounded, lazy previews. Callers own image clones; eviction never disposes a
/// thumbnail still being painted by an on-screen frame card.
class FrameThumbnailCache {
  FrameThumbnailCache(this.transport);
  final Future<Map<String, dynamic>?> Function(String, Map<String, dynamic>?)
  transport;
  final Map<int, ui.Image> _images = {};
  final Map<int, Completer<ui.Image?>> _pending = {};
  final Map<int, Completer<ui.Image?>> _active = {};
  bool _running = false, _disposed = false;
  int _generation = 0;
  Future<ui.Image?> get(int frame) {
    if (_disposed) return Future.value();
    final cached = _images.remove(frame);
    if (cached != null) {
      _images[frame] = cached;
      return Future.value(cached.clone());
    }
    final epoch = _generation;
    final pending = _pending[frame] ?? _active[frame];
    if (pending != null) {
      return pending.future.then(
        (image) => _disposed || epoch != _generation ? null : image?.clone(),
      );
    }
    final result = Completer<ui.Image?>();
    _pending[frame] = result;
    scheduleMicrotask(_load);
    // The completion carries a cache-owned image; each subscriber gets a clone.
    return result.future.then(
      (image) => _disposed || epoch != _generation ? null : image?.clone(),
    );
  }

  Future<void> _load() async {
    if (_running || _disposed || _pending.isEmpty) return;
    _running = true;
    final epoch = _generation;
    final batch = <int, Completer<ui.Image?>>{};
    for (final frame in _pending.keys.take(32).toList()) {
      batch[frame] = _pending.remove(frame)!;
    }
    _active.addAll(batch);
    final decoded = <int, ui.Image>{};
    try {
      final result = await transport('thumbnails', {
        'frames': batch.keys.toList(),
        'maxSize': 48,
      });
      if (!_disposed && epoch == _generation) {
        for (final raw in result?['thumbnails'] as List? ?? const []) {
          final data = Map<String, dynamic>.from(raw as Map);
          final frame = data['frame'] as int;
          final width = data['width'] as int, height = data['height'] as int;
          if (!batch.containsKey(frame) ||
              width < 1 ||
              height < 1 ||
              width > 64 ||
              height > 64 ||
              data['pixels'] is! Uint8List) {
            continue;
          }
          decoded[frame] = await decodeStraightRgba(
            data['pixels'] as Uint8List,
            width: width,
            height: height,
          );
        }
      }
    } catch (_) {
      /* A preview failure must not block drawing or replace state. */
    }
    if (_disposed || epoch != _generation) {
      for (final image in decoded.values) {
        image.dispose();
      }
      for (final complete in batch.values) {
        complete.complete(null);
      }
    } else {
      for (final entry in decoded.entries) {
        _images.remove(entry.key)?.dispose();
        _images[entry.key] = entry.value;
      }
      for (final entry in batch.entries) {
        entry.value.complete(decoded[entry.key]);
      }
      // Complete futures (and their clone callbacks) before disposing LRU entries.
      await Future<void>.value();
      while (_images.length > 64) {
        _images.remove(_images.keys.first)!.dispose();
      }
    }
    for (final entry in batch.entries) {
      if (identical(_active[entry.key], entry.value)) _active.remove(entry.key);
    }
    _running = false;
    if (!_disposed && _pending.isNotEmpty) scheduleMicrotask(_load);
  }

  void invalidate() {
    _generation++;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    for (final complete in _pending.values) {
      complete.complete(null);
    }
    _pending.clear();
    _active.clear();
  }

  void dispose() {
    _disposed = true;
    invalidate();
  }
}
