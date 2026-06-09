/// Rate-limits emission to at most one per [intervalMs] interval.
class BreadcrumbThrottle {
  BreadcrumbThrottle({this.intervalMs = 1000});

  final int intervalMs;

  int? _lastEmitMs;

  /// Returns `true` when [nowMs] is at least [intervalMs] after the previous accept.
  bool tryAcquire(int nowMs) {
    final last = _lastEmitMs;
    if (last == null || nowMs - last >= intervalMs) {
      _lastEmitMs = nowMs;
      return true;
    }
    return false;
  }
}
