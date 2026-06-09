import '../entities/document_side.dart';

enum HuntPhase {
  waitingFront,
  extractingFront,
  waitingBack,
  extractingBack,
  done,
}

enum HuntSignal {
  none,
  frontDetected,
  frontCaptureReady,
  backDetected,
  backCaptureReady,
}

class HuntStateMachine {
  HuntStateMachine({
    this.idleFramesThreshold = 18,
    this.fastAdvanceThreshold = 14,
    this.minFieldsForFastAdvance = 12,
    HuntPhase initialPhase = HuntPhase.waitingFront,
  }) : _phase = initialPhase;

  final int idleFramesThreshold;
  final int fastAdvanceThreshold;
  final int minFieldsForFastAdvance;

  HuntPhase _phase;
  int _idleFrames = 0;

  HuntPhase get phase => _phase;

  HuntSignal recordFrame({
    required DocumentSide detectedSide,
    required bool addedNewField,
    int filledFields = 0,
  }) {
    switch (_phase) {
      case HuntPhase.waitingFront:
        if (detectedSide == DocumentSide.front) {
          _phase = HuntPhase.extractingFront;
          _idleFrames = 0;
          return HuntSignal.frontDetected;
        }
        return HuntSignal.none;

      case HuntPhase.extractingFront:
        if (addedNewField) {
          _idleFrames = 0;
        } else {
          _idleFrames++;
        }
        if (_idleFrames >= _effectiveThreshold(filledFields)) {
          return HuntSignal.frontCaptureReady;
        }
        return HuntSignal.none;

      case HuntPhase.waitingBack:
        if (detectedSide == DocumentSide.back) {
          _phase = HuntPhase.extractingBack;
          _idleFrames = 0;
          return HuntSignal.backDetected;
        }
        return HuntSignal.none;

      case HuntPhase.extractingBack:
        if (addedNewField) {
          _idleFrames = 0;
        } else {
          _idleFrames++;
        }
        if (_idleFrames >= _effectiveThreshold(filledFields)) {
          return HuntSignal.backCaptureReady;
        }
        return HuntSignal.none;

      case HuntPhase.done:
        return HuntSignal.none;
    }
  }

  int _effectiveThreshold(int filledFields) {
    return filledFields >= minFieldsForFastAdvance
        ? fastAdvanceThreshold
        : idleFramesThreshold;
  }

  void advanceToWaitingBack() {
    _phase = HuntPhase.waitingBack;
    _idleFrames = 0;
  }

  void advanceToDone() {
    _phase = HuntPhase.done;
    _idleFrames = 0;
  }

  void reset() {
    _phase = HuntPhase.waitingFront;
    _idleFrames = 0;
  }
}
