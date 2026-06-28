/// Which side of the document a [CaptureFire] decision targets.
enum CaptureSide { front, back }

/// The only output a [CaptureCoordinator] emits — the single value the widget
/// renderer and the camera controller act on. It is a sealed hierarchy so every
/// consumer must handle every readiness outcome the real path can produce.
///
/// PR4 widened this with [CaptureCountingDown] and [CaptureReset]: the
/// coordinator now OWNS the countdown/dwell decision (the orchestrator + the
/// capture state + the wall-clock anchor), so a readiness signal starts a
/// countdown that emits [CaptureCountingDown] each held frame and [CaptureFire]
/// only when the dwell completes; a disturbance past the grace window emits
/// [CaptureReset].
///
/// PR5 (final migration) widened it with [CaptureAbsentBanner]: the coordinator
/// now also owns the document-present/absent decision. A frame that drops to no
/// document present while a side is still being scanned emits
/// [CaptureAbsentBanner] so the widget surfaces the no-document warning and
/// resets — instead of staying silently stuck. Front presence is OCR-document-
/// based (a front DNI being read is present even before it stabilizes and even
/// with `corners=0`), curing the device false-absent banner (#5543). Manual
/// fallback availability is also coordinator-owned now (see
/// [CaptureCoordinator.manualAvailable]); the widget reads it as a flag rather
/// than from a parallel controller state.
sealed class CaptureDecision {
  const CaptureDecision();
}

/// No capture is ready this frame: the machine is scanning, extracting, or saw
/// a skipped/empty frame. The widget keeps showing the live scanning UI.
class CaptureScanning extends CaptureDecision {
  const CaptureScanning();
}

/// The readiness path latched and the auto-capture countdown is running. The
/// [progress] (0 → 1) is the dwell fraction the widget renders as the 3-2-1
/// counter. Emitted every held frame between the readiness signal and the
/// shutter; the widget shows the countdown UI and does NOT take a picture yet.
class CaptureCountingDown extends CaptureDecision {
  const CaptureCountingDown(this.progress);

  final double progress;
}

/// The countdown completed for [side]: the dwell held for the full duration, so
/// the widget must take the picture NOW. Under PR4 this is the SHUTTER instant
/// (countdown end), not the readiness-signal frame.
class CaptureFire extends CaptureDecision {
  const CaptureFire(this.side);

  final CaptureSide side;
}

/// The running countdown was aborted because the document was disturbed or
/// removed for longer than the grace window. The widget clears the countdown UI
/// and returns to scanning without taking a picture.
class CaptureReset extends CaptureDecision {
  const CaptureReset();
}

/// A waiting phase stayed stuck because the side anchor was never confirmed, so
/// the machine handed off to manual-assisted capture instead of auto-capturing
/// an unconfirmed side. The widget surfaces the manual control.
class CaptureManualAvailable extends CaptureDecision {
  const CaptureManualAvailable();
}

/// No document is present in the frame while a side is still being scanned: the
/// card left the view (OCR went empty and no quad frames it) for longer than the
/// grace window. The widget surfaces the no-document warning banner and clears
/// any running countdown. Presence is computed side-aware in the coordinator —
/// FRONT presence is OCR-document-based so a present-but-not-yet-stable front
/// DNI (corners=0) never false-fires this; only a genuinely removed document
/// does (#5543, the device cure).
class CaptureAbsentBanner extends CaptureDecision {
  const CaptureAbsentBanner();
}
