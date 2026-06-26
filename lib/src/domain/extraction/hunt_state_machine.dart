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
  int _lastFilledFields = 0;

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
          _lastFilledFields = filledFields;
          return HuntSignal.frontDetected;
        }
        return _advanceWaitingIdle(resetsIdleOnNewField: addedNewField);

      case HuntPhase.extractingFront:
        if (_isComplete(filledFields, frontCompleteFieldsCount)) {
          return HuntSignal.frontCaptureReady;
        }
        if (_advanceExtractingIdle(filledFields) >=
            _effectiveThreshold(filledFields)) {
          return HuntSignal.frontCaptureReady;
        }
        return HuntSignal.none;

      case HuntPhase.waitingBack:
        if (detectedSide == DocumentSide.back) {
          _phase = HuntPhase.extractingBack;
          _idleFrames = 0;
          _lastFilledFields = filledFields;
          return HuntSignal.backDetected;
        }
        // In waitingBack a genuine BACK field would already have advanced the
        // phase above, so any addedNewField here is a STALE non-back re-read
        // (typically front fields). It must NOT reset idle, otherwise the
        // machine never reaches the threshold and the manual escape never
        // fires — the reverso latch observed on device (#5461).
        return _advanceWaitingIdle(resetsIdleOnNewField: false);

      case HuntPhase.extractingBack:
        if (_isComplete(filledFields, backCompleteFieldsCount)) {
          return HuntSignal.backCaptureReady;
        }
        if (_advanceExtractingIdle(filledFields) >=
            _effectiveThreshold(filledFields)) {
          return HuntSignal.backCaptureReady;
        }
        return HuntSignal.none;

      case HuntPhase.done:
        return HuntSignal.none;
    }
  }

  /// Advances the idle counter for an extracting phase and returns its new
  /// value. The dwell only resets when a genuinely NEW distinct field is
  /// recorded — i.e. the distinct filled-field count rises. A text-dense
  /// front keeps re-voting NEW normalized variants of fields it ALREADY
  /// filled (addedNewField=true with a flat filled count); those re-votes are
  /// not new data and must NOT reset the dwell, otherwise the 3-2-1 countdown
  /// stalls near completion and only the timeout fires (#5461).
  int _advanceExtractingIdle(int filledFields) {
    if (filledFields > _lastFilledFields) {
      _idleFrames = 0;
    } else {
      _idleFrames++;
    }
    _lastFilledFields = filledFields;
    return _idleFrames;
  }

  HuntSignal _advanceWaitingIdle({required bool resetsIdleOnNewField}) {
    if (resetsIdleOnNewField) {
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
    _lastFilledFields = 0;
  }

  void advanceToDone() {
    _phase = HuntPhase.done;
    _idleFrames = 0;
    _lastFilledFields = 0;
  }

  void reset() {
    _phase = HuntPhase.waitingFront;
    _idleFrames = 0;
    _lastFilledFields = 0;
  }
}
