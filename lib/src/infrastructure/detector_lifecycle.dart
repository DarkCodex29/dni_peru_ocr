import 'dart:async';

/// Manages the lifecycle of ML Kit detectors, ensuring that:
///
/// 1. No new frames are processed after [safeDispose] is called.
/// 2. The image stream is stopped before attempting to close detectors.
/// 3. Any in-flight frame processing is fully awaited before detectors close.
/// 4. An extra event-loop tick is yielded after drain (via [Future.delayed]
///    with [Duration.zero]) so the platform channel reply from MLKit's native
///    `OnSuccessListener` has time to land before `close()` crosses to native.
/// 5. The `closeDetectors` callback is wrapped in try/catch — double-dispose
///    and hot-reload can call it twice; the second call must be swallowed.
/// 6. If the inflight work throws, the [Completer] is still resolved so
///    [safeDispose] never hangs.
///
/// This class exists to eliminate the SIGSEGV in `TfLiteTensorCopyFromBuffer`
/// caused by calling `detector.close()` while MLKit's native Thread-17 is still
/// mid-inference. The old 300 ms `Future.delayed` band-aid was non-deterministic;
/// this class provides hard ordering guarantees through a [Completer]-based drain.
///
/// Both face and text detectors are protected: because `_isProcessing` in
/// `camera_overlay_mask.dart` is a single boolean guard, only one detector
/// runs at a time — a single shared [Completer] therefore covers both paths.
///
/// Usage in a `State.dispose` (sync):
/// ```dart
/// @override
/// void dispose() {
///   _isDisposed = true;
///   unawaited(lifecycle.safeDispose());
///   super.dispose();
/// }
/// ```
///
/// Usage when processing a frame:
/// ```dart
/// void onCameraImage(CameraImage image) {
///   if (_isDisposed) return;
///   unawaited(lifecycle.trackInflight(() => processFrameInner(image)));
/// }
/// ```
class DetectorLifecycle {
  DetectorLifecycle({
    required Future<void> Function() stopStream,
    required Future<void> Function() closeDetectors,
  })  : _stopStream = stopStream,
        _closeDetectors = closeDetectors;

  final Future<void> Function() _stopStream;
  final Future<void> Function() _closeDetectors;

  /// [Hardening 1] Defense-in-depth flag: once flipped false, NO new
  /// [trackInflight] calls are accepted — this is the very first action
  /// in [safeDispose], before stream stop or drain.
  bool _canProcess = true;

  bool _detectorsClosed = false;
  Completer<void>? _inflightCompleter;

  /// Wraps a frame-processing callback with inflight tracking.
  ///
  /// If [safeDispose] has already been called (i.e. [_canProcess] is false),
  /// the [work] is dropped — no native resources are touched after disposal.
  ///
  /// [Hardening 6] If [work] throws, the [Completer] is still resolved via
  /// the finally block's idempotent complete so [safeDispose] never hangs.
  Future<void> trackInflight(Future<void> Function() work) async {
    // [Hardening 1] check _canProcess as the primary gate
    if (!_canProcess) return;

    _inflightCompleter ??= Completer<void>();
    try {
      await work();
    } on Object catch (_) {
      // Intentionally swallow — the caller (camera_overlay_mask) has its own
      // try/catch in _processFrame. We must not re-throw here or the finally
      // block's idempotent complete would need a rethrow, breaking the drain.
    } finally {
      // [Hardening 6] idempotent complete — works whether work() succeeded or
      // threw; a second complete() on the same Completer is guarded explicitly.
      final completer = _inflightCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    }
  }

  /// Safely disposes the lifecycle:
  /// 1. [Hardening 1] Flips [_canProcess] false — no new frames accepted.
  /// 2. Stops the camera stream so no new frames arrive from native.
  /// 3. Awaits any in-flight frame to complete.
  /// 4. [Hardening 2] Yields one event-loop tick ([Future.delayed(Duration.zero)])
  ///    so the platform channel reply from MLKit's `OnSuccessListener` lands
  ///    before crossing close() to native.
  /// 5. [Hardening 3] Closes detectors wrapped in try/catch — idempotent.
  ///
  /// This method is idempotent — calling it multiple times is safe.
  Future<void> safeDispose() async {
    if (_detectorsClosed) return;

    // [Hardening 1] First action: block all new frame processing
    _canProcess = false;

    await _stopStream();

    // Drain any in-flight frame
    final pending = _inflightCompleter;
    if (pending != null && !pending.isCompleted) {
      await pending.future;
    }

    // [Hardening 2] Yield one event-loop tick. The Dart Future for processImage
    // resolving does NOT guarantee MLKit's native OnSuccessListener has fully
    // returned on the platform thread — the platform channel reply lands in a
    // microtask. Duration.zero yields one tick deterministically (NOT a band-aid
    // like 300ms) to let that landing complete before close() crosses to native.
    await Future<void>.delayed(Duration.zero);

    if (!_detectorsClosed) {
      _detectorsClosed = true;
      // [Hardening 3] Wrap in try/catch — double-dispose and hot-reload can
      // call close() twice. iOS changelog (0.2.0) hints it can be buggy on
      // double-close. Survive gracefully.
      try {
        await _closeDetectors();
      } on Object catch (_) {
        // Swallow — detector was already closed or native threw on double-close.
      }
    }
  }
}
