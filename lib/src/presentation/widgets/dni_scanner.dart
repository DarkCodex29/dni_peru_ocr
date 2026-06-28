import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../domain/capture/document_quad_detector.dart';
import '../../domain/capture/motion_stillness_gate.dart';
import '../../domain/entities/document_side.dart';
import '../../domain/extraction/dni_fields.dart';
import '../../domain/extraction/extracted_fields.dart';
import '../../domain/extraction/field_hunter.dart';
import '../../domain/extraction/hunt_result.dart';
import '../../domain/extraction/hunt_state_machine.dart';
import '../../infrastructure/detector_lifecycle.dart';
import '../../infrastructure/dni_logger.dart';
import '../../infrastructure/input_image_converter.dart';
import '../../infrastructure/opencv_quad_detector.dart';
import '../../lookup/models/dni_data.dart';
import '../../lookup/models/dni_lookup_result.dart';
import '../../lookup/services/dni_lookup_service.dart';
import '../../infrastructure/sensors_motion_gate.dart';
import '../camera_overlay_logic.dart';
import '../controllers/dni_camera_controller.dart';
import '../document_validator.dart';
import '../framing/framing_signal.dart';
import '../image_quality_gate.dart';
import '../lighting_gate.dart';
import '../orchestrators/dni_capture_orchestrator.dart';
import '../orchestrators/dni_capture_state.dart';
import '../theme/kyc_theme.dart';
import 'dni_scan_hints.dart';
import 'quad_overlay_painter.dart';

enum DniCaptureMode { auto, manual, hybrid }

enum _BlurGateOutcome { accept, retry, reject }

class DniScanResult {
  const DniScanResult({
    required this.frontPhoto,
    required this.backPhoto,
    required this.hunt,
    this.reniecData,
  });

  final XFile frontPhoto;
  final XFile backPhoto;
  final HuntResult hunt;
  final DniData? reniecData;
}

class DniSideScanResult {
  const DniSideScanResult({
    required this.photo,
    required this.isBackSide,
    required this.hunt,
    this.reniecData,
  });

  final XFile photo;
  final bool isBackSide;
  final HuntResult hunt;
  final DniData? reniecData;
}

class DniScanner extends StatefulWidget {
  const DniScanner({
    super.key,
    required this.controller,
    this.onScanComplete,
    this.onSideCaptured,
    this.isBackSide,
    this.hunter,
    this.stateMachine,
    this.fields,
    this.lookupService,
    this.lookupTimeout = const Duration(milliseconds: 2500),
    this.onDniReady,
    this.onError,
    this.idleFramesBeforeCapture = 18,
    this.backQuadDwellFrames = 6,
    this.holeWidth = 300,
    this.holeHeight = 220,
    this.captureMode = DniCaptureMode.auto,
    this.orchestrator,
    this.motionGate,
    this.imageQualityGate,
    this.autoCaptureMs = CameraOverlayTuning.autoCaptureMs,
    this.gracePeriodMs = 600,
    this.minStableFrames = 3,
    this.manualFallbackMs = CameraOverlayTuning.manualFallbackMs,
    this.flipDocumentText = 'Voltea tu DNI',
    this.scanHints = const DniScanHints(),
  }) : assert(
          (isBackSide == null && onScanComplete != null) ||
              (isBackSide != null && onSideCaptured != null),
          'Use onScanComplete for two-sided mode (isBackSide == null) or '
          'onSideCaptured for single-side mode (isBackSide != null).',
        );

  final CameraController controller;

  final void Function(DniScanResult result)? onScanComplete;

  final void Function(DniSideScanResult result)? onSideCaptured;

  final bool? isBackSide;

  final FieldHunter? hunter;
  final HuntStateMachine? stateMachine;

  final DniFields? fields;

  final DniLookupService? lookupService;

  final Duration lookupTimeout;

  final void Function(DniData data)? onDniReady;

  final void Function(Object error, StackTrace stack)? onError;

  final int idleFramesBeforeCapture;

  /// Sustained-frame dwell for a quad-confirmed TEXTLESS back before
  /// auto-capture. Forwarded to [HuntStateMachine.backQuadDwellFrames] and
  /// scoped to the back quad-latch path only; the front and the manual escape
  /// keep using [idleFramesBeforeCapture]. Defaults to 6 (~0.7s at the camera
  /// cadence), calibrated from device truth (#5525) so the reverso
  /// auto-captures in a human hold instead of falling to manual.
  final int backQuadDwellFrames;
  final double holeWidth;
  final double holeHeight;

  final DniCaptureMode captureMode;

  final DniCaptureOrchestrator? orchestrator;

  final MotionStillnessGate? motionGate;

  final ImageQualityGate? imageQualityGate;

  final int autoCaptureMs;

  final int gracePeriodMs;

  final int minStableFrames;

  /// Time a side may try to auto-capture before the manual-capture button is
  /// offered as a fallback. Measured PER SIDE: the window restarts at the
  /// front->back handoff so the back gets its own full window instead of
  /// inheriting the front's elapsed time (#5536). The manual button is still
  /// suppressed while an auto-capture is in progress (see [manualButtonVisible])
  /// so it never competes with the live 3-2-1. Configurable so a published
  /// library consumer can tune it; defaults to
  /// [CameraOverlayTuning.manualFallbackMs] (~15s).
  final int manualFallbackMs;

  /// Guidance shown to the user during the front-to-back transition, telling
  /// them to flip the document. Configurable so a published-library consumer
  /// can localize or reword it. Defaults to neutral Spanish.
  final String flipDocumentText;

  /// Rotating bottom-of-screen guidance hints per scanning phase. The copy is
  /// generic action guidance only (focus, hold still, flip) and never names a
  /// specific DNI field. Configurable so a published-library consumer can
  /// localize or reword it. Defaults to neutral Spanish.
  final DniScanHints scanHints;

  @override
  State<DniScanner> createState() => DniScannerState();
}

