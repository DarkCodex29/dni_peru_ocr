import '../document_validator.dart';
import 'dni_capture_state.dart';

/// Pure stateless state machine for the DNI auto-capture flow.
///
/// Takes the current [DniCaptureState] plus frame-level inputs, and returns
/// the next [DniCaptureState]. The caller ([DniCameraController]) owns the
/// [ValueNotifier] and calls [onFrame] on every processed frame.
///
/// [now] is injected so tests can drive time deterministically without
/// relying on [DateTime.now()].
///
/// ### Transitions
/// ```
/// Scanning(captureable=false)  ──────────────────────────────▶ Scanning
/// Scanning(captureable=true, stableFrames≥min)  ─────────────▶ CountingDown(t=0)
/// CountingDown(captureable=true, elapsed < auto)  ───────────▶ CountingDown(t+)
/// CountingDown(captureable=true, elapsed ≥ auto)  ───────────▶ InFlight
/// CountingDown(captureable=false, elapsed < grace)  ─────────▶ CountingDown (hold)
/// CountingDown(captureable=false, elapsed ≥ grace)  ─────────▶ Scanning (reset)
/// InFlight / Expired / Done  ────────────────────────────────▶ unchanged
/// ```
///
/// Side toggle: [onSideToggle] resets any in-progress countdown.
/// Manual fallback: [onManualFallbackTimeout] activates manual mode.
final class DniCaptureOrchestrator {
  DniCaptureOrchestrator({
    required this.autoCaptureMs,
    required this.gracePeriodMs,
    required this.manualFallbackMs,
    required this.minStableFrames,
  });

  /// Milliseconds of holding a captureable frame before auto-capture fires.
  final int autoCaptureMs;

  /// Grace window (ms): a non-captureable frame within this window does NOT
  /// reset the countdown (tolerates single noisy frames between stable reads).
  final int gracePeriodMs;

  /// Milliseconds after stream start before the manual-capture button appears.
  final int manualFallbackMs;

  /// Minimum consecutive stable-block frames required before starting the
  /// auto-capture countdown.
  final int minStableFrames;

  // ── Public API ─────────────────────────────────────────────────────────

  /// Pure state transition: process one camera frame.
  ///
  /// [current] — the state before this frame.
  /// [validation] — quality-gate result for this frame.
  /// [stableFrames] — consecutive stable-block-count frames so far.
  /// [userDataMatch] — OCR/user-data match result (`null` if no data to match).
  /// [now] — current wall-clock time (injected for determinism in tests).
  DniCaptureState onFrame({
    required DniCaptureState current,
    required DocumentValidationResult validation,
    required int stableFrames,
    required bool? userDataMatch,
    required DateTime now,
  }) {
    // Terminal / in-flight states are pass-through.
    if (current is DniCaptureInFlight ||
        current is DniCaptureExpired ||
        current is DniCaptureDone) {
      return current;
    }

    final isCaptureable = validation.isCaptureable;

    // ── CountingDown branch ─────────────────────────────────────────────
    if (current is CountingDownWithAnchor) {
      final elapsedMs =
          (now.millisecondsSinceEpoch - current.perfectSinceEpochMs)
              .clamp(0, autoCaptureMs * 10); // guard against backward clock

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
        // Quality regression
        if (elapsedMs < gracePeriodMs) {
          // Within grace: freeze elapsed, keep counting
          return CountingDownWithAnchor(
            guideText: current.guideText,
            elapsedMs: current.elapsedMs,
            totalMs: autoCaptureMs,
            perfectSinceEpochMs: current.perfectSinceEpochMs,
          );
        }
        // Beyond grace: reset
        return _resetToScanning(current);
      }
    }

    // ── Defensive: plain DniCaptureCountingDown without anchor ──────────
    // Should not occur in normal flow (orchestrator always emits anchored
    // states), but guard in case the controller injects a hand-crafted value.
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

    // ── Scanning branch ─────────────────────────────────────────────────
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

    // Unreachable with a complete sealed hierarchy.
    return current;
  }

  /// Manual-fallback timer expired — activate manual-capture mode.
  ///
  /// Only has an effect when [current] is [DniCaptureScanning].
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

  /// Side toggle (front ↔ back) — resets countdown and manual mode.
  DniCaptureState onSideToggle(DniCaptureState current) =>
      const DniCaptureScanning(
        guideText: '',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );

  // ── Private helpers ────────────────────────────────────────────────────

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
