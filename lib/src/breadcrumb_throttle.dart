/// Rate-limits breadcrumb emission to at most one per [intervalMs] interval.
///
/// Pure and time-injectable: callers pass `nowMs` so tests stay deterministic
/// and the gate runs without `DateTime.now()` side effects.
///
/// Used by the G.1 KYC telemetry to cap Sentry breadcrumb spam from the
/// per-frame camera image stream (≈10–15 fps after the `% 3` decimation)
/// down to ≤1 breadcrumb/sec while still capturing every gate transition
/// the user perceives.
class BreadcrumbThrottle {
  BreadcrumbThrottle({this.intervalMs = 1000});

  /// Minimum gap between two successful acquisitions, in milliseconds.
  final int intervalMs;

  int? _lastEmitMs;

  /// Returns `true` and records [nowMs] as the most recent emit when the
  /// gap since the last successful acquire is `>= intervalMs` (or this is
  /// the first call). Returns `false` and leaves state untouched otherwise.
  bool tryAcquire(int nowMs) {
    final last = _lastEmitMs;
    if (last == null || nowMs - last >= intervalMs) {
      _lastEmitMs = nowMs;
      return true;
    }
    return false;
  }
}
