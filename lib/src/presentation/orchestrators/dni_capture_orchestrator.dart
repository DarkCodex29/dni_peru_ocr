import '../document_validator.dart';
import 'dni_capture_state.dart';

final class DniCaptureOrchestrator {
  DniCaptureOrchestrator({
    required this.autoCaptureMs,
    required this.gracePeriodMs,
    required this.manualFallbackMs,
    required this.minStableFrames,
  });

  final int autoCaptureMs;
  final int gracePeriodMs;
  final int manualFallbackMs;
  final int minStableFrames;

  DniCaptureState onFrame({
    required DniCaptureState current,
    required DocumentValidationResult validation,
    required int stableFrames,
    required bool? userDataMatch,
    required DateTime now,
    bool imuStill = true,
  }) {
    if (current is DniCaptureInFlight ||
        current is DniCaptureExpired ||
        current is DniCaptureDone) {
      return current;
    }

    final isCaptureable = validation.isCaptureable && imuStill;

    if (current is CountingDownWithAnchor) {
      final elapsedMs =
          (now.millisecondsSinceEpoch - current.perfectSinceEpochMs)
              .clamp(0, autoCaptureMs * 10);

      if (isCaptureable) {
        if (elapsedMs >= autoCaptureMs) {
          return const DniCaptureInFlight(showFlash: true);
        }
        return CountingDownWithAnchor(
          guideText: current.guideText,
          elapsedMs: elapsedMs,
          totalMs: autoCaptureMs,
          perfectSinceEpochMs: current.perfectSinceEpochMs,
        );
      } else {
        if (elapsedMs < gracePeriodMs) {
          return CountingDownWithAnchor(
            guideText: current.guideText,
            elapsedMs: current.elapsedMs,
            totalMs: autoCaptureMs,
            perfectSinceEpochMs: current.perfectSinceEpochMs,
          );
        }
        return _resetToScanning(current);
      }
    }

    if (current is DniCaptureCountingDown) {
      if (isCaptureable && stableFrames >= minStableFrames) {
        return CountingDownWithAnchor(
          guideText: _countdownGuideText(userDataMatch),
          elapsedMs: 0,
          totalMs: autoCaptureMs,
          perfectSinceEpochMs: now.millisecondsSinceEpoch,
        );
      }
      return _resetToScanning(current);
    }

    if (current is DniCaptureScanning) {
      if (isCaptureable && stableFrames >= minStableFrames) {
        return CountingDownWithAnchor(
          guideText: _countdownGuideText(userDataMatch),
          elapsedMs: 0,
          totalMs: autoCaptureMs,
          perfectSinceEpochMs: now.millisecondsSinceEpoch,
        );
      }
      return DniCaptureScanning(
        guideText: current.guideText,
        failingGate: current.failingGate,
        validationProgress: 0,
        stableFrames: stableFrames,
        userDataMatch: userDataMatch,
        manualModeActive: current.manualModeActive,
      );
    }

    return current;
  }

  DniCaptureState onManualFallbackTimeout(DniCaptureState current) {
    if (current is DniCaptureScanning) {
      return DniCaptureScanning(
        guideText: 'Toca el botón para capturar',
        failingGate: current.failingGate,
        validationProgress: current.validationProgress,
        stableFrames: current.stableFrames,
        userDataMatch: current.userDataMatch,
        manualModeActive: true,
      );
    }
    return current;
  }

  DniCaptureState onSideToggle(DniCaptureState current) =>
      const DniCaptureScanning(
        guideText: '',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );

  DniCaptureScanning _resetToScanning(DniCaptureState current) {
    final manualModeActive =
        current is DniCaptureScanning ? current.manualModeActive : false;
    return DniCaptureScanning(
      guideText: '',
      failingGate: null,
      validationProgress: 0,
      stableFrames: 0,
      userDataMatch: null,
      manualModeActive: manualModeActive,
    );
  }

  String _countdownGuideText(bool? userDataMatch) => userDataMatch == true
      ? '¡DNI verificado! Mantén quieto'
      : '¡Perfecto! Mantén el documento quieto';
}
