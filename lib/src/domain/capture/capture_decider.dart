import '../extraction/hunt_result.dart';
import 'capture_signal.dart';

class CaptureDecider {
  const CaptureDecider();

  CaptureSignal decide({
    required HuntResult hunt,
    required bool framingStable,
  }) {
    final phase = _resolvePhase(hunt);
    final shouldCapture =
        phase == CapturePhase.fieldsComplete && framingStable;
    return CaptureSignal(
      phase: shouldCapture ? CapturePhase.readyToCapture : phase,
      shouldCapture: shouldCapture,
    );
  }

  CapturePhase _resolvePhase(HuntResult hunt) {
    if (hunt.isComplete) return CapturePhase.fieldsComplete;
    if (!hunt.frontDetected && !hunt.backDetected) {
      return CapturePhase.waiting;
    }
    if (hunt.frontDetected && !hunt.backDetected) {
      return CapturePhase.needsBack;
    }
    if (!hunt.frontDetected && hunt.backDetected) {
      return CapturePhase.needsFront;
    }
    return CapturePhase.gathering;
  }
}
