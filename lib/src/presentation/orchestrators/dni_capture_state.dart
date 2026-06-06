import 'dart:math' as math;

// ignore_for_file: prefer_const_constructors_in_immutables

/// Sealed state for the DNI capture flow.
///
/// Managed by [DniCaptureOrchestrator] (state machine) and observed by
/// [DniCameraController] via a [ValueNotifier]. The widget reads it through a
/// [ValueListenableBuilder] — one rebuild per real state transition.
sealed class DniCaptureState {
  const DniCaptureState();
}

// ─── Internal anchor subclass ──────────────────────────────────────────────
// Lives in the same library as the sealed hierarchy so it can extend
// the final DniCaptureCountingDown.
//
// This type is an implementation detail of DniCaptureOrchestrator and is
// NOT exported from the barrel. It is visible to code within
// lib/src/presentation/orchestrators/ through Dart's library mechanism
// (same package, same directory, no `part` needed — package-private by
// convention since it is not re-exported from dni_peru_ocr.dart).

/// [DniCaptureCountingDown] with an embedded wall-clock anchor.
///
/// Allows the orchestrator to remain stateless: the countdown start time
/// travels with the state value rather than being held by the orchestrator.
/// The [DniCameraController] treats this exactly like [DniCaptureCountingDown]
/// (it's a valid subtype); the orchestrator downcasts to read [perfectSinceEpochMs].
final class CountingDownWithAnchor extends DniCaptureCountingDown {
  const CountingDownWithAnchor({
    required super.guideText,
    required super.elapsedMs,
    required super.totalMs,
    required this.perfectSinceEpochMs,
  });

  /// Epoch milliseconds when the countdown began (first captureable frame).
  final int perfectSinceEpochMs;
}

/// Stream running; waiting for a captureable frame.
final class DniCaptureScanning extends DniCaptureState {
  const DniCaptureScanning({
    required this.guideText,
    required this.failingGate,
    required this.validationProgress,
    required this.stableFrames,
    required this.userDataMatch,
    required this.manualModeActive,
  });

  /// User-facing instruction shown below the mask hole.
  final String guideText;

  /// The gate that rejected the last frame, or `null` when all gates passed.
  /// Stable codes (Sentry filters): `min_blocks`, `centering`, `fill_high`,
  /// `fill_low`, `line_count`, `tilt`.
  final String? failingGate;

  /// 0..1 progress for the countdown arc (always 0 in scanning state).
  final double validationProgress;

  /// Consecutive stable frames observed so far.
  final int stableFrames;

  /// `null` = no user data to match; `true` = matched; `false` = mismatch.
  final bool? userDataMatch;

  /// When `true`, the manual-capture tap target is visible.
  final bool manualModeActive;

  /// Scanning state is never captureable — countdown hasn't started yet.
  bool get isCaptureable => false;
}

/// Auto-capture countdown is running (document held in frame, all gates green).
final class DniCaptureCountingDown extends DniCaptureState {
  const DniCaptureCountingDown({
    required this.guideText,
    required this.elapsedMs,
    required this.totalMs,
  });

  /// User-facing instruction.
  final String guideText;

  /// Milliseconds elapsed since the countdown started.
  final int elapsedMs;

  /// Total milliseconds required to trigger auto-capture.
  final int totalMs;

  /// 0..1 countdown progress, clamped to the range `[0, 1]`.
  double get progress => math.min(1.0, elapsedMs / totalMs);
}

/// Capture in-flight: shutter triggered, waiting for the photo file.
final class DniCaptureInFlight extends DniCaptureState {
  const DniCaptureInFlight({required this.showFlash});

  /// Whether the capture-flash overlay should be shown.
  final bool showFlash;
}

/// Document expired — stream stopped; caller should prompt re-issue.
final class DniCaptureExpired extends DniCaptureState {
  const DniCaptureExpired(this.expirationDate);

  /// The MRZ-parsed expiration date (past relative to today).
  final DateTime expirationDate;
}

/// Capture completed successfully; result was emitted to the host.
final class DniCaptureDone extends DniCaptureState {
  const DniCaptureDone();
}
