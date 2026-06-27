import 'dart:math' as math;

// ignore_for_file: prefer_const_constructors_in_immutables

/// Sealed state for the DNI capture flow.
sealed class DniCaptureState {
  const DniCaptureState();
}

/// [DniCaptureCountingDown] with an embedded wall-clock anchor.
final class CountingDownWithAnchor extends DniCaptureCountingDown {
  const CountingDownWithAnchor({
    required super.guideText,
    required super.elapsedMs,
    required super.totalMs,
    required this.perfectSinceEpochMs,
    this.disturbedSinceEpochMs,
  });

  /// Epoch ms when the countdown started (the first perfectly-held frame).
  final int perfectSinceEpochMs;

  /// Epoch ms when the CURRENT continuous disturbance began, or `null` while
  /// the hold is good. The grace window is measured against the disturbance
  /// DURATION (`now - disturbedSinceEpochMs`), not the total countdown
  /// progress, so a brief handheld jitter pauses — never resets — the dwell.
  /// Only a disturbance that itself spans `gracePeriodMs` aborts the countdown.
  /// Recovering the hold clears it back to `null` (#5532).
  final int? disturbedSinceEpochMs;
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

  final String guideText;
  final String? failingGate;
  final double validationProgress;
  final int stableFrames;
  final bool? userDataMatch;
  final bool manualModeActive;

  bool get isCaptureable => false;
}

/// Auto-capture countdown is running.
final class DniCaptureCountingDown extends DniCaptureState {
  const DniCaptureCountingDown({
    required this.guideText,
    required this.elapsedMs,
    required this.totalMs,
  });

  final String guideText;
  final int elapsedMs;
  final int totalMs;

  double get progress => math.min(1.0, elapsedMs / totalMs);
}

/// Capture in-flight: shutter triggered, waiting for the photo file.
final class DniCaptureInFlight extends DniCaptureState {
  const DniCaptureInFlight({required this.showFlash});

  final bool showFlash;
}

/// Document expired.
final class DniCaptureExpired extends DniCaptureState {
  const DniCaptureExpired(this.expirationDate);

  final DateTime expirationDate;
}

/// Capture completed successfully; result was emitted to the host.
final class DniCaptureDone extends DniCaptureState {
  const DniCaptureDone();
}
