import 'dart:async';

/// Coalesce rapid edits, but never postpone a continuous drawing indefinitely.
/// The owner enqueues [flush] on its document command queue, so selection, save,
/// close and discard cannot race a snapshot or resurrect an obsolete draft.
class DraftAutosave {
  DraftAutosave({
    required this.flush,
    this.delay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 2),
  });
  final Future<void> Function() flush;
  final Duration delay, maxDelay;
  final Set<int> _pending = {};
  Timer? _timer, _deadline;

  void mark(int id) {
    _pending.add(id);
    _timer?.cancel();
    _timer = Timer(delay, _run);
    _deadline ??= Timer(maxDelay, _run);
  }

  void _run() {
    _cancelTimers();
    // Owners report storage errors through their per-document recovery state.
    unawaited(flush());
  }

  List<int> takePending() {
    _cancelTimers();
    final result = _pending.toList();
    _pending.clear();
    return result;
  }

  void forget(int id) {
    _pending.remove(id);
    if (_pending.isEmpty) _cancelTimers();
  }

  void _cancelTimers() {
    _timer?.cancel();
    _deadline?.cancel();
    _timer = null;
    _deadline = null;
  }

  void dispose() => _cancelTimers();
}