class DniScannerState extends State<DniScanner>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final FieldHunter _hunter;
  late final HuntStateMachine _stateMachine;
  late final TextRecognizer _recognizer;
  late final DetectorLifecycle _lifecycle;
  late final AnimationController _pulse;
  late final AnimationController _captureFlash;
  late final DniCaptureOrchestrator _orchestrator;
  late final DniCameraController _cameraController;
  late final MotionStillnessGate _motionGate;
  late final ImageQualityGate _imageQualityGate;

  static const int maxBlurRetries = 2;
  int _blurRetries = 0;

  DniCaptureState _captureState = const DniCaptureScanning(
    guideText: '',
    failingGate: null,
    validationProgress: 0,
    stableFrames: 0,
    userDataMatch: null,
    manualModeActive: false,
  );
  Timer? _countdownTicker;
  DateTime? _countdownAnchor;
  int _countdownElapsedMs = 0;

  static const int _countdownTickMs = 100;

  static const int _captureFlashMs = 180;

  bool _processing = false;
  bool _disposed = false;
  bool _capturing = false;
  bool _frameCaptureable = false;
  bool _lightingValid = true;
  bool _analyzingLighting = false;
  int _lastLightingMs = 0;

  static const int _lightingIntervalMs = 350;

  late final DocumentQuadDetector _quadDetector;
  bool _framingValid = true;
  bool _documentPresent = false;
  List<QuadCorner> _quadCorners = const <QuadCorner>[];
  int _quadFrameWidth = 0;
  int _quadFrameHeight = 0;
  bool _torchOn = false;
  bool _captureReady = false;
  XFile? _frontPhoto;
  XFile? _backPhoto;
  DniData? _reniecData;
  Future<void>? _reniecLookup;
  String? _lookupAttemptedDni;
  HuntPhase _lastPhaseRendered = HuntPhase.waitingFront;
  Offset? _focusIndicator;
  Timer? _focusIndicatorTimer;
  Timer? _hintRotationTimer;
  int _hintIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hunter = widget.hunter ?? FieldHunter.standard(fields: widget.fields);
    final initialPhase = widget.isBackSide == true
        ? HuntPhase.waitingBack
        : HuntPhase.waitingFront;
    final selectedCount = widget.fields?.length ?? 19;
    // Auto-capture fires on DATA STABILITY rather than on extracting every
    // selected field, because some printed fields are physically absent or
    // illegible on a given DNI and can never be reached (#5471). The stable
    // floor is the smallest meaningful identity set (4, the size of
    // DniFields.minimal), clamped so tiny custom selections still work. Fast
    // advance keys off the same floor so any stabilized plateau above it uses
    // the fast path instead of dropping onto the slow idle path at e.g. 11/19.
    final stableFloor = 4.clamp(2, selectedCount);
    _stateMachine = widget.stateMachine ??
        HuntStateMachine(
          idleFramesThreshold: widget.idleFramesBeforeCapture,
          backQuadDwellFrames: widget.backQuadDwellFrames,
          minFieldsForFastAdvance: stableFloor,
          minFieldsForStableCapture: stableFloor,
          frontCompleteFieldsCount: widget.fields?.frontCount,
          backCompleteFieldsCount: widget.isBackSide == true
              ? widget.fields?.backCount
              : widget.fields?.length,
          initialPhase: initialPhase,
        );
    _lastPhaseRendered = initialPhase;
    _orchestrator = widget.orchestrator ??
        DniCaptureOrchestrator(
          autoCaptureMs: widget.autoCaptureMs,
          gracePeriodMs: widget.gracePeriodMs,
          manualFallbackMs: widget.manualFallbackMs,
          minStableFrames: widget.minStableFrames,
        );
    _motionGate = widget.motionGate ?? SensorsMotionGate();
    _imageQualityGate = widget.imageQualityGate ?? ImageQualityGate();
    _quadDetector = selectQuadDetector();
    _cameraController = DniCameraController(
      orchestrator: _orchestrator,
      isBackSide: widget.isBackSide ?? false,
      onValidCapture: (_, _) {},
    );
    _cameraController.captureState.addListener(_onControllerStateChanged);
    _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    _lifecycle = DetectorLifecycle(
      stopStream: () => _safeStopStream(widget.controller),
      closeDetectors: () => _recognizer.close(),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    unawaited(_pulse.repeat(reverse: true));
    _captureFlash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _captureFlashMs),
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    _hintRotationTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() => _hintIndex++);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startStream());
      unawaited(_cameraController.start());
    });
  }

  void _onControllerStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// Updates the live document-presence flag, rebuilding only on a real change
  /// so the no-document banner (#5540) appears/dismisses without per-frame
  /// churn.
  void _setDocumentPresent(bool present) {
    if (_documentPresent == present) return;
    _documentPresent = present;
    if (mounted) setState(() {});
  }

  @visibleForTesting
  bool get debugDocumentPresent => _documentPresent;

  bool get _manualModeActive {
    final state = _cameraController.captureState.value;
    return state is DniCaptureScanning && state.manualModeActive;
  }

  Future<void> _startStream() async {
    if (!widget.controller.value.isInitialized) {
      debugPrint('DniScanner: camera not initialized, cannot start stream');
      return;
    }
    if (widget.controller.value.isStreamingImages) {
      debugPrint('DniScanner: stream already active');
      return;
    }
    try {
      await widget.controller.startImageStream(_onCameraImage);
      debugPrint('DniScanner: stream started OK');
    } on CameraException catch (e) {
      debugPrint('DniScanner: startImageStream failed: ${e.code} ${e.description}');
    }
  }

  Future<void> _safeStopStream(CameraController controller) async {
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } on CameraException {
      // ignore
    }
  }

  void _onCameraImage(CameraImage image) {
    if (_disposed || _capturing) return;
    _maybeAnalyzeFrame(image);
    if (_processing) return;
    _processing = true;
    unawaited(
      _lifecycle.trackInflight(() => _processImage(image)).whenComplete(() {
        _processing = false;
      }),
    );
  }

  /// Runs lighting and (when native is available) quad detection on the same
  /// Y-plane inside a single isolate hop, reusing one throttle interval and one
  /// in-flight guard so per-frame analysis never spawns a second isolate or
  /// outpaces the camera.
  void _maybeAnalyzeFrame(CameraImage image) {
    if (_analyzingLighting) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastLightingMs < _lightingIntervalMs) return;
    _lastLightingMs = nowMs;
    final detectQuad = _quadDetector.isNativeAvailable;
    final request = _FrameAnalysisRequest(
      luminancePlane: image.planes.first.bytes,
      bytesPerRow: image.planes.first.bytesPerRow,
      width: image.width,
      height: image.height,
      rotationDegrees: widget.controller.description.sensorOrientation,
      detectQuad: detectQuad,
    );
    _analyzingLighting = true;
    unawaited(
      Isolate.run(() => _analyzeFrame(request)).then((result) {
        if (_disposed) return;
        _lightingValid = result.lighting.isValid;
        if (detectQuad) {
          _framingValid = result.framingValid;
          _quadCorners = result.corners;
          _quadFrameWidth = request.width;
          _quadFrameHeight = request.height;
          if (mounted) setState(() {});
        }
      }).catchError((_) {
        if (_disposed) return;
        _lightingValid = true;
        if (detectQuad) {
          _framingValid = true;
          _quadCorners = const <QuadCorner>[];
        }
      }).whenComplete(() {
        _analyzingLighting = false;
      }),
    );
  }

  Future<void> _processImage(CameraImage image) async {
    final inputImage = InputImageConverter.fromCameraImage(
      image,
      widget.controller.description,
    );
    if (inputImage == null) return;

    final recognized = await _recognizer.processImage(inputImage);
    if (!mounted) return;

    final text = recognized.blocks.map((b) => b.text).join('\n');
    if (text.isEmpty) {
      _handleEmptyOcrFrame();
      return;
    }

    DniLogger.verbose(
      'DniScanner',
      'raw OCR (${text.length} chars, ${recognized.blocks.length} blocks):\n$text',
    );

    final DocumentSide detectedSide = switch (widget.isBackSide) {
      null => const DocumentSideDetector().detect(text),
      true => DocumentSide.back,
      false => DocumentSide.front,
    };
    final addedNew = _hunter.process(text);
    final filled = _countFilled(_hunter.snapshot.fields);
    _recordAndDispatch(
      detectedSide: detectedSide,
      addedNewField: addedNew,
      filledFields: filled,
    );
  }

  /// Routes an empty-OCR frame through the single capture chain (#5523).
  ///
  /// The Peru DNI back is textless, so OCR is frequently empty and the OCR path
  /// alone never triggers it. [resolveEmptyOcrRoute] decides, from the live
  /// quad framing flag and the current phase, whether this empty frame must
  /// drive the back trigger (a quad-confirmed, side-safe back) or be skipped (a
  /// blank frame with no quad, or a front phase that stays OCR-triggered). An
  /// empty frame carries no front title block, so the side resolves to
  /// `unknown` (side-safe, != front); a held front is text-dense and takes the
  /// OCR branch in [_processImage] instead, so the wrong-side guard in
  /// [HuntStateMachine] still protects this path.
  DniCaptureState _handleEmptyOcrFrame() {
    if (_framingSignal().dispatchEmptyOcrBackTrigger) {
      return _recordAndDispatch(
        detectedSide: DocumentSide.unknown,
        addedNewField: false,
        filledFields: _countFilled(_hunter.snapshot.fields),
      );
    }
    _frameCaptureable = false;
    _setDocumentPresent(false);
    DniLogger.debug('DniScanner', 'frame skipped — empty OCR');
    return _captureState;
  }

  /// Records one frame through [HuntStateMachine] and dispatches the resulting
  /// signal — the single capture trigger path shared by the OCR frames and the
  /// quad-confirmed textless-back frames. The current quad framing flag
  /// ([_framingValid], updated by the quad-detection isolate) is fed into the
  /// machine so a side-safe valid quad can latch and fire the back even with no
  /// OCR fields (#5517). There is exactly one trigger path, so the two
  /// per-frame analyses (OCR + quad) never race for a second trigger.
  DniCaptureState _recordAndDispatch({
    required DocumentSide detectedSide,
    required bool addedNewField,
    required int filledFields,
  }) {
    final signal = _stateMachine.recordFrame(
      detectedSide: detectedSide,
      addedNewField: addedNewField,
      filledFields: filledFields,
      quadFramingValid: _framingValid,
    );

    final total = widget.fields?.length ?? 19;
    DniLogger.verbose(
      'DniScanner',
      'side=$detectedSide addedNew=$addedNewField phase=${_stateMachine.phase} '
          'signal=$signal filled=$filledFields/$total framing=$_framingValid',
    );

    if (mounted &&
        (_stateMachine.phase != _lastPhaseRendered || addedNewField)) {
      setState(() => _lastPhaseRendered = _stateMachine.phase);
    }

    switch (signal) {
      case HuntSignal.frontCaptureReady:
      case HuntSignal.backCaptureReady:
        _frameCaptureable = true;
        if (widget.captureMode == DniCaptureMode.manual) {
          _markCaptureReady();
        } else {
          _onCaptureReady(signal);
        }
      case HuntSignal.recoverManual:
        // A waiting phase stayed stuck because the side anchor was never
        // confirmed. Escape the latch by offering manual-assisted capture
        // instead of auto-capturing an unconfirmed side.
        _frameCaptureable = false;
        _cameraController.activateManualFallback();
        _markCaptureReady();
      case HuntSignal.frontDetected:
      case HuntSignal.backDetected:
      case HuntSignal.none:
        _frameCaptureable = false;
        break;
    }
    // A frame's document-presence is side-aware (#5540/#5543): the front trusts
    // the OCR-eligibility signal (its quad degrades to false on the text-dense
    // card), the back trusts the quad. A stale flag alone never keeps it
    // "present", so removing the DNI mid-count drops presence and the countdown
    // grace window resets it instead of capturing empty air.
    _setDocumentPresent(_framingSignal().documentPresent);
    return _captureState;
  }

  void _onCaptureReady(HuntSignal signal) {
    if (_capturing || _disposed) return;
    if (_captureState is DniCaptureInFlight ||
        _captureState is DniCaptureDone) {
      return;
    }
    _frameCaptureable = true;
    // Idempotent entry: once a countdown is running, repeated capture-ready
    // frames must NOT restart it. Resetting the anchor/elapsed and the ticker
    // every frame collapses synthetic progress back to ~0, so the ring never
    // fills and auto-capture only fires by chance. Keep the live anchor and
    // let the existing ticker keep accumulating progress toward 1.0.
    if (_captureState is CountingDownWithAnchor) {
      _advanceCapture();
      if (mounted) setState(() {});
      return;
    }
    _countdownAnchor = DateTime.now();
    _countdownElapsedMs = 0;
    _advanceCapture();
    if (mounted) setState(() {});
    _startCountdownTicker(signal);
  }

  void _startCountdownTicker(HuntSignal signal) {
    _countdownTicker?.cancel();
    _countdownTicker = Timer.periodic(
      const Duration(milliseconds: _countdownTickMs),
      (_) => _tickCountdown(signal),
    );
  }

  void _tickCountdown(HuntSignal signal) {
    if (_disposed) {
      _countdownTicker?.cancel();
      return;
    }
    _countdownElapsedMs += _countdownTickMs;
    _advanceCapture();
    if (_captureState is DniCaptureInFlight) {
      _countdownTicker?.cancel();
      _countdownTicker = null;
      if (mounted) setState(() {});
      unawaited(_fireCapture(signal));
      return;
    }
    if (_captureState is DniCaptureScanning) {
      _resetCaptureToScanning();
      return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _fireCapture(HuntSignal signal) async {
    if (signal == HuntSignal.frontCaptureReady) {
      await _captureFront();
    } else if (signal == HuntSignal.backCaptureReady) {
      await _captureBack();
    }
  }

  void _advanceCapture() {
    final anchor = _countdownAnchor ?? DateTime.now();
    final now = anchor.add(Duration(milliseconds: _countdownElapsedMs));
    final next = _orchestrator.onFrame(
      current: _captureState,
      validation: _frameCaptureable
          ? const DocumentValidationResult.captureable()
          : const DocumentValidationResult.notCaptureable(),
      stableFrames: _frameCaptureable ? widget.minStableFrames : 0,
      userDataMatch: null,
      now: now,
      imuStill: _motionGate.isStill,
      lightingValid: _lightingValid,
      framingValid: _fireFramingValid(),
    );
    if (!identical(next, _captureState)) {
      final firedNow =
          next is DniCaptureInFlight && _captureState is! DniCaptureInFlight;
      _captureState = next;
      if (firedNow) _triggerCaptureFlash();
    }
  }

  /// Side-aware framing value fed to the capture orchestrator (#5543).
  ///
  /// The FRONT readiness is OCR-sourced ([HuntSignal.frontCaptureReady] comes
  /// from field stability, not the quad), so a running front countdown already
  /// implies an OCR-confirmed framed document. The text-dense Peru DNI front
  /// held still makes the native quad find text edges, not a clean 4-corner
  /// card boundary, so [_framingValid] frequently degrades to false at the
  /// completion tick and the strict gate vetoes the shutter until motion yields
  /// a momentarily clean quad — the "captures only when I move" regression
  /// introduced when commit 08a32e4 wired the live quad into the front gate. On
  /// the front, framing degrades OPEN so it never vetoes the fire; document
  /// removal is still caught by the capture-eligibility gate (OCR-derived
  /// `isCaptureable`), so #5540 document-removed protection is preserved.
  ///
  /// The BACK has no OCR readiness signal — its only proof of a framed document
  /// is the quad itself — so it keeps the strict live [_framingValid] gate: a
  /// degrade-closed quad at completion correctly blocks the back, and the
  /// wrong-side guard (#5495/#5499) stays intact.
  bool _fireFramingValid() => _framingSignal().fireFramingValid;

  /// The single unified read of the live quad framing flag, capture-eligibility,
  /// and side context (#5543). All four side-aware quad forks — fire gate,
  /// presence, overlay annotation, empty-OCR routing — derive from this one
  /// value so they can never drift apart. The quad annotates but never vetoes;
  /// the OCR-derived [_frameCaptureable] is the blocking signal.
  FramingSignal _framingSignal() => FramingSignal(
        framingValid: _framingValid,
        captureEligible: _frameCaptureable,
        isFrontPhase: _isFrontPhase(),
      );

  void _triggerCaptureFlash() {
    if (_disposed || !mounted) return;
    _captureFlash.forward(from: 0).whenComplete(() {
      if (_disposed) return;
      _captureFlash.reset();
    });
  }

  @visibleForTesting
  void debugFeedCaptureReady(HuntSignal signal) => _onCaptureReady(signal);

  /// Drives the REAL record-and-dispatch chain a live frame uses: feeds the
  /// OCR-derived [detectedSide]/[addedNewField]/[filledFields] plus the current
  /// quad framing flag into [HuntStateMachine.recordFrame] and dispatches the
  /// EMITTED signal. Unlike [debugFeedCaptureReady] it never injects a capture
  /// signal directly, so a test can prove the machine actually emits
  /// backCaptureReady from realistic textless-back inputs (#5517). Returns the
  /// resulting capture state.
  @visibleForTesting
  DniCaptureState debugProcessFrameForTest({
    required DocumentSide detectedSide,
    required bool addedNewField,
    required int filledFields,
  }) =>
      _recordAndDispatch(
        detectedSide: detectedSide,
        addedNewField: addedNewField,
        filledFields: filledFields,
      );

  /// Drives the REAL empty-OCR branch a textless device frame triggers (#5523):
  /// runs the exact [_handleEmptyOcrFrame] routing (text.isEmpty ->
  /// [resolveEmptyOcrRoute] -> dispatch or skip) against the current framing
  /// flag and phase, WITHOUT pre-resolving a side/field count for the dispatch.
  /// This proves an empty frame actually routes to the back trigger (or is
  /// safely skipped) — the layer the device log fingered.
  @visibleForTesting
  DniCaptureState debugProcessEmptyOcrForTest() => _handleEmptyOcrFrame();

  @visibleForTesting
  DniCaptureState get debugCaptureState => _captureState;

  @visibleForTesting
  HuntPhase get debugHuntPhase => _stateMachine.phase;

  /// Auto-capture countdown progress (0 → 1) currently fed to the hole
  /// overlay. Zero whenever no countdown is running, so the ring is hidden.
  double get _countdownProgress {
    final state = _captureState;
    return state is DniCaptureCountingDown ? state.progress : 0;
  }

  @visibleForTesting
  double get debugCountdownProgress => _countdownProgress;

  @visibleForTesting
  CustomPainter debugBuildHolePainter() => _HolePainter(
        holeSize: Size(widget.holeWidth, widget.holeHeight),
        pulse: _pulse,
        borderColor: Colors.white,
        accentColor: Colors.white,
        overlayColor: const Color(0x99000000),
      );

  @visibleForTesting
  void debugSetLightingValid(bool value) => _lightingValid = value;

  @visibleForTesting
  void debugSetFramingValid(bool value) {
    _framingValid = value;
    if (mounted) setState(() {});
  }

  @visibleForTesting
  void debugSetQuad(
    List<QuadCorner> corners, {
    int frameWidth = 640,
    int frameHeight = 480,
  }) {
    _quadCorners = corners;
    _quadFrameWidth = frameWidth;
    _quadFrameHeight = frameHeight;
    if (mounted) setState(() {});
  }

  @visibleForTesting
  List<QuadCorner> get debugQuadCorners => _quadCorners;

  @visibleForTesting
  void debugSetFrameCaptureable(bool value) {
    _frameCaptureable = value;
    if (mounted) setState(() {});
  }

  @visibleForTesting
  bool get debugManualModeActive => _manualModeActive;

  @visibleForTesting
  void debugResetToScanning() => _resetCaptureToScanning();

  @visibleForTesting
  void debugTriggerSideToggle() => _cameraController.onSideChanged(
        isBackSide: !_cameraController.isBackSide,
      );

  void _safeInvoke(String label, void Function() invoke) {
    try {
      invoke();
    } catch (error, stack) {
      _reportCallbackError(label, error, stack);
    }
  }

  void _reportCallbackError(String label, Object error, StackTrace stack) {
    final onError = widget.onError;
    if (onError != null) {
      onError(error, stack);
      return;
    }
    DniLogger.error('DniScanner', 'host callback $label threw', error, stack);
  }

  void _resetCaptureToScanning() {
    _countdownTicker?.cancel();
    _countdownTicker = null;
    _countdownAnchor = null;
    _countdownElapsedMs = 0;
    _captureState = const DniCaptureScanning(
      guideText: '',
      failingGate: null,
      validationProgress: 0,
      stableFrames: 0,
      userDataMatch: null,
      manualModeActive: false,
    );
    if (mounted) setState(() {});
  }

  void _markCaptureReady() {
    if (_captureReady || !mounted) return;
    setState(() => _captureReady = true);
  }

  Future<void> _onManualCapturePressed() async {
    if (_capturing) return;
    if (_isFrontPhase()) {
      await _captureFront();
    } else if (_stateMachine.phase != HuntPhase.done) {
      await _captureBack();
    }
    if (mounted && _captureReady) {
      setState(() => _captureReady = false);
    }
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

  Future<XFile> _takeLockedPicture() async {
    // Lock failures must never block the capture. CameraController does not
    // normalize platform errors for these calls: iOS surfaces FlutterError
    // as PlatformException, so catching CameraException alone is not enough.
    try {
      await widget.controller.setFocusMode(FocusMode.locked);
      await widget.controller.setExposureMode(ExposureMode.locked);
    } on Exception {
      // proceed without lock
    }
    try {
      return await widget.controller.takePicture();
    } finally {
      try {
        await widget.controller.setFocusMode(FocusMode.auto);
        await widget.controller.setExposureMode(ExposureMode.auto);
      } on Exception {
        // device already without lock support
      }
    }
  }

  Future<_BlurGateOutcome> _evaluateBlurGate(XFile raw) async {
    Uint8List bytes;
    try {
      bytes = await raw.readAsBytes();
    } on Object {
      return _BlurGateOutcome.reject;
    }
    QualityCheckResult verdict;
    try {
      verdict = await _imageQualityGate.validate(bytes);
    } on Object {
      return _BlurGateOutcome.accept;
    }
    switch (verdict) {
      case QualityCheckResult.pass:
        _blurRetries = 0;
        return _BlurGateOutcome.accept;
      case QualityCheckResult.blurry:
        if (_blurRetries >= maxBlurRetries) {
          _blurRetries = 0;
          return _BlurGateOutcome.accept;
        }
        _blurRetries++;
        return _BlurGateOutcome.retry;
      case QualityCheckResult.spoofed:
      case QualityCheckResult.error:
        return _BlurGateOutcome.reject;
    }
  }

  Future<void> _captureFront() async {
    if (_capturing || _frontPhoto != null) return;
    _capturing = true;
    final preview = context.size;
    try {
      final raw = await _takeLockedPicture();
      final outcome = await _evaluateBlurGate(raw);
      if (_disposed) return;
      if (outcome != _BlurGateOutcome.accept) {
        _resetCaptureToScanning();
        return;
      }
      unawaited(_playStepFeedback());
      final cropped =
          await _cropToHole(raw, suffix: 'front', preview: preview) ?? raw;
      _frontPhoto = cropped;
      _maybeStartLookup();
      HapticFeedback.mediumImpact();
      if (widget.isBackSide == false) {
        _stateMachine.advanceToDone();
        if (_reniecLookup != null) await _reniecLookup;
        _safeInvoke(
          'onSideCaptured',
          () => widget.onSideCaptured?.call(
            DniSideScanResult(
              photo: cropped,
              isBackSide: false,
              hunt: _hunter.snapshot,
              reniecData: _reniecData,
            ),
          ),
        );
        return;
      }
      _stateMachine.advanceToWaitingBack();
      // Clear the leftover front DniCaptureInFlight so the back's
      // _onCaptureReady guard passes and its countdown can start (#5535). The
      // front shutter has already completed (post-await), so this never
      // re-arms a capture during the live front; the in-flight re-entry guard
      // stays intact for frames arriving mid-shutter.
      _resetCaptureToScanning();
      // Restart the manual-fallback window for the BACK so it measures from the
      // moment the back starts trying, not from scanner open (#5536). The live
      // handoff does not route through onSideChanged, so without this the back
      // inherits the front's already-elapsing timer and the manual button
      // surfaces before the back auto-capture gets a full window.
      _cameraController.restartManualFallbackTimer();
    } on CameraException catch (e) {
      DniLogger.error('DniScanner', 'front capture failed: ${e.code}');
    } finally {
      _capturing = false;
    }
  }

  void _maybeStartLookup() {
    final service = widget.lookupService;
    if (service == null) return;
    final dni = _hunter.snapshot.fields.documentNumber;
    if (dni == null || dni.isEmpty) return;
    if (_lookupAttemptedDni == dni) return;
    _lookupAttemptedDni = dni;
    _reniecLookup = _runLookup(service, dni);
  }

  Future<void> _runLookup(DniLookupService service, String dni) async {
    try {
      final result = await service
          .lookup(dni)
          .timeout(widget.lookupTimeout, onTimeout: () =>
              const DniLookupNetworkError());
      if (!mounted) return;
      if (result is DniLookupSuccess && result.data.dni == dni) {
        _reniecData = result.data;
        _safeInvoke(
          'onDniReady',
          () => widget.onDniReady?.call(result.data),
        );
      }
    } catch (_) {
      // graceful: missing data is acceptable, OCR remains source of truth
    }
  }

  Future<void> _captureBack() async {
    if (_capturing || _backPhoto != null) return;
    _capturing = true;
    final preview = context.size;
    try {
      final raw = await _takeLockedPicture();
      final outcome = await _evaluateBlurGate(raw);
      if (_disposed) return;
      if (outcome != _BlurGateOutcome.accept) {
        _resetCaptureToScanning();
        return;
      }
      unawaited(_playCompletionFeedback());
      final cropped =
          await _cropToHole(raw, suffix: 'back', preview: preview) ?? raw;
      _backPhoto = cropped;
      _stateMachine.advanceToDone();
      _maybeStartLookup();
      if (_reniecLookup != null) {
        await _reniecLookup;
      }
      if (widget.isBackSide == true) {
        _safeInvoke(
          'onSideCaptured',
          () => widget.onSideCaptured?.call(
            DniSideScanResult(
              photo: cropped,
              isBackSide: true,
              hunt: _hunter.snapshot,
              reniecData: _reniecData,
            ),
          ),
        );
        return;
      }
      if (_frontPhoto != null) {
        final finalSnapshot = _hunter.snapshot;
        _safeInvoke(
          'onScanComplete',
          () => widget.onScanComplete?.call(
            DniScanResult(
              frontPhoto: _frontPhoto!,
              backPhoto: cropped,
              hunt: finalSnapshot,
              reniecData: _reniecData,
            ),
          ),
        );
      }
    } on CameraException catch (e) {
      DniLogger.error('DniScanner', 'back capture failed: ${e.code}');
    } finally {
      _capturing = false;
    }
  }

  Future<void> _playStepFeedback() async {
    await HapticFeedback.vibrate();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await HapticFeedback.vibrate();
    unawaited(SystemSound.play(SystemSoundType.click));
  }

  Future<void> _playCompletionFeedback() async {
    await HapticFeedback.vibrate();
    await Future<void>.delayed(const Duration(milliseconds: 130));
    await HapticFeedback.vibrate();
    await Future<void>.delayed(const Duration(milliseconds: 130));
    await HapticFeedback.vibrate();
    await Future<void>.delayed(const Duration(milliseconds: 130));
    await HapticFeedback.vibrate();
    unawaited(SystemSound.play(SystemSoundType.click));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    unawaited(SystemSound.play(SystemSoundType.click));
  }

  Future<XFile?> _cropToHole(
    XFile source, {
    required String suffix,
    required Size? preview,
  }) async {
    try {
      if (preview == null) return null;
      final dir = await getTemporaryDirectory();
      final outPath =
          '${dir.path}/dni_${suffix}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final request = _CropRequest(
        sourcePath: source.path,
        outPath: outPath,
        previewWidth: preview.width,
        previewHeight: preview.height,
        holeWidth: widget.holeWidth,
        holeHeight: widget.holeHeight,
      );
      final resultPath = await Isolate.run(() => _cropAndEncode(request));
      return resultPath == null ? null : XFile(resultPath);
    } catch (e) {
      DniLogger.error('DniScanner', 'crop failed: $e');
      return null;
    }
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      unawaited(_safeStopStream(widget.controller));
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_startStream());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _countdownTicker?.cancel();
    _focusIndicatorTimer?.cancel();
    _hintRotationTimer?.cancel();
    _cameraController.captureState.removeListener(_onControllerStateChanged);
    unawaited(_cameraController.dispose());
    _motionGate.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    _captureFlash.dispose();
    unawaited(_lifecycle.safeDispose());
    super.dispose();
  }

  Future<void> _focusAt(TapDownDetails details, Size previewSize) async {
    try {
      final normalized = Offset(
        details.localPosition.dx / previewSize.width,
        details.localPosition.dy / previewSize.height,
      );
      await widget.controller.setFocusPoint(normalized);
      await widget.controller.setExposurePoint(normalized);
      await HapticFeedback.selectionClick();
      if (!mounted) return;
      setState(() => _focusIndicator = details.localPosition);
      _focusIndicatorTimer?.cancel();
      _focusIndicatorTimer = Timer(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        setState(() => _focusIndicator = null);
      });
    } on CameraException {
      // device may not support focus point
    }
  }

  String _sideTitle() {
    switch (_stateMachine.phase) {
      case HuntPhase.waitingFront:
      case HuntPhase.extractingFront:
        return 'Frente del DNI';
      case HuntPhase.waitingBack:
      case HuntPhase.extractingBack:
        return 'Reverso del DNI';
      case HuntPhase.done:
        return 'Procesando';
    }
  }

  String _sideHint() {
    final hints = widget.scanHints;
    final list = switch (_stateMachine.phase) {
      HuntPhase.waitingFront => hints.waitingFront,
      HuntPhase.extractingFront => hints.extractingFront,
      HuntPhase.waitingBack => hints.waitingBack,
      HuntPhase.extractingBack => hints.extractingBack,
      HuntPhase.done => [hints.processing],
    };
    if (list.isEmpty) return '';
    return list[_hintIndex % list.length];
  }

  bool _isExtracting() {
    return _stateMachine.phase == HuntPhase.extractingFront ||
        _stateMachine.phase == HuntPhase.extractingBack;
  }

  bool _isFrontPhase() {
    return _stateMachine.phase == HuntPhase.waitingFront ||
        _stateMachine.phase == HuntPhase.extractingFront;
  }

  Future<void> _toggleTorch() async {
    if (!widget.controller.value.isInitialized) return;
    try {
      final next = !_torchOn;
      await widget.controller.setFlashMode(
        next ? FlashMode.torch : FlashMode.off,
      );
      if (mounted) setState(() => _torchOn = next);
    } on CameraException catch (e) {
      debugPrint('DniScanner: torch toggle failed: ${e.code} ${e.description}');
    }
  }

  List<Offset> _quadPreviewPoints(Size previewSize) {
    if (_quadCorners.isEmpty ||
        _quadFrameWidth <= 0 ||
        _quadFrameHeight <= 0) {
      return const <Offset>[];
    }
    final mirror = widget.controller.description.lensDirection ==
        CameraLensDirection.front;
    return mapQuadToPreview(
      corners: _quadCorners,
      frameWidth: _quadFrameWidth,
      frameHeight: _quadFrameHeight,
      rotationDegrees: widget.controller.description.sensorOrientation,
      previewSize: previewSize,
      mirror: mirror,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = KycTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => _focusAt(details, previewSize),
                child: CameraPreview(widget.controller),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _HolePainter(
                    holeSize: Size(widget.holeWidth, widget.holeHeight),
                    pulse: _pulse,
                    borderColor: theme.white,
                    accentColor: _isExtracting() ? theme.success : theme.white,
                    overlayColor: theme.overlayDark,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: QuadOverlayPainter(
                    points: _quadPreviewPoints(previewSize),
                    color: theme.white,
                  ),
                ),
              ),
            ),
            if (_captureState is DniCaptureCountingDown)
              Positioned.fill(
                key: const Key('dni_scanner_countdown_counter'),
                child: IgnorePointer(
                  child: Center(
                    child: _CountdownCounter(
                      digit: countdownDigitFromProgress(
                        _countdownProgress,
                        widget.autoCaptureMs,
                      ),
                    ),
                  ),
                ),
              ),
            _CaptureFlash(animation: _captureFlash),
            if (_focusIndicator != null)
              Positioned(
                left: _focusIndicator!.dx - 36,
                top: _focusIndicator!.dy - 36,
                child: IgnorePointer(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.white, width: 2),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 24,
              right: 24,
              child: _ScannerHeader(
                title: _sideTitle(),
                isFront: _isFrontPhase(),
                done: _stateMachine.phase == HuntPhase.done,
                theme: theme,
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 74,
              left: 24,
              right: 24,
              child: _SideProgress(
                fields: _hunter.snapshot.fields,
                frontTotal: widget.fields?.frontCount,
                backTotal: widget.fields?.backCount,
                isFrontDone: _frontPhoto != null,
                isBackDone: _backPhoto != null,
                isFrontPhase: _isFrontPhase(),
                theme: theme,
              ),
            ),
            Positioned(
              top: (constraints.maxHeight / 2) + (widget.holeHeight / 2) + 24,
              left: 24,
              right: 24,
              child: _ScannerHint(hint: _sideHint(), theme: theme),
            ),
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 32,
              left: 0,
              right: 0,
              child: widget.captureMode != DniCaptureMode.auto ||
                      manualButtonVisible(
                        manualModeActive: _manualModeActive,
                        countdownActive: _captureState is DniCaptureCountingDown,
                        autoCaptureProgressing: _isExtracting(),
                      )
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        _ManualCaptureButton(
                          key: const Key('dni_scanner_manual_capture'),
                          ready: _captureReady,
                          capturing: _capturing,
                          onPressed: _onManualCapturePressed,
                          theme: theme,
                        ),
                        Positioned(
                          right: 40,
                          child: _ScannerFlashToggle(
                            isOn: _torchOn,
                            onToggle: _toggleTorch,
                            theme: theme,
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: _ScannerFlashToggle(
                        isOn: _torchOn,
                        onToggle: _toggleTorch,
                        theme: theme,
                      ),
                    ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _FlipDocumentBanner(
                visible: flipBannerVisible(
                  phase: _stateMachine.phase,
                  captureInFlight: _captureState is DniCaptureInFlight,
                  twoSided: widget.isBackSide == null,
                ),
                guidanceText: widget.flipDocumentText,
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _DocumentAbsentBanner(
                // The flip banner owns the top slot during the front->back
                // hand-off (where a missing document is expected), so the
                // no-document warning yields to it to avoid overlap.
                visible: !flipBannerVisible(
                      phase: _stateMachine.phase,
                      captureInFlight: _captureState is DniCaptureInFlight,
                      twoSided: widget.isBackSide == null,
                    ) &&
                    documentAbsentBannerVisible(
                      documentPresent: _framingSignal().documentPresent,
                      phase: _stateMachine.phase,
                    ),
                guidanceText: widget.scanHints.documentAbsent,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CropRequest {
  const _CropRequest({
    required this.sourcePath,
    required this.outPath,
    required this.previewWidth,
    required this.previewHeight,
    required this.holeWidth,
    required this.holeHeight,
  });

  final String sourcePath;
  final String outPath;
  final double previewWidth;
  final double previewHeight;
  final double holeWidth;
  final double holeHeight;
}

const int _cropMaxDimension = 3000;
const int _cropJpegQuality = 97;

const int _lightingTargetSamples = 64;

class _FrameAnalysisRequest {
  const _FrameAnalysisRequest({
    required this.luminancePlane,
    required this.bytesPerRow,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.detectQuad,
  });

  final List<int> luminancePlane;
  final int bytesPerRow;
  final int width;
  final int height;
  final int rotationDegrees;
  final bool detectQuad;
}

class _FrameAnalysisResult {
  const _FrameAnalysisResult({
    required this.lighting,
    required this.framingValid,
    required this.corners,
  });

  final LightingResult lighting;
  final bool framingValid;
  final List<QuadCorner> corners;
}

/// Runs lighting evaluation and, when requested, native quad detection on the
/// same luminance buffer. Executed inside `Isolate.run`; only plain values
/// cross the boundary. When quad detection is not requested (fallback path),
/// [_FrameAnalysisResult.framingValid] stays true so framing degrades to the
/// OCR-block gate and capture is never blocked.
_FrameAnalysisResult _analyzeFrame(_FrameAnalysisRequest request) {
  final lighting = LightingGate.evaluate(_downscaleLuminance(request));
  if (!request.detectQuad) {
    return _FrameAnalysisResult(
      lighting: lighting,
      framingValid: true,
      corners: const <QuadCorner>[],
    );
  }
  final quad = detectQuadInFrame(
    QuadFrame(
      luminance: Uint8List.fromList(request.luminancePlane),
      width: request.width,
      height: request.height,
      bytesPerRow: request.bytesPerRow,
      rotationDegrees: request.rotationDegrees,
    ),
  );
  return _FrameAnalysisResult(
    lighting: lighting,
    framingValid: quad.framingValid,
    corners: quad.corners,
  );
}

List<int> _downscaleLuminance(_FrameAnalysisRequest request) {
  final width = request.width;
  final height = request.height;
  if (width <= 0 || height <= 0 || request.luminancePlane.isEmpty) {
    return const <int>[];
  }
  final stepX = (width / _lightingTargetSamples).floor().clamp(1, width);
  final stepY = (height / _lightingTargetSamples).floor().clamp(1, height);
  final samples = <int>[];
  for (var y = 0; y < height; y += stepY) {
    final rowStart = y * request.bytesPerRow;
    for (var x = 0; x < width; x += stepX) {
      final index = rowStart + x;
      if (index < request.luminancePlane.length) {
        samples.add(request.luminancePlane[index]);
      }
    }
  }
  return samples;
}

@visibleForTesting
LightingResult analyzeLuminancePlaneForTest({
  required List<int> luminancePlane,
  required int bytesPerRow,
  required int width,
  required int height,
}) =>
    LightingGate.evaluate(
      _downscaleLuminance(
        _FrameAnalysisRequest(
          luminancePlane: luminancePlane,
          bytesPerRow: bytesPerRow,
          width: width,
          height: height,
          rotationDegrees: 0,
          detectQuad: false,
        ),
      ),
    );

@visibleForTesting
class CropRequestForTest {
  const CropRequestForTest({
    required this.sourcePath,
    required this.outPath,
    required this.previewWidth,
    required this.previewHeight,
    required this.holeWidth,
    required this.holeHeight,
  });

  final String sourcePath;
  final String outPath;
  final double previewWidth;
  final double previewHeight;
  final double holeWidth;
  final double holeHeight;
}

@visibleForTesting
String? cropAndEncodeForTest(CropRequestForTest request) => _cropAndEncode(
      _CropRequest(
        sourcePath: request.sourcePath,
        outPath: request.outPath,
        previewWidth: request.previewWidth,
        previewHeight: request.previewHeight,
        holeWidth: request.holeWidth,
        holeHeight: request.holeHeight,
      ),
    );

String? _cropAndEncode(_CropRequest request) {
  final bytes = File(request.sourcePath).readAsBytesSync();
  var decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  if (decoded.width > _cropMaxDimension ||
      decoded.height > _cropMaxDimension) {
    decoded = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: _cropMaxDimension)
        : img.copyResize(decoded, height: _cropMaxDimension);
  }
  final imgWidth = decoded.width;
  final imgHeight = decoded.height;

  final fitScale =
      (imgWidth / request.previewWidth).clamp(0.0, double.infinity);
  final fitScaleH =
      (imgHeight / request.previewHeight).clamp(0.0, double.infinity);
  final scale = fitScale > fitScaleH ? fitScaleH : fitScale;

  final holeWPx = (request.holeWidth * scale).round();
  final holeHPx = (request.holeHeight * scale).round();
  final pad = (24 * scale).round();
  final cropW = (holeWPx + pad * 2).clamp(1, imgWidth);
  final cropH = (holeHPx + pad * 2).clamp(1, imgHeight);
  final cropX = ((imgWidth - cropW) ~/ 2).clamp(0, imgWidth - cropW);
  final cropY = ((imgHeight - cropH) ~/ 2).clamp(0, imgHeight - cropH);

  final crop = img.copyCrop(
    decoded,
    x: cropX,
    y: cropY,
    width: cropW,
    height: cropH,
  );
  File(request.outPath)
      .writeAsBytesSync(img.encodeJpg(crop, quality: _cropJpegQuality));
  return request.outPath;
}

class _ManualCaptureButton extends StatelessWidget {
  const _ManualCaptureButton({
    super.key,
    required this.ready,
    required this.capturing,
    required this.onPressed,
    required this.theme,
  });

  final bool ready;
  final bool capturing;
  final Future<void> Function() onPressed;
  final KycTheme theme;

  @override
  Widget build(BuildContext context) {
    final accent = ready ? theme.success : theme.white;
    return GestureDetector(
      onTap: capturing
          ? null
          : () {
              HapticFeedback.selectionClick();
              unawaited(onPressed());
            },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: capturing ? 0.05 : 0.15),
              border: Border.all(color: accent, width: 3),
            ),
            child: Center(
              child: capturing
                  ? SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(accent),
                      ),
                    )
                  : Icon(
                      Icons.camera_alt_outlined,
                      color: accent,
                      size: 32,
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Capturar',
            style: TextStyle(
              color: accent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              shadows: const [Shadow(blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerFlashToggle extends StatelessWidget {
  const _ScannerFlashToggle({
    required this.isOn,
    required this.onToggle,
    required this.theme,
  });

  final bool isOn;
  final Future<void> Function() onToggle;
  final KycTheme theme;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        unawaited(onToggle());
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isOn
              ? theme.warningIcon
              : Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(
            color: theme.white.withValues(alpha: 0.85),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          isOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
          color: theme.white,
          size: 20,
        ),
      ),
    );
  }
}

/// Maps the auto-capture countdown [progress] (0 → 1) to the digit shown in
/// the centered 3-2-1 counter. [totalMs] is the dwell duration, so the
/// remaining time is `totalMs * (1 - progress)` and the digit is the ceiling
/// of the remaining whole seconds, clamped to 1..3 so the user always sees a
/// digit through the final tick before the shutter fires.
@visibleForTesting
int countdownDigitFromProgress(double progress, int totalMs) {
  final clamped = progress.clamp(0.0, 1.0);
  // Round to whole ms first so exact-second boundaries (e.g. 2000ms remaining)
  // are not pushed up a digit by floating-point dust from the progress ratio.
  final remainingMs = (totalMs * (1 - clamped)).round();
  final digit = (remainingMs / 1000).ceil();
  return digit.clamp(1, 3);
}

/// Whether the flip-document guidance banner should be visible (#5494).
///
/// The banner used to be gated only on `phase == waitingBack`, but that phase
/// is reached only AFTER the slow Camera2 `takePicture`/crop completes. Between
/// the front capture flash and `waitingBack` there is a DEAD WINDOW (the
/// in-flight processing time) during which the user received no guidance — the
/// paso1->paso2 gap (#5491). This widens the visibility so the flip guidance is
/// also shown while the FRONT capture is in flight, giving continuous guidance
/// from the flash through to back scanning.
///
/// It stays a pure visual gate: only [HuntPhase.waitingBack], or a front
/// capture in flight ([HuntPhase.extractingFront] + [captureInFlight]) in
/// two-sided mode, shows the banner. Single-side mode ([twoSided] == false) has
/// no front-to-back transition, and an in-flight BACK capture is past the flip,
/// so neither shows it.
@visibleForTesting
bool flipBannerVisible({
  required HuntPhase phase,
  required bool captureInFlight,
  required bool twoSided,
}) {
  if (phase == HuntPhase.waitingBack) return true;
  return twoSided &&
      captureInFlight &&
      phase == HuntPhase.extractingFront;
}

/// Whether the manual-capture affordance should be shown in auto mode (#5536).
///
/// The manual button is driven by [DniCameraController]'s fallback flag
/// (the early `recoverManual` escape or the per-side fallback timer), a source
/// of truth that runs in PARALLEL to the widget auto-capture countdown and does
/// not know an auto-capture is in progress. On device the button surfaced too
/// soon — while the working auto-capture was still counting down or the side
/// was dwelling toward capture — tempting the user to tap it instead of waiting
/// for the auto-capture that fires on its own.
///
/// This gates the affordance on the auto-capture state so the manual stays a
/// REAL fallback: it is withheld while the 3-2-1 [countdownActive] is on screen
/// OR a side is actively dwelling toward capture ([autoCaptureProgressing]), and
/// only appears once [manualModeActive] is flagged AND no auto-capture is in
/// progress. It does not weaken the fallback — a side that never stabilizes
/// still leaves both progress flags false, so the button appears after the
/// fallback window as before.
@visibleForTesting
bool manualButtonVisible({
  required bool manualModeActive,
  required bool countdownActive,
  required bool autoCaptureProgressing,
}) {
  if (!manualModeActive) return false;
  return !countdownActive && !autoCaptureProgressing;
}

/// Whether a document is actually present and framed this frame (#5540/#5543).
///
/// The 3-2-1 countdown must abort, and the no-document banner must show, if the
/// user REMOVES the DNI mid-count instead of counting down on empty air and
/// capturing nothing. Presence is computed side-aware, mirroring the fire-time
/// framing split in [DniScannerState._fireFramingValid] (#5543), because the
/// two sides prove a framed document through different live signals:
/// - [captureEligible]: the latest processed frame yielded a capture-ready /
///   side-detected signal from [HuntStateMachine] (so OCR/quad confirmed a
///   document), as opposed to a `none`/dropped frame.
/// - [framingValid]: the quad detector confirms a well-framed document quad.
///
/// On the FRONT ([isFrontPhase] true) readiness is OCR-sourced. The text-dense
/// Peru DNI front held still makes the native quad find text edges, not a clean
/// 4-corner card boundary, so [framingValid] frequently degrades to false while
/// the DNI IS present and OCR-confirmed. Gating front presence on the quad made
/// the banner cry "no document" on a present card. Front presence therefore
/// tracks [captureEligible] only — the real per-frame device signal. Removal
/// still drops presence because OCR goes empty (signal=none ->
/// captureEligible=false), so #5540 document-removed protection holds.
///
/// On the BACK ([isFrontPhase] false) there is no OCR readiness signal — the
/// quad IS the only proof of a framed document — so presence stays the strict
/// conjunction of [framingValid] and [captureEligible]: a stale flag alone never
/// keeps it present, and a quad drop when the card leaves the frame aborts.
///
/// The same hysteresis is preserved — a single dropped frame within the grace
/// window (#5504/#5532) does not reset, only a sustained loss.
@visibleForTesting
bool documentPresent({
  required bool framingValid,
  required bool captureEligible,
  required bool isFrontPhase,
}) {
  if (isFrontPhase) return captureEligible;
  return framingValid && captureEligible;
}

/// Whether the top banner should warn that no document is detected (#5540).
///
/// Shown while a side is being scanned ([HuntPhase.waitingFront],
/// [HuntPhase.extractingFront], [HuntPhase.waitingBack],
/// [HuntPhase.extractingBack]) and no document is present in the frame, so the
/// user learns the countdown stopped because the DNI left the frame. Suppressed
/// in [HuntPhase.done]: both sides are captured and the scanner is processing,
/// where a missing document is expected and must not raise the warning.
@visibleForTesting
bool documentAbsentBannerVisible({
  required bool documentPresent,
  required HuntPhase phase,
}) {
  if (documentPresent) return false;
  return phase != HuntPhase.done;
}

/// Honest side-progress ratio for the front/back indicator (#5494).
///
/// The raw field-count ratio (`filled / total`) is DECOUPLED from the capture
/// state machine: the back can reach `7/7 = 100%` while the auto-capture
/// trigger — governed by data STABILITY and the wrong-side SAFETY invariant,
/// not by the raw field count — has not fired. Showing that "100%" implies an
/// imminent or completed capture that the field count cannot promise, which is
/// the misleading indicator the owner saw.
///
/// This keeps the indicator useful (it grows with data so the user sees real
/// progress) but makes it HONEST: the only way to reach a full 100% ring is for
/// the side to actually be captured ([done] == true). A not-done side is capped
/// strictly below 1.0 by [scanningCeiling] so it never claims completion before
/// the capture trigger fires. A non-positive [total] degrades gracefully.
@visibleForTesting
double sideProgressRatio({
  required int filled,
  required int total,
  required bool done,
  double scanningCeiling = 0.95,
}) {
  if (done) return 1.0;
  if (total <= 0) return 0.0;
  final raw = (filled / total).clamp(0.0, 1.0);
  return raw < scanningCeiling ? raw : scanningCeiling;
}

/// How an empty-OCR frame must be routed by the live frame processor (#5523).
enum EmptyOcrRoute {
  /// Drive the single record-and-dispatch chain with empty-OCR back inputs so a
  /// quad-confirmed textless back can still reach backCaptureReady.
  dispatchBackTrigger,

  /// Discard the frame: either no document quad confirms framing (a blank view
  /// is not a document) or the machine is still in a front phase (the front
  /// stays OCR-triggered, never back-triggered by an empty frame).
  skip,
}

/// Routes an empty-OCR frame for [_DniScannerState._processImage] (#5523).
///
/// The Peru DNI back is textless, so OCR is frequently empty. The OCR path can
/// no longer be the only trigger source: when the quad detector has confirmed a
/// well-framed document ([framingValid]) AND the machine has left the front
/// phase ([isFrontPhase] == false), the empty frame must DRIVE the back trigger
/// instead of being discarded — otherwise the early skip wins the race and the
/// textless back never auto-captures. Two guards keep this safe:
/// - NO valid quad => [EmptyOcrRoute.skip]: a blank frame with no document quad
///   must never trigger a capture.
/// - A front phase => [EmptyOcrRoute.skip]: the front is text-dense and stays
///   OCR-triggered; an empty frame must never produce a wrong-side back trigger.
@visibleForTesting
EmptyOcrRoute resolveEmptyOcrRoute({
  required bool framingValid,
  required bool isFrontPhase,
}) {
  if (framingValid && !isFrontPhase) {
    return EmptyOcrRoute.dispatchBackTrigger;
  }
  return EmptyOcrRoute.skip;
}

/// Centered 3-2-1 auto-capture counter rendered in smoke white over the dark
/// overlay. Each digit change plays a short scale-in + fade so the countdown
/// feels intentional without being flashy.
class _CountdownCounter extends StatelessWidget {
  const _CountdownCounter({required this.digit});

  /// Smoke white, kept slightly off pure white for a softer premium feel while
  /// staying high-contrast against the dark overlay.
  static const Color _smokeWhite = Color(0xFFF5F5F5);

  final int digit;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.7, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: Text(
        '$digit',
        key: ValueKey<int>(digit),
        style: const TextStyle(
          color: _smokeWhite,
          fontSize: 96,
          fontWeight: FontWeight.w700,
          height: 1,
          shadows: [
            Shadow(
              color: Color(0x99000000),
              blurRadius: 16,
            ),
          ],
        ),
      ),
    );
  }
}

/// Brief full-screen white flash fired the moment a photo is captured (the
/// dwell countdown completed and the shutter triggered). The opacity ramps up
/// then fades out over a short duration so the user gets an unmistakable but
/// snappy "photo taken" cue. Rendered for both the front and back capture.
class _CaptureFlash extends StatelessWidget {
  const _CaptureFlash({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        if (animation.status == AnimationStatus.dismissed) {
          return const SizedBox.shrink();
        }
        // Ramp opacity up over the first third of the animation, then fade out
        // over the rest, peaking just below opaque so the preview is never
        // fully hidden.
        final t = animation.value;
        final opacity = t < 0.33 ? (t / 0.33) * 0.85 : (1 - t) / 0.67 * 0.85;
        return Positioned.fill(
          key: const Key('dni_scanner_capture_flash'),
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: const ColoredBox(color: Color(0xFFFFFFFF)),
            ),
          ),
        );
      },
    );
  }
}

