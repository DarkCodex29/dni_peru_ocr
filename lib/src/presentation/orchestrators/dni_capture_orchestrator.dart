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
    bool lightingValid = true,
    bool framingValid = true,
  }) {
    if (current is DniCaptureInFlight ||
        current is DniCaptureExpired ||
        current is DniCaptureDone) {
      return current;
    }

    final entryCaptureable =
        validation.isCaptureable && lightingValid && framingValid;
    final holdCaptureable = entryCaptureable && imuStill;

    if (current is CountingDownWithAnchor) {
      final elapsedMs =
          (now.millisecondsSinceEpoch - current.perfectSinceEpochMs)
              .clamp(0, autoCaptureMs * 10);

      if (holdCaptureable) {
        if (elapsedMs >= autoCaptureMs) {
          return const DniCaptureInFlight(showFlash: true);
        }
        // Hold is good: progress accrues and any prior disturbance clears, so
        // the next jitter starts a fresh grace window.
        return CountingDownWithAnchor(
          guideText: current.guideText,
          elapsedMs: elapsedMs,
          totalMs: autoCaptureMs,
          perfectSinceEpochMs: current.perfectSinceEpochMs,
          disturbedSinceEpochMs: null,
        );
      } else {
        // Hold is broken this frame. The grace window measures how long the
        // disturbance has lasted CONTINUOUSLY — not the total countdown
        // progress — so a brief handheld jitter pauses the dwell instead of
        // resetting it. The reset-loop that hung the textless back compared the
        // grace against total elapsed: once progress passed the grace mark, a
        // single jitter frame reset the whole countdown and the back could
        // never sustain 3s before the next micro-jitter (#5532).
        final disturbedSince =
            current.disturbedSinceEpochMs ?? now.millisecondsSinceEpoch;
        final disturbedForMs = (now.millisecondsSinceEpoch - disturbedSince)
            .clamp(0, autoCaptureMs * 10);
        if (disturbedForMs < gracePeriodMs) {
          return CountingDownWithAnchor(
            guideText: current.guideText,
            elapsedMs: current.elapsedMs,
            totalMs: autoCaptureMs,
            perfectSinceEpochMs: current.perfectSinceEpochMs,
            disturbedSinceEpochMs: disturbedSince,
          );
        }
        return _resetToScanning(current);
      }
    }

    if (current is DniCaptureCountingDown) {
      if (entryCaptureable && stableFrames >= minStableFrames) {
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
      if (entryCaptureable && stableFrames >= minStableFrames) {
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
