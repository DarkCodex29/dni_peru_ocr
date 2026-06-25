import '../extraction/hunt_result.dart';
import 'capture_signal.dart';

class CaptureDecider {
  const CaptureDecider();

  CaptureSignal decide({
    required HuntResult hunt,
    required bool framingStable,
    bool isBackSide = false,
    bool imuStill = true,
    bool lightingValid = true,
  }) {
    final phase = _resolvePhase(hunt, isBackSide: isBackSide);
    final shouldCapture = phase == CapturePhase.fieldsComplete &&
        framingStable &&
        lightingValid;
    return CaptureSignal(
      phase: shouldCapture ? CapturePhase.readyToCapture : phase,
      shouldCapture: shouldCapture,
    );
  }

  CapturePhase _resolvePhase(HuntResult hunt, {required bool isBackSide}) {
    final ready = isBackSide ? hunt.isComplete : hunt.isFrontReady;
    if (ready) return CapturePhase.fieldsComplete;
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