class _HolePainter extends CustomPainter {
  _HolePainter({
    required this.holeSize,
    required this.pulse,
    required this.borderColor,
    required this.accentColor,
    required this.overlayColor,
  }) : super(repaint: pulse);

  final Size holeSize;
  final Animation<double> pulse;
  final Color borderColor;
  final Color accentColor;
  final Color overlayColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final hole = Rect.fromCenter(
      center: center,
      width: holeSize.width,
      height: holeSize.height,
    );
    const double r = 24;
    const radius = Radius.circular(r);
    final rrect = RRect.fromRectAndRadius(hole, radius);

    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(overlayPath, Paint()..color = overlayColor);

    const armLen = 28.0;
    final cornerPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void drawCorner({
      required Offset arcStart,
      required Offset arcEnd,
      required Offset arrowEndFromStart,
      required Offset arrowEndFromEnd,
      required bool clockwise,
    }) {
      final path = Path()
        ..moveTo(arrowEndFromStart.dx, arrowEndFromStart.dy)
        ..lineTo(arcStart.dx, arcStart.dy)
        ..arcToPoint(arcEnd, radius: radius, clockwise: clockwise)
        ..lineTo(arrowEndFromEnd.dx, arrowEndFromEnd.dy);
      canvas.drawPath(path, cornerPaint);
    }

