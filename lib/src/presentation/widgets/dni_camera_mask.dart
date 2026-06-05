import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '_camera_overlay_widgets.dart';
import '_mask_painter.dart';

import '../../data/ocr_consensus.dart';
import '../../data/ocr_field_extractor.dart';
import '../../domain/entities/user_verification_data.dart';
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

  OcrConsensusBuilder? _consensusBuilder;
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
      onValidCapture: (file, consensus) {
        widget.onValidCapture(file as XFile, consensus as OcrConsensusResult?);
      },
      onDocumentExpired: widget.onDocumentExpired,
    );

    // Listen to captureState for side effects: countdown arc and capture trigger
    _captureController.captureState.addListener(_onCaptureStateChanged);

    if (widget.isBackSide) {
      _consensusBuilder = OcrConsensusBuilder();
    }
    _startStream();
    unawaited(_captureController.start());
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
      final captureConsensus = widget.isBackSide
          ? _consensusBuilder?.snapshot()
          : null;
      _captureController.onCaptureDelivered(
        file: outFile,
        consensus: captureConsensus,
      );
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
    // so initState's check never re-runs — initialize the builder here.
    //
    // TODO(PR4): migrate consensus seeding to DniCameraController.onSideChanged()
    // once OcrConsensusBuilder is renamed to OcrConsensusAccumulator and the
    // controller owns the accumulator lifecycle. The widget should not hold
    // OCR consensus state directly — this is the last piece of business logic
    // left in the widget after PR3c.
    if (!old.isBackSide && widget.isBackSide) {
      _consensusBuilder ??= OcrConsensusBuilder();
      // Prime the back-side consensus with ALL text-OCR fields captured on
      // the front. Back-side MRZ overrides any of these when it locks
      // (confidence=1.0 via lockFromMrzFields). When MRZ fails or the manual
      // fallback fires, the front-side accumulation acts as a safety net so
      // documentNumber, firstName, lastName and dateOfBirth are not null.
      final seedVotes = <String, String?>{};
      if (_accumulatedFields.firstName != null) {
        seedVotes['firstName'] = _accumulatedFields.firstName;
      }
      if (_accumulatedFields.lastName != null) {
        seedVotes['lastName'] = _accumulatedFields.lastName;
      }
      if (_accumulatedFields.secondLastName != null) {
        seedVotes['secondLastName'] = _accumulatedFields.secondLastName;
      }
      if (_accumulatedFields.documentNumber != null) {
        seedVotes['documentNumber'] = _accumulatedFields.documentNumber;
      }
      if (_accumulatedFields.dateOfBirth != null) {
        seedVotes['dateOfBirth'] = _accumulatedFields.dateOfBirth;
      }
      if (_accumulatedFields.expirationDate != null) {
        seedVotes['expirationDate'] = _accumulatedFields.expirationDate;
      }
      if (_accumulatedFields.address != null) {
        seedVotes['address'] = _accumulatedFields.address;
      }
      if (seedVotes.isNotEmpty) _consensusBuilder!.recordVote(seedVotes);
      // DNI azul has MRZ on the front — seed the back-side builder with
      // any MRZ data already accumulated so snapshot() has data immediately.
      if (_accumulatedFields.hasMrzData) {
        _consensusBuilder!.lockFromMrzFields(
          documentNumber: _accumulatedFields.documentNumber,
          firstName: _accumulatedFields.firstName,
          lastName: _accumulatedFields.lastName,
          secondLastName: _accumulatedFields.secondLastName,
          dateOfBirth: _accumulatedFields.dateOfBirth,
          expirationDate: _accumulatedFields.expirationDate,
        );
      }
      _expiredHandled = false;
      _showSideIntro = true;
      _sideIntroTimer?.cancel();
      _sideIntroTimer = Timer(
        const Duration(seconds: CameraOverlayTuning.sideIntroSeconds),
        () {
          if (mounted) setState(() => _showSideIntro = false);
        },
      );
      _captureController.onSideChanged();
    }
    if (old.isBackSide && !widget.isBackSide) {
      _consensusBuilder?.dispose();
      _consensusBuilder = null;
      _consensusWindowTimer?.cancel();
      _consensusWindowTimer = null;
      _expiredHandled = false;
      _captureController.onSideChanged();
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
    _consensusBuilder?.dispose();
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
  ) => filterBlocksInHole(recognized, imageSize);

  Future<void> _processDocument(
    dynamic inputImage,
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
      theme: _theme,
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

    // Delegate expiration detection and state transitions to controller
    DateTime? expirationDate;

    if (recognized.blocks.isNotEmpty) {
      final frameFields = OcrFieldExtractor.extract(recognized);
      _accumulatedFields.merge(frameFields);

      // KYC v2: expiration gate
      if (widget.kycV2Enabled &&
          frameFields.hasMrzData &&
          !_expiredHandled) {
        final expired = _expirationFromFields(frameFields.expirationDate);
        if (expired != null) {
          _expiredHandled = true;
          expirationDate = expired;
          _stopStream();
        }
      }

      final builder = _consensusBuilder;
      if (builder != null && expirationDate == null) {
        _consensusWindowTimer ??= Timer(
          const Duration(seconds: CameraOverlayTuning.consensusWindowSeconds),
          () {},
        );

        if (frameFields.hasMrzData) {
          builder
            ..lockFromMrzFields(
              documentNumber: frameFields.documentNumber,
              firstName: frameFields.firstName,
              lastName: frameFields.lastName,
              secondLastName: frameFields.secondLastName,
              dateOfBirth:
                  frameFields.dateOfBirth ?? _accumulatedFields.dateOfBirth,
              expirationDate:
                  frameFields.expirationDate ??
                  _accumulatedFields.expirationDate,
            )
            ..recordVote({
              'documentNumber': frameFields.documentNumber,
              'firstName': frameFields.firstName,
              'lastName': frameFields.lastName,
              'secondLastName': frameFields.secondLastName,
              'dateOfBirth': frameFields.dateOfBirth,
              'expirationDate': frameFields.expirationDate,
              'address': frameFields.address,
            });
          if (builder.isMrzLocked) {
            // kycV2 fast path: once MRZ is locked, the consensus is
            // authoritative — skip the auto-capture countdown and trigger
            // capture immediately. We guard against re-triggering when the
            // controller already moved past Scanning/CountingDown.
            final captureState = _captureController.captureState.value;
            if (captureState is! DniCaptureInFlight &&
                captureState is! DniCaptureExpired &&
                captureState is! DniCaptureDone) {
              _captureController.captureManually();
            }
          }
        } else {
          builder
            ..resetMrzConsecutiveCount()
            ..recordVote({
              'documentNumber': frameFields.documentNumber,
              'firstName': frameFields.firstName,
              'lastName': frameFields.lastName,
              'secondLastName': frameFields.secondLastName,
              'dateOfBirth': frameFields.dateOfBirth,
              'expirationDate': frameFields.expirationDate,
              'address': frameFields.address,
            });
          if (builder.checkAllThresholds()) {
            final captureState = _captureController.captureState.value;
            if (captureState is! DniCaptureInFlight &&
                captureState is! DniCaptureExpired &&
                captureState is! DniCaptureDone) {
              _captureController.captureManually();
            }
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
      failingGate: result.failingGate,
      tiltDegrees: _telemetryTilt,
      rawBlockCount: _telemetryRawBlocks,
      filteredBlockCount: _telemetryLines,
    );

    _emitGateBreadcrumb(
      failingGate: result.failingGate,
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
                    final isPulsing =
                        !_isCaptureable && !widget.isLoading && !_isCapturingFromState;
                    return CustomPaint(
                      painter: MaskPainter(
                        holeWidth: widget.holeWidth,
                        holeHeight: widget.holeHeight,
                        borderColor: isPulsing
                            ? _borderColor.withValues(alpha: _pulseAnimation.value)
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
            // Flash toggle
            Positioned(
              bottom: manualModeActive
                  ? MediaQuery.of(context).padding.bottom + 56
                  : MediaQuery.of(context).padding.bottom + 24,
              right: 24,
              child: AnimatedSwitcher(
                duration: const Duration(
                  milliseconds: CameraOverlayTuning.torchSwitcherFadeMs,
                ),
                child: FlashToggle(
                  key: ValueKey<bool>(_torchOn),
                  isOn: _torchOn,
                  onToggle: _toggleTorch,
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
                        Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF69F0AE),
                          size: 52,
                        )
                      else
                        CircularProgressIndicator(color: theme.white),
                      SizedBox(height: 16),
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
              GuideTextBanner(
                text: _guideText,
                holeHeight: widget.holeHeight,
                insideHole: false,
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
                child: ManualCapturePanel(
                  isBackSide: widget.isBackSide,
                  onPressed: () => _captureController.captureManually(),
                ),
              ),
            if (userDataMatch != null && !_isCapturingFromState && !widget.isLoading)
              DataMatchIndicator(
                matches: userDataMatch,
                bottom: manualModeActive ? 208 : 80,
              ),
            if (widget.isBackSide)
              Positioned(
                top:
                    MediaQuery.sizeOf(context).height / 2 +
                    widget.holeHeight / 2 +
                    16,
                left: 24,
                right: 24,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _showSideIntro ? 1.0 : 0.0,
                    duration: const Duration(
                      milliseconds: CameraOverlayTuning.sideIntroFadeMs,
                    ),
                    child: const SideIntroRibbon(),
                  ),
                ),
              ),
            if (kDebugMode && true)
              ValueListenableBuilder<DniTelemetry>(
                valueListenable: _captureController.telemetry,
                builder: (context, telemetry, _) {
                  return Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 8,
                    child: IgnorePointer(
                      child: G1TelemetryOverlay(
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


