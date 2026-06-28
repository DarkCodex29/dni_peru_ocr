import '../../domain/entities/document_side.dart';
import '../../domain/extraction/dni_fields.dart';
import '../../domain/extraction/extracted_fields.dart';
import '../../domain/extraction/field_hunter.dart';
import '../../domain/extraction/hunt_state_machine.dart';
import '../framing/framing_signal.dart';
import 'capture_decision.dart';
import 'frame_input.dart';

/// The single capture-readiness owner introduced by the capture-redesign
/// (#5543). It consumes a normalized [FrameInput] and runs the REAL readiness
/// path — `DocumentSideDetector.detect` → `FieldHunter.process` →
/// `HuntStateMachine.recordFrame` — then maps the emitted `HuntSignal` into a
/// [CaptureDecision]. That is the same per-frame chain `DniScannerState`
/// executes on the device after `recognizer.processImage`, so the coordinator
/// is the device-faithful seam ABOVE OCR that the harness drives.
///
/// PR3a SCOPE — this is a thin SKELETON / adapter. It establishes the seam and
/// runs the real detector + hunt machine, but it does NOT yet own the countdown
/// timer, the manual-fallback timer, or the presence-banner state; those still
/// live in `DniScannerState` and migrate in PR4/PR5. The coordinator therefore
/// holds NO Flutter import and NO dartcv: it carries already-computed values
/// (the quad framing flag, the gate readings) on [FrameInput] rather than
/// computing them, so it stays pure Dart and trivially testable.
///
/// Internal: not exported from `package:dni_peru_ocr/dni_peru_ocr.dart`.
class CaptureCoordinator {
  CaptureCoordinator({
    DniFields? fields,
    bool? isBackSide,
    int idleFramesThreshold = 18,
    int fastAdvanceThreshold = 14,
    int minFieldsForFastAdvance = 12,
    int minFieldsForStableCapture = 4,
    int backQuadDwellFrames = 6,
    HuntPhase initialPhase = HuntPhase.waitingFront,
  })  : _isBackSide = isBackSide,
        _hunter = FieldHunter.standard(fields: fields),
        _stateMachine = HuntStateMachine(
          idleFramesThreshold: idleFramesThreshold,
          fastAdvanceThreshold: fastAdvanceThreshold,
          minFieldsForFastAdvance: minFieldsForFastAdvance,
          minFieldsForStableCapture: minFieldsForStableCapture,
          backQuadDwellFrames: backQuadDwellFrames,
          frontCompleteFieldsCount: fields?.frontCount,
          backCompleteFieldsCount: fields?.length,
          initialPhase: initialPhase,
        );

  /// Two-sided run when null (side detected from OCR text); single-side back
  /// when true; single-side front when false. Mirrors `DniScanner.isBackSide`.
  final bool? _isBackSide;

  final FieldHunter _hunter;
  final HuntStateMachine _stateMachine;

  static const DocumentSideDetector _sideDetector = DocumentSideDetector();

  /// The current hunt phase, exposed so the seam and the harness can observe
  /// the real machine progressing (waitingFront → extractingFront → … → done).
  HuntPhase get phase => _stateMachine.phase;

  /// Runs one frame through the REAL readiness path and returns the decision.
  ///
  /// This reproduces `DniScannerState._processImage` +
  /// `_recordAndDispatch`: the side is detected from [FrameInput.ocrText] (or
  /// fixed for a single-side run), the fields are accumulated by the real
  /// `FieldHunter`, the distinct filled-field count is computed, and the real
  /// `HuntStateMachine` emits the readiness signal. An empty-OCR frame routes
  /// through the same empty-OCR back trigger the live widget uses.
  CaptureDecision onFrame(FrameInput input) {
    if (input.ocrText.isEmpty) {
      return _handleEmptyOcrFrame(input);
    }

    final detectedSide = switch (_isBackSide) {
      null => _sideDetector.detect(input.ocrText),
      true => DocumentSide.back,
      false => DocumentSide.front,
    };
    final addedNewField = _hunter.process(input.ocrText);
    final filledFields = _countFilled(_hunter.snapshot.fields);
    return _recordAndDispatch(
      detectedSide: detectedSide,
      addedNewField: addedNewField,
      filledFields: filledFields,
      quadFramingValid: input.quadFramingValid,
    );
  }

