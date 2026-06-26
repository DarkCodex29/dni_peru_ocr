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

  /// A waiting phase stayed stuck (the side anchor was never confirmed) for the
  /// idle threshold. The machine escapes the latch by handing off to
  /// manual-assisted capture instead of auto-capturing an unconfirmed side.
  recoverManual,
}

class HuntStateMachine {
  HuntStateMachine({
    this.idleFramesThreshold = 18,
    this.fastAdvanceThreshold = 14,
    this.minFieldsForFastAdvance = 12,
    this.frontCompleteFieldsCount,
    this.backCompleteFieldsCount,
    HuntPhase initialPhase = HuntPhase.waitingFront,
  }) : _phase = initialPhase;

  final int idleFramesThreshold;
  final int fastAdvanceThreshold;
  final int minFieldsForFastAdvance;

  /// Filled-fields count that completes the FRONT phase. When a front frame
  /// reports this many filled fields, capture fires immediately without
  /// waiting idle frames. Typically `DniFields.frontCount`.
  final int? frontCompleteFieldsCount;

  /// Filled-fields count that completes the BACK phase. In two-sided mode
  /// this is the full selection length (front fields accumulate); in
  /// single-side back mode it is `DniFields.backCount`.
  final int? backCompleteFieldsCount;

  HuntPhase _phase;
  int _idleFrames = 0;

  HuntPhase get phase => _phase;

  // TEMP DIAG (#5453): expose the idle-frame counter so the live frame path
  // can log gate progress on device. Remove with the diagnostics below.
  int get debugIdleFrames => _idleFrames;

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
        return _advanceWaitingIdle(addedNewField);

      case HuntPhase.extractingFront:
        if (_isComplete(filledFields, frontCompleteFieldsCount)) {
          return HuntSignal.frontCaptureReady;
        }
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
        return _advanceWaitingIdle(addedNewField);

      case HuntPhase.extractingBack:
        if (_isComplete(filledFields, backCompleteFieldsCount)) {
          return HuntSignal.backCaptureReady;
        }
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

  HuntSignal _advanceWaitingIdle(bool addedNewField) {
    if (addedNewField) {
      _idleFrames = 0;
      return HuntSignal.none;
    }
    _idleFrames++;
    if (_idleFrames >= idleFramesThreshold) {
      _idleFrames = 0;
      return HuntSignal.recoverManual;
    }
    return HuntSignal.none;
  }

  int _effectiveThreshold(int filledFields) {
    return filledFields >= minFieldsForFastAdvance
        ? fastAdvanceThreshold
        : idleFramesThreshold;
  }

  bool _isComplete(int filledFields, int? total) {
    return total != null && total > 0 && filledFields >= total;
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