    drawCorner(
      arcStart: Offset(hole.left + r, hole.top),
      arcEnd: Offset(hole.left, hole.top + r),
      arrowEndFromStart: Offset(hole.left + r + armLen, hole.top),
      arrowEndFromEnd: Offset(hole.left, hole.top + r + armLen),
      clockwise: false,
    );
    drawCorner(
      arcStart: Offset(hole.right - r, hole.top),
      arcEnd: Offset(hole.right, hole.top + r),
      arrowEndFromStart: Offset(hole.right - r - armLen, hole.top),
      arrowEndFromEnd: Offset(hole.right, hole.top + r + armLen),
      clockwise: true,
    );
    drawCorner(
      arcStart: Offset(hole.left + r, hole.bottom),
      arcEnd: Offset(hole.left, hole.bottom - r),
      arrowEndFromStart: Offset(hole.left + r + armLen, hole.bottom),
      arrowEndFromEnd: Offset(hole.left, hole.bottom - r - armLen),
      clockwise: true,
    );
    drawCorner(
      arcStart: Offset(hole.right - r, hole.bottom),
      arcEnd: Offset(hole.right, hole.bottom - r),
      arrowEndFromStart: Offset(hole.right - r - armLen, hole.bottom),
      arrowEndFromEnd: Offset(hole.right, hole.bottom - r - armLen),
      clockwise: false,
    );

