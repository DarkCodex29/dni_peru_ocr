import 'dart:async';

/// Manages the lifecycle of ML Kit detectors.
///
/// Stops the image stream, drains in-flight processing, and closes
/// detectors with double-dispose protection.
class DetectorLifecycle {
  DetectorLifecycle({
    required Future<void> Function() stopStream,
    required Future<void> Function() closeDetectors,
  })  : _stopStream = stopStream,
        _closeDetectors = closeDetectors;

  final Future<void> Function() _stopStream;
  final Future<void> Function() _closeDetectors;

  bool _canProcess = true;
  bool _detectorsClosed = false;
  Completer<void>? _inflightCompleter;

  /// Wraps a frame-processing callback with inflight tracking.
  Future<void> trackInflight(Future<void> Function() work) async {
    if (!_canProcess) return;

    _inflightCompleter ??= Completer<void>();
    try {
      await work();
    } on Object catch (_) {
    } finally {
      final completer = _inflightCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    }
  }

  /// Stops the stream, drains in-flight work, and closes detectors. Idempotent.
  Future<void> safeDispose() async {
    if (_detectorsClosed) return;

    _canProcess = false;

    await _stopStream();

    final pending = _inflightCompleter;
    if (pending != null && !pending.isCompleted) {
      await pending.future;
    }

    await Future<void>.delayed(Duration.zero);

    if (!_detectorsClosed) {
      _detectorsClosed = true;
      try {
        await _closeDetectors();
      } on Object catch (_) {}
    }
  }
}
