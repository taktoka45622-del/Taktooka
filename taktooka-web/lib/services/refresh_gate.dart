import 'dart:async';

class RefreshGate {
  Future<void>? _running;
  Completer<void>? _queued;
  bool _queuedFull = false;

  Future<void> run(
    Future<void> Function(bool full) task, {
    bool full = true,
    bool queue = true,
  }) {
    if (_running != null) {
      if (!queue) return _running!;
      _queued ??= Completer<void>();
      _queuedFull = _queuedFull || full;
      return _queued!.future;
    }
    final completion = Completer<void>();
    _running = completion.future;
    unawaited(_execute(task, full, completion));
    return completion.future;
  }

  Future<void> _execute(
    Future<void> Function(bool full) task,
    bool full,
    Completer<void> completion,
  ) async {
    Object? error;
    StackTrace? trace;
    try {
      await task(full);
    } catch (e, stack) {
      error = e;
      trace = stack;
    } finally {
      final queued = _queued;
      final queuedFull = _queuedFull;
      _queued = null;
      _queuedFull = false;
      _running = queued?.future;
      if (queued != null) unawaited(_execute(task, queuedFull, queued));
      if (error == null) {
        completion.complete();
      } else {
        completion.completeError(error, trace);
      }
    }
  }
}

bool sameSnapshot(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    final keys = a.keys.where((key) => key != 'server_now').toSet();
    final otherKeys = b.keys.where((key) => key != 'server_now').toSet();
    return keys.length == otherKeys.length &&
        keys.every((key) => b.containsKey(key) && sameSnapshot(a[key], b[key]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!sameSnapshot(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
