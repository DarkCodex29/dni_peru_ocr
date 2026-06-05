import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'breadcrumb_throttle.dart';
import 'camera_overlay_logic.dart';
import 'detector_lifecycle.dart';
import 'document_validator.dart';
import 'input_image_converter.dart';
import 'kyc_image_utils.dart';
import 'kyc_theme.dart';
import 'ocr_consensus.dart';
import 'ocr_field_extractor.dart';
import 'tilt_calculator.dart';
import 'user_verification_data.dart';


Widget _animatedSwitcherDedupeLayout(
  Widget? current,
  List<Widget> previous,
) => animatedSwitcherDedupeLayout(current, previous);

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
  String _guideText = '';
  Color _borderColor = Colors.white;
  bool _isCaptureable = false;
  DateTime? _perfectSince;
  DateTime? _lastCaptureableAt;
  double _validationProgress = 0;
  bool _capturing = false;
  bool _showFlash = false;
  bool _torchOn = false;
  bool _manualModeActive = false;
  Timer? _manualFallbackTimer;
  bool _showSideIntro = false;
  Timer? _sideIntroTimer;
  bool _isDisposed = false;
  bool? _userDataMatch;
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
  // Captured per processed document frame. Read by the debug overlay
  // (kDebugMode only) and emitted as Sentry breadcrumbs (throttled to 1 Hz)
  // to root-cause the "Endereza el documento" hang reported on JC's Infinix
  // X6837 — see Engram observation #3188.
  final BreadcrumbThrottle _gateBreadcrumbThrottle = BreadcrumbThrottle();
  double _telemetryTilt = 0; // cornerPoints-derived (production signal)
  double? _telemetryMlkitAngle; // MLKit-provided (comparison signal; iOS=null)
  int _telemetryLines = 0; // lines after _filterBlocksInHole
  int _telemetryRawBlocks = 0; // raw block count before filter
  int _telemetryRotation = 0; // sensor orientation degrees
  String _telemetryFormat = '-'; // camera ImageFormatGroup raw name
  String? _telemetryFailingGate; // null when frame is captureable
  int _telemetryPerfectSinceMs = -1; // ms since gates went green; -1 if not

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  late final AnimationController _scanController;
  late final Animation<double> _scanAnimation;
  late final AnimationController _countdownController;

  static const int _autoCaptureMs = CameraOverlayTuning.autoCaptureMs;
  static const int _gracePeriodMs = CameraOverlayTuning.gracePeriodMs;
  static const int _minStableFrames = CameraOverlayTuning.minStableFrames;
  static const int _manualFallbackMs = CameraOverlayTuning.manualFallbackMs;

  String get _loadingMessage => loadingMessage(
    isLoading: widget.isLoading,
    isBackSide: widget.isBackSide,
  );

  String get _initialGuideText =>
      initialGuideText(isFaceHole: false);

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
    _guideText = _initialGuideText;
    WidgetsBinding.instance.addObserver(this);
    if (widget.isBackSide) {
      _consensusBuilder = OcrConsensusBuilder();
    }
    _startStream();
    _startManualFallbackTimer();
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
    }
    if (old.isBackSide && !widget.isBackSide) {
      _consensusBuilder?.dispose();
      _consensusBuilder = null;
      _consensusWindowTimer?.cancel();
      _consensusWindowTimer = null;
      _expiredHandled = false;
    }

    if (old.isLoading && !widget.isLoading) {
      _capturing = false;
      _isCaptureable = false;
      _perfectSince = null;
      _lastCaptureableAt = null;
      _countdownController.reset();
      _validationProgress = 0;
      _guideText = _initialGuideText;
      _borderColor = _theme.white;
      _manualModeActive = false;
      _startStream();
      _startManualFallbackTimer();
    }
  }

  void _resetState() {
    _frameCount = 0;
    _isProcessing = false;
    _capturing = false;
    _isCaptureable = false;
    _perfectSince = null;
    _lastCaptureableAt = null;
    _countdownController.reset();
    _validationProgress = 0;
    _showFlash = false;
    _guideText = _initialGuideText;
    _borderColor = _theme.white;
    _lastBlockCount = 0;
    _stableFrames = 0;
    _tiltBadFrames = 0;
    _manualModeActive = false;
    _startManualFallbackTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _stopStream();
    } else if (state == AppLifecycleState.resumed) {
      if (!_capturing && !widget.isLoading) _startStream();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _manualFallbackTimer?.cancel();
    _sideIntroTimer?.cancel();
    _consensusWindowTimer?.cancel();
    _consensusBuilder?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _scanController.dispose();
    _countdownController.dispose();
    // Flutter's dispose() is synchronous — we cannot await here.
    // _lifecycle.safeDispose() handles the full async sequence:
    //   1. Stop the camera stream (no new frames arrive)
    //   2. Drain any in-flight _processFrame to completion
    //   3. Close ML Kit detectors (deterministic, no race condition)
    // _detectorsOpen guard inside DetectorLifecycle ensures idempotency.
    unawaited(_lifecycle.safeDispose());
    super.dispose();
  }

  void _onCameraImage(CameraImage image) {
    if (_isDisposed) return;
    _frameCount++;
    if (_frameCount % 3 != 0) return;
    if (_isProcessing || _capturing) return;
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
      // The raw CameraImage dimensions are pre-rotation, so swap them when the
      // sensor is rotated 90° or 270° to match ML Kit's coordinate system.
      final sensorOrientation = widget.controller.description.sensorOrientation;
      final isRotated = sensorOrientation == 90 || sensorOrientation == 270;
      final imageSize = Size(
        isRotated ? image.height.toDouble() : image.width.toDouble(),
        isRotated ? image.width.toDouble() : image.height.toDouble(),
      );

      // Guard: don't call processImage on a disposed (closed) detector.
      if (_isDisposed) return;

      await _processDocument(inputImage, imageSize);

      if (!_isDisposed) _checkAutoCapture();
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

    // ─── G.1 telemetry capture (diagnostic-only) ───────────────────────────
    // Both signals are computed unconditionally — the cost is negligible
    // (already iterating these blocks for validation) and Sentry/release
    // builds need the breadcrumb data even though kDebugMode is false.
    final tiltDeg = computeMedianTiltDegrees(recognized);
    final mlkitAngle = computeMlkitMedianAngleDegrees(recognized);
    _telemetryTilt = tiltDeg;
    _telemetryMlkitAngle = mlkitAngle;
    _telemetryLines = recognized.blocks.length;
    _telemetryRawBlocks = raw.blocks.length;
    _telemetryRotation = widget.controller.description.sensorOrientation;
    _telemetryFormat = widget.controller.imageFormatGroup?.name ?? '-';
    _telemetryFailingGate = result.failingGate;

    final blockDiff = (recognized.blocks.length - _lastBlockCount).abs();
    _lastBlockCount = recognized.blocks.length;
    _stableFrames = StabilityState.update(
      current: _stableFrames,
      blockDiff: blockDiff,
      isEmpty: recognized.blocks.isEmpty,
    );

    final isStable = _stableFrames >= _minStableFrames;
    final canCapture = result.isCaptureable && (dataMatch ?? true) && isStable;
    final wasCaptureable = _isCaptureable;

    if (recognized.blocks.isNotEmpty) {
      final frameFields = OcrFieldExtractor.extract(recognized);
      _accumulatedFields.merge(frameFields);

      // KYC v2: expiration gate runs on any side as soon as the
      // checksum-valid MRZ surfaces (users often show the back during
      // the "front" step). Disabled in legacy flow.
      if (widget.kycV2Enabled &&
          frameFields.hasMrzData &&
          !_expiredHandled &&
          !_capturing) {
        final expired = _expirationFromFields(frameFields.expirationDate);
        if (expired != null) {
          _expiredHandled = true;
          _perfectSince = null;
          _countdownController.reset();
          _stopStream();
          widget.onDocumentExpired?.call(expired);
          return;
        }
      }

      final builder = _consensusBuilder;
      if (builder != null) {
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
              // Supplement with accumulated data — DNI azul holograms can make
              // individual MRZ frames miss dates even when they were seen earlier.
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
          if (builder.isMrzLocked && !_capturing) {
            unawaited(_triggerCaptureWithConsensus(builder.snapshot()));
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
          if (builder.checkAllThresholds() && !_capturing) {
            unawaited(_triggerCaptureWithConsensus(builder.snapshot()));
          }
        }
      }

      final src = _accumulatedFields.hasMrzData ? 'MRZ' : 'TEXT';
      debugPrint(
        '─── OCR [$src] [${recognized.blocks.length}/${raw.blocks.length} bloques] '
        'cap=$canCapture match=$dataMatch '
        '(${_accumulatedFields.foundCount}/${_accumulatedFields.totalCount}) ───',
      );
      debugPrint(_accumulatedFields.toString());
    }

    // Gestionar _perfectSince y el controller de countdown ANTES del debounce
    // de tilt, para que frames con tilt real detengan el arco inmediatamente
    // aunque el warning visual se suprima durante los primeros 2 frames.
    if (canCapture && !wasCaptureable) {
      unawaited(HapticFeedback.lightImpact());
      _perfectSince = DateTime.now();
      unawaited(_countdownController.forward(from: 0));
    } else if (!canCapture) {
      _perfectSince = null;
      _countdownController.reset();
    }

    // Debounce "Endereza el documento": a single noisy frame with bad tilt
    // must not interrupt an otherwise steady capture. Only surface the warning
    // after 3 consecutive frames that exceed the tilt threshold.
    const enderezaMsg = 'Endereza el documento';
    if (result.message == enderezaMsg) {
      _tiltBadFrames++;
      if (_tiltBadFrames < 3) return;
    } else {
      _tiltBadFrames = 0;
    }

    setState(() {
      _guideText = result.message;
      _borderColor = result.borderColor;
      _isCaptureable = canCapture;
      _userDataMatch = dataMatch;
    });

    _telemetryPerfectSinceMs = _perfectSince == null
        ? -1
        : DateTime.now().difference(_perfectSince!).inMilliseconds;

    _emitGateBreadcrumb(
      failingGate: result.failingGate,
      stableFrames: _stableFrames,
    );
  }

  /// Throttled (≤1 Hz) Sentry breadcrumb emission for the G.1 telemetry.
  ///
  /// Safe in release: when Sentry is not initialized, `addBreadcrumb` is a
  /// no-op. Emits only when a validation gate is failing — the captureable
  /// path is silent to keep the breadcrumb stream signal-dense.
  void _emitGateBreadcrumb({
    required String? failingGate,
    required int stableFrames,
  }) {
    if (failingGate == null) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!_gateBreadcrumbThrottle.tryAcquire(nowMs)) return;

    OcrExtractedFields.logger.breadcrumb(
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

  /// Back-side capture requires at minimum the document number plus the
  /// surname or given names. Without either, the confirmation screen would
  /// render an empty form — better to keep the user on the camera.
  bool _consensusHasMinimumData(OcrConsensusResult? snap) =>
      consensusHasMinimumData(snap);

  /// Parses DD/MM/YYYY (MRZ extractor format). Returns the DateTime only
  /// when it is in the past; returns null for valid or unparseable dates.
  DateTime? _expirationFromFields(String? raw) => expirationIfPast(raw);

  void _checkAutoCapture() {
    if (_capturing || _expiredHandled || _perfectSince == null) return;
    // Blink must be confirmed before the countdown fires — blocks photo spoofing.
    if (!_isCaptureable) return;
    final elapsed = DateTime.now().difference(_perfectSince!).inMilliseconds;
    if (elapsed >= _autoCaptureMs) unawaited(_triggerCapture());
  }

  Future<void> _triggerCapture() async {
    await _triggerCaptureWithConsensus(null);
  }

  Future<void> _triggerCaptureWithConsensus(
    OcrConsensusResult? consensus,
  ) async {
    if (_capturing || _expiredHandled) return;

    // In manual mode the user explicitly overrides the quality gate.
    if (widget.isBackSide && !_manualModeActive) {
      final snap = consensus ?? _consensusBuilder?.snapshot();
      if (!_consensusHasMinimumData(snap)) {
        if (mounted) {
          setState(() {
            _guideText = 'Acerca más el reverso del DNI e intenta de nuevo';
          });
        }
        return;
      }
    }

    _capturing = true;
    _countdownController.stop();
    _manualFallbackTimer?.cancel();
    _consensusWindowTimer?.cancel();
    _manualModeActive = false;
    _stopStream();

    if (mounted) setState(() => _showFlash = true);
    await Future<void>.delayed(
      const Duration(milliseconds: CameraOverlayTuning.captureFlashMs),
    );
    if (mounted) setState(() => _showFlash = false);

    try {
      final raw = await widget.controller.takePicture();
      unawaited(HapticFeedback.heavyImpact());
      final shouldCrop =
          widget.kycV2Enabled;
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
          ? (consensus ?? _consensusBuilder?.snapshot())
          : null;
      widget.onValidCapture(outFile, captureConsensus);
    } on CameraException catch (_) {
      if (mounted) {
        setState(() {
          _capturing = false;
          _perfectSince = null;
          _showFlash = false;
        });
        _startStream();
      }
    }
  }

  Future<void> _toggleTorch() async {
    try {
      final newMode = _torchOn ? FlashMode.off : FlashMode.torch;
      await widget.controller.setFlashMode(newMode);
      if (mounted) setState(() => _torchOn = !_torchOn);
    } on CameraException catch (_) {}
  }

  void _startManualFallbackTimer() {
    _manualFallbackTimer?.cancel();
    _manualFallbackTimer = Timer(
      const Duration(milliseconds: _manualFallbackMs),
      () {
        if (mounted && !_capturing) {
          setState(() {
            _manualModeActive = true;
            _guideText = 'Toca el botón para capturar';
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final _theme = KycTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _screenSize = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(widget.controller),
            AnimatedBuilder(
              animation: Listenable.merge([
                _pulseAnimation,
                _scanAnimation,
                _countdownController,
              ]),
              builder: (context, _) {
                final isPulsing =
                    !_isCaptureable && !widget.isLoading && !_capturing;
                return CustomPaint(
                  painter: _MaskPainter(
                    holeWidth: widget.holeWidth,
                    holeHeight: widget.holeHeight,
                    borderColor: isPulsing
                        ? _borderColor.withValues(alpha: _pulseAnimation.value)
                        : _borderColor,
                    overlayColor: _theme.overlayDark,
                    countdownProgress: _countdownController.value,
                    scanProgress: _scanAnimation.value,
                  ),
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
            if (true)
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                right: 16,
                child: _FlashToggle(
                  isOn: _torchOn,
                  onToggle: _toggleTorch,
                ),
              ),
            if (widget.isLoading || _capturing)
              ColoredBox(
                color: _theme.overlayMedium,
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
                        CircularProgressIndicator(color: _theme.white),
                      SizedBox(height: 16),
                      Text(
                        _loadingMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _theme.white,
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (!_manualModeActive)
              _GuideTextBanner(
                text: _guideText,
                holeHeight: widget.holeHeight,
                insideHole: false,
              ),
            if (_showFlash)
              IgnorePointer(
                child: ColoredBox(color: _theme.white60),
              ),
            if (_manualModeActive && !_capturing && !widget.isLoading)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _ManualCapturePanel(
                  isBackSide: widget.isBackSide,
                  onPressed: () => unawaited(_triggerCapture()),
                ),
              ),
            if (_userDataMatch != null && !_capturing && !widget.isLoading)
              _DataMatchIndicator(
                matches: _userDataMatch!,
                bottom: _manualModeActive ? 208 : 80,
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
                    child: const _SideIntroRibbon(),
                  ),
                ),
              ),
            if (kDebugMode && true)
              Positioned(
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
                    stableFrames: _stableFrames,
                    failingGate: _telemetryFailingGate,
                    perfectSinceMs: _telemetryPerfectSinceMs,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ManualCapturePanel extends StatelessWidget {
  const _ManualCapturePanel({
    required this.isBackSide,
    required this.onPressed,
  });

  final bool isBackSide;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final _theme = KycTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      decoration: BoxDecoration(
        color: Color(0xCC0D0D1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isBackSide
                ? 'Encuadra el reverso del DNI y toca para capturar'
                : 'Encuadra el anverso del DNI y toca para capturar',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _theme.white70,
              fontSize: 13,
            ),
          ),
          SizedBox(height: 20),
          GestureDetector(
            onTap: onPressed,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _theme.white.withValues(alpha: 0.15),
                border: Border.all(color: _theme.white, width: 3),
              ),
              child: Center(
                child: Icon(
                  Icons.camera_alt_outlined,
                  color: _theme.white,
                  size: 32,
                ),
              ),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Capturar',
            style: TextStyle(
              color: _theme.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}

class _SideIntroRibbon extends StatelessWidget {
  const _SideIntroRibbon();

  @override
  Widget build(BuildContext context) {
    final _theme = KycTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _theme.overlayMedium,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _theme.white.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF69F0AE),
            size: 18,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Anverso listo — ahora voltea el DNI',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _theme.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Debug-only HUD that surfaces the G.1 telemetry signals on top of the
/// camera preview. Renders nothing in release builds (the entry point in
/// `DniCameraMask.build` is wrapped in `if (kDebugMode)`).
///
/// All values mirror the per-frame Sentry breadcrumb payload — so QA can
/// reproduce the bug on a debug build and read the same data on screen
/// that Sentry would receive in release.
class _G1TelemetryOverlay extends StatelessWidget {
  const _G1TelemetryOverlay({
    required this.tilt,
    required this.mlkitAngle,
    required this.lines,
    required this.rawBlocks,
    required this.rotation,
    required this.format,
    required this.stableFrames,
    required this.failingGate,
    required this.perfectSinceMs,
  });

  final double tilt;
  final double? mlkitAngle;
  final int lines;
  final int rawBlocks;
  final int rotation;
  final String format;
  final int stableFrames;
  final String? failingGate;
  final int perfectSinceMs;

  String _fmtAngle(double v) => v.toStringAsFixed(1);
  String _fmtMaybeAngle(double? v) => v == null ? '-' : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final _theme = KycTheme.of(context);
    final lineStyle = TextStyle(
      color: _theme.white,
      fontSize: 11,
      fontFamily: 'monospace',
      height: 1.25,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _theme.overlayMedium.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('tilt: ${_fmtAngle(tilt)}°', style: lineStyle),
          Text('mlkit_angle: ${_fmtMaybeAngle(mlkitAngle)}°', style: lineStyle),
          Text('lines: $lines', style: lineStyle),
          Text('blocks: $rawBlocks', style: lineStyle),
          Text('rot: $rotation', style: lineStyle),
          Text('fmt: $format', style: lineStyle),
          Text('stableFrames: $stableFrames', style: lineStyle),
          Text('failing_gate: ${failingGate ?? "-"}', style: lineStyle),
          Text('perfectSince_ms: $perfectSinceMs', style: lineStyle),
        ],
      ),
    );
  }
}

class _GuideTextBanner extends StatelessWidget {
  const _GuideTextBanner({
    required this.text,
    required this.holeHeight,
    this.insideHole = false,
  });
  final String text;
  final double holeHeight;
  final bool insideHole;

  @override
  Widget build(BuildContext context) {
    final _theme = KycTheme.of(context);
    final screenH = MediaQuery.sizeOf(context).height;
    final holeBottom = screenH / 2 + holeHeight / 2;
    final top = insideHole ? holeBottom - 52 : holeBottom + 16;
    return Positioned(
      top: top,
      left: 32,
      right: 32,
      child: AnimatedSwitcher(
        duration: const Duration(
          milliseconds: CameraOverlayTuning.switcherFadeMs,
        ),
        layoutBuilder: _animatedSwitcherDedupeLayout,
        child: Container(
          key: ValueKey(text),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: _theme.overlayMedium,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _theme.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Mask painter ─────────────────────────────────────────────────────────────

class _MaskPainter extends CustomPainter {
  const _MaskPainter({
    required this.holeWidth,
    required this.holeHeight,
    required this.borderColor,
    required this.overlayColor,
    required this.countdownProgress,
    this.scanProgress = 0,
  });

  final double holeWidth;
  final double holeHeight;
  final Color borderColor;
  final Color overlayColor;
  final double countdownProgress;
  final double scanProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final fullPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final holePath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, cy),
            width: holeWidth,
            height: holeHeight,
          ),
          const Radius.circular(8),
        ),
      );

    canvas.drawPath(
      Path.combine(PathOperation.difference, fullPath, holePath),
      Paint()..color = overlayColor,
    );

    _drawCornerMarkers(canvas, cx, cy);
    _drawScanLine(canvas, cx, cy);
    if (countdownProgress > 0) _drawRectCountdown(canvas, cx, cy);
  }
  /// Horizontal scan line sweeping vertically through the document hole.
  /// Gives real-time feedback that the system is actively reading the document.
  void _drawScanLine(Canvas canvas, double cx, double cy) {
    final l = cx - holeWidth / 2;
    final t = cy - holeHeight / 2;
    final r = cx + holeWidth / 2;
    final b = cy + holeHeight / 2;
    final scanY = t + (b - t) * scanProgress;
    final gradientRect = Rect.fromLTRB(l, scanY - 6, r, scanY + 6);

    canvas
      ..save()
      ..clipRect(Rect.fromLTRB(l, t, r, b))
      // Glow layer
      ..drawLine(
        Offset(l, scanY),
        Offset(r, scanY),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0x00FFFFFF), Color(0x1EFFFFFF), Color(0x00FFFFFF)],
          ).createShader(gradientRect)
          ..strokeWidth = 12
          ..style = PaintingStyle.stroke,
      )
      // Core line
      ..drawLine(
        Offset(l, scanY),
        Offset(r, scanY),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0x00FFFFFF), Color(0x8CFFFFFF), Color(0x00FFFFFF)],
          ).createShader(gradientRect)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      )
      ..restore();
  }

  /// Draws a clockwise-filling border around the document rect as the
  /// auto-capture countdown progresses (0 → 1). Starts from the top-left
  /// corner so the animation feels natural and directional.
  void _drawRectCountdown(Canvas canvas, double cx, double cy) {
    final l = cx - holeWidth / 2;
    final t = cy - holeHeight / 2;
    final r = cx + holeWidth / 2;
    final b = cy + holeHeight / 2;

    final perimeter = 2 * (holeWidth + holeHeight);
    var remaining = perimeter * countdownProgress;

    final path = Path()..moveTo(l, t);

    final seg1 = math.min(remaining, holeWidth);
    path.lineTo(l + seg1, t);
    remaining -= seg1;

    if (remaining > 0) {
      final seg2 = math.min(remaining, holeHeight);
      path.lineTo(r, t + seg2);
      remaining -= seg2;
    }
    if (remaining > 0) {
      final seg3 = math.min(remaining, holeWidth);
      path.lineTo(r - seg3, b);
      remaining -= seg3;
    }
    if (remaining > 0) {
      final seg4 = math.min(remaining, holeHeight);
      path.lineTo(l, b - seg4);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..strokeWidth = 3.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }
  void _drawCornerMarkers(Canvas canvas, double cx, double cy) {
    const markerLen = 24.0;
    const strokeW = 4.0;
    const radius = 8.0;

    final paint = Paint()
      ..color = borderColor
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final l = cx - holeWidth / 2;
    final t = cy - holeHeight / 2;
    final r = cx + holeWidth / 2;
    final b = cy + holeHeight / 2;

    canvas
      ..drawLine(
        Offset(l + radius, t),
        Offset(l + radius + markerLen, t),
        paint,
      )
      ..drawLine(
        Offset(l, t + radius),
        Offset(l, t + radius + markerLen),
        paint,
      )
      ..drawArc(
        Rect.fromCircle(center: Offset(l + radius, t + radius), radius: radius),
        3.14159,
        0.5 * 3.14159,
        false,
        paint,
      )
      ..drawLine(
        Offset(r - radius, t),
        Offset(r - radius - markerLen, t),
        paint,
      )
      ..drawLine(
        Offset(r, t + radius),
        Offset(r, t + radius + markerLen),
        paint,
      )
      ..drawArc(
        Rect.fromCircle(center: Offset(r - radius, t + radius), radius: radius),
        1.5 * 3.14159,
        0.5 * 3.14159,
        false,
        paint,
      )
      ..drawLine(
        Offset(l + radius, b),
        Offset(l + radius + markerLen, b),
        paint,
      )
      ..drawLine(
        Offset(l, b - radius),
        Offset(l, b - radius - markerLen),
        paint,
      )
      ..drawArc(
        Rect.fromCircle(center: Offset(l + radius, b - radius), radius: radius),
        0.5 * 3.14159,
        0.5 * 3.14159,
        false,
        paint,
      )
      ..drawLine(
        Offset(r - radius, b),
        Offset(r - radius - markerLen, b),
        paint,
      )
      ..drawLine(
        Offset(r, b - radius),
        Offset(r, b - radius - markerLen),
        paint,
      )
      ..drawArc(
        Rect.fromCircle(center: Offset(r - radius, b - radius), radius: radius),
        0,
        0.5 * 3.14159,
        false,
        paint,
      );
  }
  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    const dash = 10.0;
    const gap = 6.0;
    for (final metric in path.computeMetrics()) {
      double d = 0;
      bool draw = true;
      while (d < metric.length) {
        final len = draw ? dash : gap;
        if (draw) canvas.drawPath(metric.extractPath(d, d + len), paint);
        d += len;
        draw = !draw;
      }
    }
  }

  @override
  bool shouldRepaint(_MaskPainter old) =>
      old.holeWidth != holeWidth ||
      old.holeHeight != holeHeight ||
      old.borderColor != borderColor ||
      old.overlayColor != overlayColor ||
      old.countdownProgress != countdownProgress ||
      old.scanProgress != scanProgress;
}

class _DataMatchIndicator extends StatelessWidget {
  const _DataMatchIndicator({required this.matches, this.bottom = 80});
  final bool matches;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final _theme = KycTheme.of(context);
    return Positioned(
      bottom: bottom,
      left: 24,
      right: 24,
      child: AnimatedSwitcher(
        duration: const Duration(
          milliseconds: CameraOverlayTuning.torchSwitcherFadeMs,
        ),
        layoutBuilder: _animatedSwitcherDedupeLayout,
        child: Container(
          key: ValueKey(matches),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: matches
                ? _theme.success.withValues(alpha: 0.85)
                : _theme.warningIcon.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                matches ? Icons.verified_rounded : Icons.info_outline_rounded,
                color: _theme.white,
                size: 16,
              ),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  matches
                      ? 'DNI coincide con tu perfil'
                      : 'DNI no coincide — verifica el documento',
                  style: TextStyle(
                    color: _theme.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
  /// Unstable → decrement by 1 (minimum 0) — single-frame forgiveness.
  /// Returns the next value of the stability counter.
  ///
  /// A frame is "stable" when [blockDiff] ≤ 2 AND [isEmpty] is false.
  /// Stable → increment by 1.
  /// Unstable → decrement by 1, floored at 0 (REQ-STAB-1 forgiveness).
  /// A single noisy frame loses only 1 stable point instead of resetting
  /// to zero — two consecutive unstable frames still reach 0.
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

class _FlashToggle extends StatelessWidget {
  const _FlashToggle({required this.isOn, required this.onToggle});
  final bool isOn;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final _theme = KycTheme.of(context);
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isOn
              ? _theme.white.withValues(alpha: 0.3)
              : _theme.overlayMedium,
          shape: BoxShape.circle,
        ),
        child: Icon(
          isOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
          color: isOn ? _theme.warningIcon : _theme.white70,
          size: 22,
        ),
      ),
    );
  }
}
