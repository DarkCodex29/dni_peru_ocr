import 'package:flutter_test/flutter_test.dart';
import 'package:dni_peru_ocr/src/breadcrumb_throttle.dart';

// ── Tests ─────────────────────────────────────────────────────────────────────
//
// `BreadcrumbThrottle.tryAcquire(nowMs)` is a pure stateful gate used to cap
// Sentry breadcrumbs emitted from the camera image stream to at most one per
// `intervalMs` interval (default 1000ms).
//
// Contract:
//   - First call → true (acquires) and records nowMs as the last emit.
//   - Subsequent call within `intervalMs` of the last emit → false (drops).
//   - Subsequent call at or after `intervalMs` since the last emit → true.
//
// Pure: no `DateTime.now()` inside — the caller passes `nowMs`. This makes the
// helper deterministic and testable without faking time.
void main() {
  group('BreadcrumbThrottle.tryAcquire — 1Hz cap', () {
    test('first call → true (no prior emit)', () {
      final t = BreadcrumbThrottle(intervalMs: 1000);
      expect(t.tryAcquire(0), isTrue);
    });

    test('second call <1s after first → false', () {
      final t = BreadcrumbThrottle(intervalMs: 1000);
      expect(t.tryAcquire(0), isTrue);
      expect(t.tryAcquire(500), isFalse);
      expect(t.tryAcquire(999), isFalse);
    });

    test('second call exactly at intervalMs → true', () {
      final t = BreadcrumbThrottle(intervalMs: 1000);
      expect(t.tryAcquire(0), isTrue);
      expect(t.tryAcquire(1000), isTrue);
    });

    test('second call after intervalMs → true and resets window', () {
      final t = BreadcrumbThrottle(intervalMs: 1000);
      expect(t.tryAcquire(0), isTrue);
      expect(t.tryAcquire(1200), isTrue);
      // After acquiring at 1200, next call <1s later must drop.
      expect(t.tryAcquire(1500), isFalse);
      expect(t.tryAcquire(2200), isTrue);
    });

    test('custom intervalMs (e.g. 250) is respected', () {
      final t = BreadcrumbThrottle(intervalMs: 250);
      expect(t.tryAcquire(0), isTrue);
      expect(t.tryAcquire(100), isFalse);
      expect(t.tryAcquire(250), isTrue);
    });
  });
}
