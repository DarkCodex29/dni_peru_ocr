import '../../domain/entities/document_side.dart';
import '../../domain/extraction/dni_fields.dart';
import '../../domain/extraction/extracted_fields.dart';
import '../../domain/extraction/field_hunter.dart';
import '../../domain/extraction/hunt_state_machine.dart';
import '../document_validator.dart';
import '../framing/framing_signal.dart';
import '../orchestrators/dni_capture_orchestrator.dart';
import '../orchestrators/dni_capture_state.dart';
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
/// PR4 SCOPE — the countdown/dwell ownership now LIVES here. The coordinator
/// owns the [DniCaptureOrchestrator] (the dwell + grace/disturbance math), the
/// presentation [DniCaptureState], and the wall-clock countdown anchor. A
/// readiness signal STARTS a countdown rather than firing immediately:
/// [onFrame] returns [CaptureCountingDown] each held frame and [CaptureFire]
/// only when the dwell completes, or [CaptureReset] when a disturbance outlasts
/// the grace window. The dwell is measured against the injectable
/// [FrameInput.now] clock, so it needs NO real `Timer` — the device-faithful
/// harness advances time deterministically and the live widget supplies its
/// monotonic countdown anchor + elapsed.
///
/// Still in `DniScannerState` (migrate in PR5): the manual-fallback timer and
/// the presence-banner / absent-document state. The coordinator owns no widget
/// import; it references the presentation orchestrator + capture state (also
/// presentation layer) and stays free of any Flutter framework import.
///
/// Internal: not exported from `package:dni_peru_ocr/dni_peru_ocr.dart`.
class CaptureCoordinator {
  /// Builds a coordinator. The live widget INJECTS its existing [hunter],
  /// [stateMachine] and [orchestrator] so there is a SINGLE shared source of
  /// truth — the widget renders from the same hunt machine the coordinator
  /// decides from, with no duplicated/divergent state. The harness and unit
  /// tests omit them and let the coordinator build defaults from the tuning
  /// parameters.
  CaptureCoordinator({
    DniFields? fields,
    bool? isBackSide,
    int idleFramesThreshold = 18,
    int fastAdvanceThreshold = 14,
    int minFieldsForFastAdvance = 12,
    int minFieldsForStableCapture = 4,
    int backQuadDwellFrames = 6,
    int autoCaptureMs = 3000,
    int gracePeriodMs = 600,
    int manualFallbackMs = 15000,
    int minStableFrames = 2,
    HuntPhase initialPhase = HuntPhase.waitingFront,
    FieldHunter? hunter,
    HuntStateMachine? stateMachine,
    DniCaptureOrchestrator? orchestrator,
  })  : _isBackSide = isBackSide,
        _minStableFrames = minStableFrames,
        _hunter = hunter ?? FieldHunter.standard(fields: fields),
        _orchestrator = orchestrator ??
            DniCaptureOrchestrator(
              autoCaptureMs: autoCaptureMs,
              gracePeriodMs: gracePeriodMs,
              manualFallbackMs: manualFallbackMs,
              minStableFrames: minStableFrames,
            ),
        _stateMachine = stateMachine ??
            HuntStateMachine(
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

  final int _minStableFrames;

  final FieldHunter _hunter;
  final HuntStateMachine _stateMachine;
  final DniCaptureOrchestrator _orchestrator;

  static const DocumentSideDetector _sideDetector = DocumentSideDetector();

  /// The owned countdown/capture state. Starts scanning; advances to
  /// [CountingDownWithAnchor] while dwelling, [DniCaptureInFlight] at the
  /// shutter instant, and back to [DniCaptureScanning] on a grace-expired reset.
  DniCaptureState _captureState = const DniCaptureScanning(
    guideText: '',
    failingGate: null,
    validationProgress: 0,
    stableFrames: 0,
    userDataMatch: null,
    manualModeActive: false,
  );

  /// Which side the running countdown will fire for. Captured at the readiness
  /// signal that started the countdown so the completion [CaptureFire] reports
  /// the correct side without re-reading the machine at the shutter instant.
  CaptureSide? _countingDownSide;

  /// Whether the OCR/quad readiness path marked this frame capture-eligible —
  /// the blocking signal fed to the orchestrator. Set per frame from the hunt
  /// signal exactly as `DniScannerState._frameCaptureable` was.
  bool _frameCaptureable = false;

  /// The current hunt phase, exposed so the seam and the harness can observe
  /// the real machine progressing (waitingFront → extractingFront → … → done).
  HuntPhase get phase => _stateMachine.phase;

  /// The owned capture state, exposed so the live widget can render the 3-2-1
  /// counter / flash from the single coordinator-owned source.
  DniCaptureState get captureState => _captureState;

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
      input: input,
      detectedSide: detectedSide,
      addedNewField: addedNewField,
      filledFields: filledFields,
    );
  }

  /// Latches a readiness signal for [side] so the next [tickCountdown] starts
  /// (or continues) the owned countdown for that side. The live widget calls
  /// this when the shared hunt machine emits a capture-ready signal, then drives
  /// the dwell through its periodic ticker — the migrated `_onCaptureReady`
  /// entry. Idempotent: re-latching while a countdown runs keeps the anchor.
  void beginCountdown(CaptureSide side) {
    _countingDownSide = side;
  }

  /// Advances ONLY the owned countdown one tick against [now], without running
  /// a new OCR/hunt frame. The live widget calls this from its periodic ticker
  /// during the camera-stream pause (when `takePicture`/dwell suspends the image
  /// stream so no new frames arrive). The widget supplies the current
  /// per-frame [captureEligible] (its OCR-derived eligibility / debug override
  /// from the shared hunt machine) so a document lost mid-dwell aborts the
  /// countdown. Returns the widened [CaptureDecision] so the widget renders the
  /// 3-2-1 counter and fires the shutter on completion — the migrated
  /// `_tickCountdown` + `_advanceCapture` path.
  CaptureDecision tickCountdown({
    required DateTime now,
    required bool imuStill,
    required bool quadFramingValid,
    required bool captureEligible,
    bool lightingValid = true,
  }) {
    _frameCaptureable = captureEligible;
    return _advanceCountdownAt(
      now: now,
      imuStill: imuStill,
      quadFramingValid: quadFramingValid,
      lightingValid: lightingValid,
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
          // Clear the leftover front countdown so the back countdown can start
          // from a clean scanning state (#5535: the InFlight latch that hung
          // the two-sided back when it was never reset after the front fired).
          _resetCountdown();
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
    _resetCountdown();
  }

  /// Clears ONLY the owned countdown/capture state back to scanning, leaving the
  /// shared hunt machine and hunter untouched. The live widget calls this from
  /// `_resetCaptureToScanning` (a disturbed-out-of-grace countdown, a blur
  /// reject, or the post-front-capture handoff) — the migrated countdown reset.
  void resetCountdown() => _resetCountdown();

  /// Routes an empty-OCR frame exactly as `DniScannerState._handleEmptyOcrFrame`
  /// does (#5523): a quad-confirmed side-safe back drives the back trigger; a
  /// blank frame with no quad, or a front phase, is skipped — but a running
  /// countdown still advances so a removed document (empty frames) can reset
  /// past the grace window instead of leaving the dwell hanging.
  CaptureDecision _handleEmptyOcrFrame(FrameInput input) {
    final framing = _framingSignal(input, captureEligible: false);
    if (framing.dispatchEmptyOcrBackTrigger) {
      return _recordAndDispatch(
        input: input,
        detectedSide: DocumentSide.unknown,
        addedNewField: false,
        filledFields: _countFilled(_hunter.snapshot.fields),
      );
    }
    // No readiness this frame. If a countdown is running it must keep ticking
    // against the clock so a sustained empty/disturbed stream aborts it.
    _frameCaptureable = false;
    return _advanceCountdown(input);
  }

  /// Records one frame through `HuntStateMachine`, maps the emitted signal to a
  /// readiness verdict, then drives the owned countdown. The OCR frames and the
  /// quad-confirmed textless-back frames share this single trigger path; the
  /// current quad framing flag latches a side-safe back (#5517).
  ///
  /// PR4: the readiness signal no longer fires directly. It marks the frame
  /// capture-eligible (or hands off to manual) and the countdown decides when
  /// the shutter actually fires by dwelling against the clock.
  CaptureDecision _recordAndDispatch({
    required FrameInput input,
    required DocumentSide detectedSide,
    required bool addedNewField,
    required int filledFields,
  }) {
    final signal = _stateMachine.recordFrame(
      detectedSide: detectedSide,
      addedNewField: addedNewField,
      filledFields: filledFields,
      quadFramingValid: input.quadFramingValid,
    );

    switch (signal) {
      case HuntSignal.frontCaptureReady:
        _frameCaptureable = true;
        _countingDownSide = CaptureSide.front;
      case HuntSignal.backCaptureReady:
        _frameCaptureable = true;
        _countingDownSide = CaptureSide.back;
      case HuntSignal.recoverManual:
        // A waiting phase stayed stuck because the side anchor was never
        // confirmed. Escape the latch by offering manual-assisted capture
        // instead of auto-capturing an unconfirmed side. (Manual ownership
        // reconciliation is PR5; the coordinator surfaces the decision today.)
        _frameCaptureable = false;
        _advanceCountdown(input);
        return const CaptureManualAvailable();
      case HuntSignal.frontDetected:
      case HuntSignal.backDetected:
      case HuntSignal.none:
        _frameCaptureable = false;
    }

    return _advanceCountdown(input);
  }

  /// Advances the owned countdown one tick against the per-frame clock and maps
  /// the resulting [DniCaptureState] to the widened [CaptureDecision]. This is
  /// the migrated dwell/grace logic: the orchestrator accrues progress while the
  /// document is held and resets past the grace window when it is disturbed.
  CaptureDecision _advanceCountdown(FrameInput input) => _advanceCountdownAt(
        now: input.now,
        imuStill: input.imuStill,
        quadFramingValid: input.quadFramingValid,
      );

  CaptureDecision _advanceCountdownAt({
    required DateTime now,
    required bool imuStill,
    required bool quadFramingValid,
    bool lightingValid = true,
  }) {
    final previous = _captureState;
    final next = _orchestrator.onFrame(
      current: _captureState,
      validation: _frameCaptureable
          ? const DocumentValidationResult.captureable()
          : const DocumentValidationResult.notCaptureable(),
      stableFrames: _frameCaptureable ? _minStableFrames : 0,
      userDataMatch: null,
      now: now,
      imuStill: imuStill,
      lightingValid: lightingValid,
      framingValid: _fireFramingValid(quadFramingValid),
    );
    _captureState = next;

    if (next is DniCaptureInFlight) {
      final side = _countingDownSide ?? CaptureSide.front;
      return CaptureFire(side);
    }
    if (next is DniCaptureCountingDown) {
      return CaptureCountingDown(next.progress);
    }
    // Scanning. Distinguish a fresh scan (no fire was pending) from an aborted
    // countdown: a transition OUT of a running countdown is a reset the widget
    // must render (clear the 3-2-1 counter) — the document-removed-mid-dwell
    // path. A plain scanning→scanning frame stays Scanning.
    if (previous is DniCaptureCountingDown) {
      _countingDownSide = null;
      return const CaptureReset();
    }
    return const CaptureScanning();
  }

  /// Side-aware framing value fed to the capture orchestrator (#5543). The FRONT
  /// degrades OPEN (its readiness is OCR-sourced, so a running front countdown
  /// already implies a framed document and the text-dense quad must not veto the
  /// shutter); the BACK keeps the strict live quad gate (the quad is its only
  /// proof of a framed document).
  bool _fireFramingValid(bool quadFramingValid) => FramingSignal(
        framingValid: quadFramingValid,
        captureEligible: _frameCaptureable,
        isFrontPhase: _stateMachine.phase == HuntPhase.waitingFront ||
            _stateMachine.phase == HuntPhase.extractingFront,
      ).fireFramingValid;

  void _resetCountdown() {
    _captureState = const DniCaptureScanning(
      guideText: '',
      failingGate: null,
      validationProgress: 0,
      stableFrames: 0,
      userDataMatch: null,
      manualModeActive: false,
    );
    _countingDownSide = null;
    _frameCaptureable = false;
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
