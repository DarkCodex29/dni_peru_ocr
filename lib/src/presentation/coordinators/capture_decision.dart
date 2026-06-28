/// Which side of the document a [CaptureFire] decision targets.
enum CaptureSide { front, back }

/// The only output a [CaptureCoordinator] emits — the single value the widget
/// renderer and the camera controller act on. It is a sealed hierarchy so every
/// consumer must handle every readiness outcome the real path can produce.
///
/// In PR3a the coordinator emits the readiness decision derived from the REAL
/// DocumentSideDetector + FieldHunter + HuntStateMachine chain. The countdown
/// timer, manual-fallback timer, and presence-banner state still live in the
/// widget (their migration is PR4/PR5); this type names the decision so the
/// device-faithful harness can assert it without injected flags.
sealed class CaptureDecision {
  const CaptureDecision();
}

/// No capture is ready this frame: the machine is scanning, extracting, or saw
/// a skipped/empty frame. The widget keeps showing the live scanning UI.
class CaptureScanning extends CaptureDecision {
  const CaptureScanning();
}

/// The real readiness path emitted a capture-ready signal for [side]: the OCR
/// stabilized (front) or a sustained valid quad dwelled (textless back). The
/// widget starts/continues its countdown toward the shutter.
class CaptureFire extends CaptureDecision {
  const CaptureFire(this.side);

  final CaptureSide side;
}

/// A waiting phase stayed stuck because the side anchor was never confirmed, so
/// the machine handed off to manual-assisted capture instead of auto-capturing
/// an unconfirmed side. The widget surfaces the manual control.
class CaptureManualAvailable extends CaptureDecision {
  const CaptureManualAvailable();
}
