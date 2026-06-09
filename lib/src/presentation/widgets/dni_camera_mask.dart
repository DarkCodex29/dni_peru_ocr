import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../data/ocr_consensus.dart';
import '../../data/ocr_field_extractor.dart';
import '../../domain/capture/capture_decider.dart';
import '../../domain/entities/user_verification_data.dart';
import '../../domain/extraction/dni_fields.dart';
import '../../domain/extraction/field_hunter.dart';
import '../../domain/extraction/hunt_result.dart';
import '../../lookup/models/dni_data.dart';
import '../../lookup/services/dni_lookup_service.dart';
import '../../infrastructure/breadcrumb_throttle.dart';
import '../../infrastructure/detector_lifecycle.dart';
import '../../infrastructure/input_image_converter.dart';
import '../../infrastructure/kyc_image_utils.dart';
import '../../infrastructure/tilt_calculator.dart';
import '../camera_overlay_logic.dart';
import '../document_validator.dart';
import '../theme/kyc_theme.dart';
import '../controllers/dni_camera_controller.dart';
import '../orchestrators/dni_capture_orchestrator.dart';
import '../orchestrators/dni_capture_state.dart';
import '_mask_painter.dart';
import '_shared_scan_widgets.dart';

part '_camera_overlay_widgets.dart';

class DniCameraMask extends StatefulWidget {
  const DniCameraMask({
    super.key,
    required this.controller,
    required this.onValidCapture,
    this.holeWidth = 300,
    this.holeHeight = 188,
    this.isLoading = false,
    this.isBackSide = false,
    this.topContent,
    this.userVerificationData,
    this.onDocumentExpired,
    this.kycV2Enabled = true,
    this.frontSideFields,
    this.onFrontSideOcrUpdated,
    this.fieldHunter,
    this.onFieldsUpdated,
    this.onCaptureReady,
    this.captureDecider = const CaptureDecider(),
    this.lookupService,
    this.onDniReady,
    this.lookupTimeout = const Duration(milliseconds: 1500),
    this.fields,
  });

  final CameraController controller;

  /// On back-side captures the second arg carries the accumulated
  /// [OcrConsensusResult]; on front captures it is `null`.
  final void Function(XFile file, OcrConsensusResult? consensus) onValidCapture;
  final double holeWidth;
  final double holeHeight;
  final bool isLoading;
  final bool isBackSide;
  final Widget? topContent;
  final UserVerificationData? userVerificationData;

  /// Fired once when the MRZ locks with an expiration date in the past.
  /// The capture is skipped so the caller can prompt the user to abort.
  final void Function(DateTime expirationDate)? onDocumentExpired;

  /// Enables the consensus-driven back-side capture pipeline. Hosts can
  /// disable to fall back to a single-frame capture without consensus.
  final bool kycV2Enabled;

  /// Optional seed for the back-side consensus accumulator.
  ///
  /// Flutter destroys a widget's [State] when the host swaps its enclosing
  /// widget by type (e.g. a `switch` over an enum step), so two
  /// [DniCameraMask] instances mounted for the front and back side do NOT
  /// share `_accumulatedFields`. Without a seed, the back-side accumulator
  /// starts empty and discards every OCR vote the front side collected.
  ///
  /// Pattern: **State holder injection.** The host (Bloc / Cubit / parent
  /// State) is the source of truth for cross-side OCR memory. It persists
  /// the fields emitted by [onFrontSideOcrUpdated] during the front-side
  /// scan and feeds them back here when constructing the back-side widget.
  ///
  /// Ignored when `isBackSide == false`.
  final OcrExtractedFields? frontSideFields;

  /// Optional callback emitted while scanning the FRONT side, every time the
  /// internal `_accumulatedFields` learns a new field. Hosts can persist
  /// these values (e.g. into a Bloc state) so they can be fed back as
  /// [frontSideFields] when the back-side widget is mounted.
  ///
  /// Ignored on back-side captures (`isBackSide == true`).
  final void Function(OcrExtractedFields fields)? onFrontSideOcrUpdated;

  /// Optional field hunter. When provided, the widget switches to the
  /// evidence-driven capture flow: side is inferred from OCR anchors, fields
  /// accumulate across every frame regardless of host hints, and capture
  /// fires when the hunter reports completeness plus stable framing.
  final FieldHunter? fieldHunter;