    final scanY = hole.top + 24 + (hole.height - 48) * pulse.value;
    final scanLine = Paint()
      ..shader = LinearGradient(
        colors: [
          accentColor.withValues(alpha: 0),
          accentColor.withValues(alpha: 0.85),
          accentColor.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(hole.left, scanY - 1, hole.width, 2))
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(hole.left + 20, scanY),
      Offset(hole.right - 20, scanY),
      scanLine,
    );
  }

  @override
  bool shouldRepaint(covariant _HolePainter old) {
    return old.holeSize != holeSize ||
        old.borderColor != borderColor ||
        old.accentColor != accentColor ||
        old.overlayColor != overlayColor;
  }
}

class _ScannerHeader extends StatelessWidget {
  const _ScannerHeader({
    required this.title,
    required this.isFront,
    required this.done,
    required this.theme,
  });

  final String title;
  final bool isFront;
  final bool done;
  final KycTheme theme;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Text(
        title,
        key: ValueKey(title),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: theme.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          shadows: const [
            Shadow(
              blurRadius: 12,
              color: Color(0x80000000),
              offset: Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerHint extends StatelessWidget {
  const _ScannerHint({required this.hint, required this.theme});

  final String hint;
  final KycTheme theme;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: Container(
          key: ValueKey(hint),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            hint,
            key: const Key('dni_scanner_hint'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _FlipDocumentBanner extends StatefulWidget {
  const _FlipDocumentBanner({
    required this.visible,
    required this.guidanceText,
  });

  final bool visible;
  final String guidanceText;

  @override
  State<_FlipDocumentBanner> createState() => _FlipDocumentBannerState();
}

class _FlipDocumentBannerState extends State<_FlipDocumentBanner>
    with TickerProviderStateMixin {
  late final AnimationController _rotate;

  @override
  void initState() {
    super.initState();
    _rotate = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _rotate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedSlide(
        offset: widget.visible ? Offset.zero : const Offset(0, -1.0),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: widget.visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 280),
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 16,
              left: 20,
              right: 20,
            ),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFB8C00), Color(0xFFF57C00)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RotationTransition(
                    turns: _rotate,
                    child: const Icon(
                      Icons.flip_camera_android_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      widget.guidanceText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Top banner shown when no document is detected in the frame while a side is
/// being scanned (#5540). It tells the user the auto-capture stopped because
/// the DNI left the frame. Mounted permanently and shown/hidden via the same
/// slide+fade pattern as [_FlipDocumentBanner] so it animates in and out.
class _DocumentAbsentBanner extends StatelessWidget {
  const _DocumentAbsentBanner({
    required this.visible,
    required this.guidanceText,
  });

  final bool visible;
  final String guidanceText;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -1.0),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 280),
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 16,
              left: 20,
              right: 20,
            ),
            child: Container(
              key: const Key('dni_scanner_document_absent_banner'),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xE6212121),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.document_scanner_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      guidanceText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SideProgress extends StatelessWidget {
  const _SideProgress({
    required this.fields,
    required this.isFrontDone,
    required this.isBackDone,
    required this.isFrontPhase,
    required this.theme,
    this.frontTotal,
    this.backTotal,
  });

  final ExtractedFields fields;
  final bool isFrontDone;
  final bool isBackDone;
  final bool isFrontPhase;
  final KycTheme theme;

  final int? frontTotal;
  final int? backTotal;

  static const int _frontTotalDefault = 12;
  static const int _backTotalDefault = 7;

  int _frontFilled() {
    final f = fields;
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
    if (f.stateCivil != null) n++;
    if (f.cardNumber != null) n++;
    return n;
  }

  int _backFilled() {
    final f = fields;
    var n = 0;
    if (f.address != null) n++;
    if (f.department != null) n++;
    if (f.province != null) n++;
    if (f.district != null) n++;
    if (f.organDonor != null) n++;
    if (f.votingGroup != null) n++;
    if (f.birthUbigeoCode != null) n++;
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final frontFilled = _frontFilled();
    final backFilled = _backFilled();
    final effectiveFrontTotal =
        (frontTotal ?? _frontTotalDefault).clamp(1, _frontTotalDefault);
    final effectiveBackTotal =
        (backTotal ?? _backTotalDefault).clamp(1, _backTotalDefault);
    // Honest readiness-aware progress: a side that has not actually captured
    // can never display 100%, because the auto-capture trigger is governed by
    // data stability and the wrong-side invariant — not by this raw field
    // count (#5494).
    final frontProgress = sideProgressRatio(
      filled: frontFilled,
      total: effectiveFrontTotal,
      done: isFrontDone,
    );
    final backProgress = sideProgressRatio(
      filled: backFilled,
      total: effectiveBackTotal,
      done: isBackDone,
    );

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(32),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _SideDot(
              label: 'Frente',
              progress: frontProgress,
              done: isFrontDone,
              active: !isFrontDone && isFrontPhase,
              theme: theme,
            ),
            Container(
              width: 28,
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: isFrontDone
                  ? theme.success
                  : theme.white.withValues(alpha: 0.35),
            ),
            _SideDot(
              label: 'Reverso',
              progress: backProgress,
              done: isBackDone,
              active: isFrontDone && !isBackDone,
              theme: theme,
            ),
          ],
        ),
      ),
    );
  }
}

class _SideDot extends StatelessWidget {
  const _SideDot({
    required this.label,
    required this.progress,
    required this.done,
    required this.active,
    required this.theme,
  });

  final String label;
  final double progress;
  final bool done;
  final bool active;
  final KycTheme theme;

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).round();
    final ringColor = done
        ? theme.success
        : active
            ? theme.success
            : theme.white.withValues(alpha: 0.55);
    final trackColor = theme.white.withValues(alpha: 0.22);
    final labelColor = done || active
        ? theme.white
        : theme.white.withValues(alpha: 0.7);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: progress),
                  duration: const Duration(milliseconds: 350),
                  builder: (context, value, _) {
                    return CircularProgressIndicator(
                      value: value,
                      strokeWidth: 3.5,
                      backgroundColor: trackColor,
                      valueColor: AlwaysStoppedAnimation<Color>(ringColor),
                    );
                  },
                ),
              ),
              done
                  ? Icon(Icons.check, color: theme.success, size: 22)
                  : Text(
                      '$percent%',
                      style: TextStyle(
                        color: labelColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            color: labelColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            shadows: const [
              Shadow(blurRadius: 6, color: Color(0x66000000)),
            ],
          ),
        ),
      ],
    );
  }
}