  /// Mirrors the post-capture handoff `DniScannerState._captureFront` /
  /// `_captureBack` drive on the real machine: the front advances to the back
  /// phase, the back advances to done. The harness calls this after a
  /// [CaptureFire] to follow the device sequence through a two-sided scan
  /// without resetting or injecting any state.
  void advanceAfterCapture() {
    switch (_stateMachine.phase) {
      case HuntPhase.waitingFront:
      case HuntPhase.extractingFront:
        if (_isBackSide == null) {
          _stateMachine.advanceToWaitingBack();
        } else {
          _stateMachine.advanceToDone();
        }
      case HuntPhase.waitingBack:
      case HuntPhase.extractingBack:
        _stateMachine.advanceToDone();
      case HuntPhase.done:
        break;
    }
  }

  /// Resets the coordinator to a fresh front-waiting scan.
  void reset() {
    _hunter.reset();
    _stateMachine.reset();
  }

  /// Routes an empty-OCR frame exactly as `DniScannerState._handleEmptyOcrFrame`
  /// does (#5523): a quad-confirmed side-safe back drives the back trigger; a
  /// blank frame with no quad, or a front phase, is skipped.
  CaptureDecision _handleEmptyOcrFrame(FrameInput input) {
    final framing = _framingSignal(input, captureEligible: false);
    if (framing.dispatchEmptyOcrBackTrigger) {
      return _recordAndDispatch(
        detectedSide: DocumentSide.unknown,
        addedNewField: false,
        filledFields: _countFilled(_hunter.snapshot.fields),
        quadFramingValid: input.quadFramingValid,
      );
    }
    return const CaptureScanning();
  }

  /// Records one frame through `HuntStateMachine` and maps the emitted signal to
  /// a [CaptureDecision] — the single trigger path the OCR frames and the
  /// quad-confirmed textless-back frames share. The current quad framing flag is
  /// fed in so a side-safe valid quad can latch and fire the back (#5517).
  CaptureDecision _recordAndDispatch({
    required DocumentSide detectedSide,
    required bool addedNewField,
    required int filledFields,
    required bool quadFramingValid,
  }) {
    final signal = _stateMachine.recordFrame(
      detectedSide: detectedSide,
      addedNewField: addedNewField,
      filledFields: filledFields,
      quadFramingValid: quadFramingValid,
    );

    return switch (signal) {
      HuntSignal.frontCaptureReady => const CaptureFire(CaptureSide.front),
      HuntSignal.backCaptureReady => const CaptureFire(CaptureSide.back),
      HuntSignal.recoverManual => const CaptureManualAvailable(),
      HuntSignal.frontDetected ||
      HuntSignal.backDetected ||
      HuntSignal.none =>
        const CaptureScanning(),
    };
  }

  FramingSignal _framingSignal(
    FrameInput input, {
    required bool captureEligible,
  }) {
    return FramingSignal(
      framingValid: input.quadFramingValid,
      captureEligible: captureEligible,
      isFrontPhase: _stateMachine.phase == HuntPhase.waitingFront ||
          _stateMachine.phase == HuntPhase.extractingFront,
    );
  }

  int _countFilled(ExtractedFields f) {
    var n = 0;
    if (f.documentNumber != null) n++;
    if (f.firstName != null) n++;
    if (f.lastName != null) n++;
    if (f.secondLastName != null) n++;
    if (f.dateOfBirth != null) n++;
    if (f.expirationDate != null) n++;
    if (f.emissionDate != null) n++;
    if (f.inscriptionDate != null) n++;
    if (f.sex != null) n++;
    if (f.nationality != null) n++;
    if (f.address != null) n++;
    if (f.department != null) n++;
    if (f.province != null) n++;
    if (f.district != null) n++;
    if (f.stateCivil != null) n++;
    if (f.cardNumber != null) n++;
    if (f.organDonor != null) n++;
    if (f.votingGroup != null) n++;
    if (f.birthUbigeoCode != null) n++;
    return n;
  }
}
