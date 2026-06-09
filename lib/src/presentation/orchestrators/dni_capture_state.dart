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
  });

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