  /// Emits the current hunt snapshot on every processed frame when
  /// [fieldHunter] is provided.
  final void Function(HuntResult result)? onFieldsUpdated;

  /// Fires once when the [captureDecider] determines fields are complete and
  /// framing is stable. Replaces [onValidCapture] in the new API.
  final void Function(XFile file, HuntResult result)? onCaptureReady;

  /// Resolves the capture decision from a [HuntResult] and the framing
  /// stability flag. Defaults to the standard decider.
  final CaptureDecider captureDecider;

  final DniLookupService? lookupService;

  final void Function(DniData)? onDniReady;

  final Duration lookupTimeout;

  /// Restricts the FieldHunter path to the specified fields. When null,
  /// all 19 fields are extracted (v0.10.0 behavior).
  ///
  /// This parameter ONLY applies to the [fieldHunter] pipeline. The legacy
  /// [OcrConsensusAccumulator] path is not filtered by [fields] and always
  /// runs unmodified.
  final DniFields? fields;

  @override
  State<DniCameraMask> createState() => _DniCameraMaskState();
}

class _DniCameraMaskState extends State<DniCameraMask>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  KycTheme get _theme => KycTheme.of(context);

  late final TextRecognizer _textRecognizer;

  bool _isProcessing = false;
  int _frameCount = 0;
  bool _showFlash = false;
  bool _torchOn = false;
  bool _showSideIntro = false;
  Timer? _sideIntroTimer;
  bool _isDisposed = false;
  late final DetectorLifecycle _lifecycle;
  final OcrExtractedFields _accumulatedFields = OcrExtractedFields();

  FieldHunter? _effectiveHunter;

  @visibleForTesting
  FieldHunter? get effectiveFieldHunter => _effectiveHunter;

  bool _expiredHandled = false;
  Timer? _consensusWindowTimer;

  int _lastBlockCount = 0;
  int _stableFrames = 0;
  int _tiltBadFrames = 0;
  Size? _screenSize;

  // ─── G.1 Telemetry (diagnostic-only; safe in release) ──────────────────────
  final BreadcrumbThrottle _gateBreadcrumbThrottle = BreadcrumbThrottle();
  double _telemetryTilt = 0;
  double? _telemetryMlkitAngle;
  int _telemetryLines = 0;
  int _telemetryRawBlocks = 0;
  int _telemetryRotation = 0;
  String _telemetryFormat = '-';

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  late final AnimationController _scanController;
  late final Animation<double> _scanAnimation;
  late final AnimationController _countdownController;

  // ─── DniCameraController wiring ────────────────────────────────────────────
  late final DniCameraController _captureController;

  /// Exposes the internal controller for integration tests.
  @visibleForTesting
  DniCameraController get captureController => _captureController;

  static const int _autoCaptureMs = CameraOverlayTuning.autoCaptureMs;

  String get _loadingMessage => loadingMessage(
        isLoading: widget.isLoading,
        isBackSide: widget.isBackSide,
      );

  String get _initialGuideText => initialGuideText(isFaceHole: false);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: CameraOverlayTuning.pulseAnimationMs,
      ),
    );
    unawaited(_pulseController.repeat(reverse: true));
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: CameraOverlayTuning.scanAnimationMs,
      ),
    );
    unawaited(_scanController.repeat());
    _scanAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_scanController);
    _countdownController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _autoCaptureMs),
    );

    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    _effectiveHunter = widget.fieldHunter ??
        (widget.fields != null
            ? FieldHunter.standard(fields: widget.fields)
            : null);
    _lifecycle = DetectorLifecycle(
      stopStream: () => _safeStopStream(widget.controller),
      closeDetectors: _closeDetectors,
    );

    // Build internal orchestrator + controller
    final orchestrator = DniCaptureOrchestrator(
      autoCaptureMs: CameraOverlayTuning.autoCaptureMs,
      gracePeriodMs: CameraOverlayTuning.gracePeriodMs,
      manualFallbackMs: CameraOverlayTuning.manualFallbackMs,
      minStableFrames: CameraOverlayTuning.minStableFrames,
    );
    _captureController = DniCameraController(
      orchestrator: orchestrator,
      isBackSide: widget.isBackSide,
      onValidCapture: widget.onValidCapture,
      onDocumentExpired: widget.onDocumentExpired,
      lookupService: widget.lookupService,
      onDniReady: widget.onDniReady,
      lookupTimeout: widget.lookupTimeout,
    );

    // Listen to captureState for side effects: countdown arc and capture trigger
    _captureController.captureState.addListener(_onCaptureStateChanged);

    if (widget.isBackSide) {
      // Seed the back-side consensus accumulator with the front-side OCR
      // fields the host persisted across the step transition. Required
      // because Flutter destroys the front widget's `_accumulatedFields`
      // when the host swaps to the back-side instance; without the seed,
      // the back-side snapshot would emit nulls whenever the back MRZ
      // arrives partial.
      _captureController.onSideChanged(
        isBackSide: true,
        frontSideFields: widget.frontSideFields,
      );
    }
    _startStream();
    unawaited(_captureController.start());
    if (widget.isBackSide) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _triggerSideIntro();
      });
    }
  }

  void _triggerSideIntro() {
    if (!mounted) return;
    setState(() => _showSideIntro = true);
    _sideIntroTimer?.cancel();
    _sideIntroTimer = Timer(
      const Duration(seconds: CameraOverlayTuning.sideIntroSeconds),
      () {
        if (mounted) setState(() => _showSideIntro = false);
      },
    );
  }

  // ─── State change listener ─────────────────────────────────────────────────

  void _onCaptureStateChanged() {
    if (_isDisposed || !mounted) return;
    final state = _captureController.captureState.value;

    // Drive countdown animation from state
    if (state is CountingDownWithAnchor) {
      final progress = state.progress;
      if (_countdownController.value != progress) {
        _countdownController.value = progress;
      }
    } else if (state is DniCaptureInFlight) {
      _countdownController.stop();
      // Fire shutter when state transitions to InFlight
      if (state.showFlash && !_showFlash) {
        unawaited(_triggerShutter());
      }
    } else {
      _countdownController.reset();
    }

    // Rebuild for guide text / border color changes
    if (mounted) setState(() {});
  }

  // ─── Capture shutter ────────────────────────────────────────────────────────

  Future<void> _triggerShutter() async {
    if (_isDisposed) return;
    setState(() => _showFlash = true);
    await Future<void>.delayed(
      const Duration(milliseconds: CameraOverlayTuning.captureFlashMs),
    );
    if (mounted) setState(() => _showFlash = false);

    try {
      final raw = await widget.controller.takePicture();
      unawaited(HapticFeedback.heavyImpact());
      final shouldCrop = widget.kycV2Enabled;
      final outFile = shouldCrop
          ? XFile(
              await KycImageUtils.cropToDocumentArea(
                raw.path,
                holeWidth: widget.holeWidth,
                holeHeight: widget.holeHeight,
                screenSize: _screenSize!,
              ),
            )
          : raw;
      final captureConsensus =
          widget.isBackSide ? _captureController.snapshotConsensus() : null;
      _captureController.onCaptureDelivered(
        file: outFile,
        consensus: captureConsensus,
      );
      if (_effectiveHunter != null) {
        widget.onCaptureReady?.call(outFile, _effectiveHunter!.snapshot);
      }
    } on CameraException catch (_) {
      // Restore scanning state on camera failure
      if (mounted) {
        setState(() => _showFlash = false);
        _startStream();
        unawaited(_captureController.start());
      }
    }
  }

  // Closes ML Kit detectors. Called by [DetectorLifecycle] only after all
  // in-flight frames have completed, eliminating the SIGSEGV race condition.
  Future<void> _closeDetectors() async {
    await _textRecognizer.close();
  }

  void _startStream() {
    if (!widget.controller.value.isInitialized ||
        widget.controller.value.isStreamingImages) {
      return;
    }
    unawaited(_safeStartStream());
  }

  Future<void> _safeStartStream() async {
    try {
      await widget.controller.startImageStream(_onCameraImage);
    } on CameraException catch (_) {}
  }

  void _stopStream() {
    unawaited(_safeStopStream(widget.controller));
  }

  Future<void> _safeStopStream(CameraController controller) async {
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } on CameraException catch (_) {}
  }

  @override
  void didUpdateWidget(DniCameraMask old) {
    super.didUpdateWidget(old);

    if (old.controller != widget.controller) {
      unawaited(_safeStopStream(old.controller));
      _resetState();
      _startStream();
      return;
    }

    // Flutter reuses this State instance when the step toggles isBackSide,
    // so initState's check never re-runs — handle the transition here.
    // The controller now owns the OcrConsensusAccumulator lifecycle:
    // onSideChanged(isBackSide: true, frontSideFields: ...) creates and seeds it.
    if (!old.isBackSide && widget.isBackSide) {
      _expiredHandled = false;
      _triggerSideIntro();
      // Delegate accumulator creation + seeding to the controller.
      _captureController.onSideChanged(
        isBackSide: true,
        frontSideFields: _accumulatedFields,
      );
    }
    if (old.isBackSide && !widget.isBackSide) {
      _consensusWindowTimer?.cancel();
      _consensusWindowTimer = null;
      _expiredHandled = false;
      _captureController.onSideChanged(isBackSide: false);
    }

    if (old.isLoading && !widget.isLoading) {
      _startStream();
      unawaited(_captureController.start());
    }
  }

  void _resetState() {
    _frameCount = 0;
    _isProcessing = false;
    _showFlash = false;
    _lastBlockCount = 0;
    _stableFrames = 0;
    _tiltBadFrames = 0;
    _countdownController.reset();
    _captureController.onSideChanged();
    unawaited(_captureController.start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final captureState = _captureController.captureState.value;
    final isCapturing = captureState is DniCaptureInFlight;
    if (state == AppLifecycleState.inactive) {
      _stopStream();
    } else if (state == AppLifecycleState.resumed) {
      if (!isCapturing && !widget.isLoading) _startStream();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _captureController.captureState.removeListener(_onCaptureStateChanged);
    _sideIntroTimer?.cancel();
    _consensusWindowTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _scanController.dispose();
    _countdownController.dispose();
    unawaited(_captureController.dispose());
    // Flutter's dispose() is synchronous — we cannot await here.
    // _lifecycle.safeDispose() handles the full async sequence:
    //   1. Stop the camera stream (no new frames arrive)
    //   2. Drain any in-flight _processFrame to completion
    //   3. Close ML Kit detectors (deterministic, no race condition)
    unawaited(_lifecycle.safeDispose());
    super.dispose();
  }

  void _onCameraImage(CameraImage image) {
    if (_isDisposed) return;
    // Skip if capture is already in-flight or expired
    final captureState = _captureController.captureState.value;
    if (captureState is DniCaptureInFlight ||
        captureState is DniCaptureExpired ||
        captureState is DniCaptureDone) {
      return;
    }
    _frameCount++;
    if (_frameCount % 3 != 0) return;
    if (_isProcessing) return;
    _isProcessing = true;
    unawaited(_lifecycle.trackInflight(() => _processFrame(image)));
  }

  Future<void> _processFrame(CameraImage image) async {
    try {
      final inputImage = InputImageConverter.fromCameraImage(
        image,
        widget.controller.description,
      );
      if (inputImage == null) return;

      // ML Kit returns bounding boxes in the post-rotation (display) space.
      final sensorOrientation = widget.controller.description.sensorOrientation;
      final isRotated = sensorOrientation == 90 || sensorOrientation == 270;
      final imageSize = Size(
        isRotated ? image.height.toDouble() : image.width.toDouble(),
        isRotated ? image.width.toDouble() : image.height.toDouble(),
      );

      if (_isDisposed) return;

      await _processDocument(inputImage, imageSize);
    } finally {
      _isProcessing = false;
    }
  }

  /// Filtra bloques OCR dejando solo los que intersectan con la zona del hole.
  RecognizedText _filterBlocksInHole(
    RecognizedText recognized,
    Size imageSize,
  ) =>
      filterBlocksInHole(recognized, imageSize);

  Future<void> _processDocument(
    InputImage inputImage,
    Size imageSize,
  ) async {
    final raw = await _textRecognizer.processImage(inputImage);
    if (!mounted) return;

    final recognized = _filterBlocksInHole(raw, imageSize);

    final userData = widget.userVerificationData;
    bool? dataMatch;
    if (userData != null && recognized.blocks.isNotEmpty) {
      final fullText = recognized.blocks.map((b) => b.text).join(' ');
      dataMatch = userData.matchesText(fullText);
    }

    final result = DocumentValidationResult.evaluate(
      recognizedText: recognized,
      imageSize: imageSize,
      ocrMatchesUser: dataMatch == true,
      isBackSide: widget.isBackSide,
    );

    // ─── G.1 telemetry capture ─────────────────────────────────────────────
    final tiltDeg = computeMedianTiltDegrees(recognized);
    final mlkitAngle = computeMlkitMedianAngleDegrees(recognized);
    _telemetryTilt = tiltDeg;
    _telemetryMlkitAngle = mlkitAngle;
    _telemetryLines = recognized.blocks.length;
    _telemetryRawBlocks = raw.blocks.length;
    _telemetryRotation = widget.controller.description.sensorOrientation;
    _telemetryFormat = widget.controller.imageFormatGroup?.name ?? '-';

    final blockDiff = (recognized.blocks.length - _lastBlockCount).abs();
    _lastBlockCount = recognized.blocks.length;
    _stableFrames = StabilityState.update(
      current: _stableFrames,
      blockDiff: blockDiff,
      isEmpty: recognized.blocks.isEmpty,
    );

    if (_effectiveHunter != null && recognized.blocks.isNotEmpty) {
      final ocrText =
          recognized.blocks.map((b) => b.text).join('\n');
      _effectiveHunter!.process(ocrText);
      final snapshot = _effectiveHunter!.snapshot;
      widget.onFieldsUpdated?.call(snapshot);
      final signal = widget.captureDecider.decide(
        hunt: snapshot,
        framingStable: result.isCaptureable,
      );
      if (signal.shouldCapture) {
        final captureState = _captureController.captureState.value;
        if (captureState is! DniCaptureInFlight &&
            captureState is! DniCaptureExpired &&
            captureState is! DniCaptureDone) {
          _captureController.captureManually();
        }
      }
    }

    DateTime? expirationDate;

    if (recognized.blocks.isNotEmpty) {
      final frameFields = OcrFieldExtractor.extract(recognized);
      _accumulatedFields.merge(frameFields);
      // Notify the host about front-side OCR progress so it can persist the
      // fields across the step transition and feed them back as
      // [DniCameraMask.frontSideFields] when the back-side widget mounts.
      // Throttle: only fire when the merge produced a change.
      if (!widget.isBackSide && widget.onFrontSideOcrUpdated != null) {
        widget.onFrontSideOcrUpdated!(_accumulatedFields);
      }

      // KYC v2: expiration gate
      if (widget.kycV2Enabled && frameFields.hasMrzData && !_expiredHandled) {
        final expired = _expirationFromFields(frameFields.expirationDate);
        if (expired != null) {
          _expiredHandled = true;
          expirationDate = expired;
          _stopStream();
        }
      }

      // Delegate consensus accumulation to the controller (PR4).
      // The controller owns the OcrConsensusAccumulator lifecycle.
      if (expirationDate == null && widget.isBackSide) {
        _consensusWindowTimer ??= Timer(
          const Duration(seconds: CameraOverlayTuning.consensusWindowSeconds),
          () {},
        );

        final consensusReached = _captureController.recordOcrFrame(frameFields);
        if (consensusReached) {
          final captureState = _captureController.captureState.value;
          if (captureState is! DniCaptureInFlight &&
              captureState is! DniCaptureExpired &&
              captureState is! DniCaptureDone) {
            _captureController.captureManually();
          }
        }
      }

      if (kDebugMode) {
        final src = _accumulatedFields.hasMrzData ? 'MRZ' : 'TEXT';
        debugPrint(
          '─── OCR [$src] [${recognized.blocks.length}/${raw.blocks.length} bloques] '
          'match=$dataMatch '
          '(${_accumulatedFields.foundCount}/${_accumulatedFields.totalCount}) ───',
        );
        debugPrint(_accumulatedFields.toString());
      }
    }

    // Debounce "Endereza el documento"
    const enderezaMsg = 'Endereza el documento';
    if (result.message == enderezaMsg) {
      _tiltBadFrames++;
      if (_tiltBadFrames < 3) return;
    } else {
      _tiltBadFrames = 0;
    }

    // Delegate to controller for state transitions
    _captureController.processFrame(
      validation: result,
      stableFrames: _stableFrames,
      userDataMatch: dataMatch,
      expirationDate: expirationDate,
      failingGate: result.failingGate?.sentryCode,
      tiltDegrees: _telemetryTilt,
      rawBlockCount: _telemetryRawBlocks,
      filteredBlockCount: _telemetryLines,
    );

    _emitGateBreadcrumb(
      failingGate: result.failingGate?.sentryCode,
      stableFrames: _stableFrames,
    );
  }

  /// Throttled (≤1 Hz) Sentry breadcrumb emission for the G.1 telemetry.
  void _emitGateBreadcrumb({
    required String? failingGate,
    required int stableFrames,
  }) {
    if (failingGate == null) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!_gateBreadcrumbThrottle.tryAcquire(nowMs)) return;

    _captureController.emitBreadcrumb(
      'kyc.gate',
      'gate_failed',
      data: <String, Object?>{
        'tilt': _telemetryTilt,
        'mlkit_angle': _telemetryMlkitAngle,
        'lines': _telemetryLines,
        'blocks_raw': _telemetryRawBlocks,
        'rot': _telemetryRotation,
        'fmt': _telemetryFormat,
        'failing_gate': failingGate,
        'stable_frames': stableFrames,
      },
    );
  }

  /// Parses DD/MM/YYYY (MRZ extractor format). Returns the DateTime only
  /// when it is in the past; returns null for valid or unparseable dates.
  DateTime? _expirationFromFields(String? raw) => expirationIfPast(raw);

  Future<void> _toggleTorch() async {
    try {
      final newMode = _torchOn ? FlashMode.off : FlashMode.torch;
      await widget.controller.setFlashMode(newMode);
      if (mounted) setState(() => _torchOn = !_torchOn);
    } on CameraException catch (_) {}
  }

  // ─── Derived state helpers for build() ─────────────────────────────────────

  /// Guide text from the current [DniCaptureState].
  String get _guideText {
    final state = _captureController.captureState.value;
    if (state is DniCaptureScanning) return state.guideText;
    if (state is DniCaptureCountingDown) return state.guideText;
    return _initialGuideText;
  }

  /// Border color derived from the current state and telemetry.
  Color get _borderColor {
    final state = _captureController.captureState.value;
    if (state is DniCaptureScanning) {
      // Use result's borderColor — carry it via telemetry's failingGate.
      if (state.failingGate != null) return _theme.accentOrange;
      return _theme.white;
    }
    if (state is DniCaptureCountingDown) return _theme.success;
    if (state is DniCaptureInFlight) return _theme.success;
    return _theme.white;
  }

  bool get _isCaptureable {
    final state = _captureController.captureState.value;
    return state is DniCaptureCountingDown || state is DniCaptureInFlight;
  }

  bool get _manualModeActiveFromState {
    final state = _captureController.captureState.value;
    return state is DniCaptureScanning && state.manualModeActive;
  }

  bool get _isCapturingFromState {
    final state = _captureController.captureState.value;
    return state is DniCaptureInFlight || _showFlash;
  }

  bool? get _userDataMatchFromState {
    final state = _captureController.captureState.value;
    if (state is DniCaptureScanning) return state.userDataMatch;
    if (state is DniCaptureCountingDown) return null;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = KycTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _screenSize = Size(constraints.maxWidth, constraints.maxHeight);
        final manualModeActive = _manualModeActiveFromState;
        final isCapturingOrLoading = _isCapturingFromState || widget.isLoading;
        final userDataMatch = _userDataMatchFromState;

        return Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(widget.controller),
            ValueListenableBuilder<DniCaptureState>(
              valueListenable: _captureController.captureState,
              builder: (context, state, _) {
                return AnimatedBuilder(
                  animation: Listenable.merge([
                    _pulseAnimation,
                    _scanAnimation,
                    _countdownController,
                  ]),
                  builder: (context, _) {
                    final isPulsing = !_isCaptureable &&
                        !widget.isLoading &&
                        !_isCapturingFromState;
                    return CustomPaint(
                      painter: MaskPainter(
                        holeWidth: widget.holeWidth,
                        holeHeight: widget.holeHeight,
                        borderColor: isPulsing
                            ? _borderColor.withValues(
                                alpha: _pulseAnimation.value)
                            : _borderColor,
                        overlayColor: theme.overlayDark,
                        countdownProgress: _countdownController.value,
                        scanProgress: _scanAnimation.value,
                      ),
                    );
                  },
                );
              },
            ),
            if (widget.topContent != null)
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                left: 0,
                right: 52,
                child: widget.topContent!,
              ),
            Positioned(
              bottom: manualModeActive
                  ? MediaQuery.of(context).padding.bottom + 96
                  : MediaQuery.of(context).padding.bottom + 32,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(
                    milliseconds: CameraOverlayTuning.torchSwitcherFadeMs,
                  ),
                  child: ScannerFlashToggle(
                    key: ValueKey<bool>(_torchOn),
                    isOn: _torchOn,
                    onToggle: _toggleTorch,
                    theme: theme,
                  ),
                ),
              ),
            ),
            if (isCapturingOrLoading)
              ColoredBox(
                color: theme.overlayMedium,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.isLoading && !widget.isBackSide)
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF69F0AE),
                          size: 52,
                        )
                      else
                        CircularProgressIndicator(color: theme.white),
                      const SizedBox(height: 16),
                      Text(
                        _loadingMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.white,
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (!manualModeActive)
              Positioned(
                top: MediaQuery.sizeOf(context).height / 2 +
                    widget.holeHeight / 2 +
                    16,
                left: 32,
                right: 32,
                child: Center(
                  child: ScannerHint(hint: _guideText, theme: theme),
                ),
              ),
            if (_showFlash)
              IgnorePointer(
                child: ColoredBox(color: theme.white60),
              ),
            if (manualModeActive && !_isCapturingFromState && !widget.isLoading)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _ManualCapturePanel(
                  isBackSide: widget.isBackSide,
                  onPressed: () => _captureController.captureManually(),
                ),
              ),
            if (userDataMatch != null &&
                !_isCapturingFromState &&
                !widget.isLoading)
              _DataMatchIndicator(
                matches: userDataMatch,
                bottom: manualModeActive ? 208 : 80,
              ),
            if (widget.isBackSide)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: FlipDocumentBanner(
                  visible: _showSideIntro,
                ),
              ),
            if (kDebugMode)
              ValueListenableBuilder<DniTelemetry>(
                valueListenable: _captureController.telemetry,
                builder: (context, telemetry, _) {
                  return Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 8,
                    child: IgnorePointer(
                      child: _G1TelemetryOverlay(
                        tilt: _telemetryTilt,
                        mlkitAngle: _telemetryMlkitAngle,
                        lines: _telemetryLines,
                        rawBlocks: _telemetryRawBlocks,
                        rotation: _telemetryRotation,
                        format: _telemetryFormat,
                        stableFrames: telemetry.stableFrames,
                        failingGate: telemetry.failingGate,
                        perfectSinceMs: -1,
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

/// Pure helper for the document stability counter.
///
/// Encapsulates the update logic for `_stableFrames` so it can be tested
/// independently from the widget's camera image stream.
///
/// The `update` method receives the current counter value, the absolute
/// block-count diff between frames, and an isEmpty flag. It returns the
/// new counter value to assign to `_stableFrames`.
@visibleForTesting
class StabilityState {
  const StabilityState._();

  /// Returns the next value of the stability counter.
  ///
  /// A frame is "stable" when [blockDiff] ≤ 2 AND [isEmpty] is false.
  /// Stable → increment by 1.
  /// Unstable → decrement by 1, floored at 0 (REQ-STAB-1 forgiveness).
  static int update({
    required int current,
    required int blockDiff,
    required bool isEmpty,
  }) {
    if (blockDiff <= 2 && !isEmpty) {
      return current + 1;
    }
    return math.max(0, current - 1);
  }
}
