import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

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
import '../../lookup/models/dni_data.dart';
import '../../lookup/models/dni_lookup_result.dart';
import '../../lookup/services/dni_lookup_service.dart';
import '../../infrastructure/sensors_motion_gate.dart';
import '../controllers/dni_camera_controller.dart';
import '../document_validator.dart';
import '../image_quality_gate.dart';
import '../lighting_gate.dart';
import '../orchestrators/dni_capture_orchestrator.dart';
import '../orchestrators/dni_capture_state.dart';
import '../theme/kyc_theme.dart';

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
    this.idleFramesBeforeCapture = 18,
    this.holeWidth = 300,
    this.holeHeight = 220,
    this.captureMode = DniCaptureMode.auto,
    this.orchestrator,
    this.motionGate,
    this.imageQualityGate,
    this.autoCaptureMs = 1500,
    this.gracePeriodMs = 600,
    this.minStableFrames = 3,
    this.manualFallbackMs = 30000,
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

  final int idleFramesBeforeCapture;
  final double holeWidth;
  final double holeHeight;

  final DniCaptureMode captureMode;

  final DniCaptureOrchestrator? orchestrator;

  final MotionStillnessGate? motionGate;

  final ImageQualityGate? imageQualityGate;

  final int autoCaptureMs;

  final int gracePeriodMs;

  final int minStableFrames;

  final int manualFallbackMs;

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

  bool _processing = false;
  bool _disposed = false;
  bool _capturing = false;
  bool _lightingValid = true;
  bool _analyzingLighting = false;
  int _lastLightingMs = 0;

  static const int _lightingIntervalMs = 350;
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
    _stateMachine = widget.stateMachine ??
        HuntStateMachine(
          idleFramesThreshold: widget.idleFramesBeforeCapture,
          minFieldsForFastAdvance:
              (selectedCount * 0.66).round().clamp(2, selectedCount),
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
    _cameraController = DniCameraController(
      orchestrator: _orchestrator,
      isBackSide: widget.isBackSide ?? false,
      onValidCapture: (_, __) {},
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
    _maybeAnalyzeLighting(image);
    if (_processing) return;
    _processing = true;
    unawaited(
      _lifecycle.trackInflight(() => _processImage(image)).whenComplete(() {
        _processing = false;
      }),
    );
  }

  void _maybeAnalyzeLighting(CameraImage image) {
    if (_analyzingLighting) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastLightingMs < _lightingIntervalMs) return;
    _lastLightingMs = nowMs;
    final request = _LightingRequest(
      luminancePlane: image.planes.first.bytes,
      bytesPerRow: image.planes.first.bytesPerRow,
      width: image.width,
      height: image.height,
    );
    _analyzingLighting = true;
    unawaited(
      Isolate.run(() => _analyzeLighting(request)).then((result) {
        if (_disposed) return;
        _lightingValid = result.isValid;
      }).catchError((_) {
        if (_disposed) return;
        _lightingValid = true;
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
      DniLogger.debug('DniScanner', 'frame skipped — empty OCR');
      return;
    }

    DniLogger.info(
      'DniScanner',
      'raw OCR (${text.length} chars, ${recognized.blocks.length} blocks):\n$text',
    );

    final DocumentSide detectedSide = switch (widget.isBackSide) {
      null => const DocumentSideDetector().detect(text),
      true => DocumentSide.back,
      false => DocumentSide.front,
    };
    final addedNew = _hunter.process(text);
    final snapshot = _hunter.snapshot;
    final filled = _countFilled(snapshot.fields);
    final signal = _stateMachine.recordFrame(
      detectedSide: detectedSide,
      addedNewField: addedNew,
      filledFields: filled,
    );

    final total = widget.fields?.length ?? 19;
    DniLogger.info(
      'DniScanner',
      'side=$detectedSide addedNew=$addedNew phase=${_stateMachine.phase} '
          'signal=$signal filled=$filled/$total',
    );

    if (mounted &&
        (_stateMachine.phase != _lastPhaseRendered || addedNew)) {
      setState(() => _lastPhaseRendered = _stateMachine.phase);
    }

    switch (signal) {
      case HuntSignal.frontCaptureReady:
      case HuntSignal.backCaptureReady:
        if (widget.captureMode == DniCaptureMode.manual) {
          _markCaptureReady();
        } else {
          _onCaptureReady(signal);
        }
      case HuntSignal.frontDetected:
      case HuntSignal.backDetected:
      case HuntSignal.none:
        break;
    }
  }

  void _onCaptureReady(HuntSignal signal) {
    if (_capturing || _disposed) return;
    if (_captureState is DniCaptureInFlight ||
        _captureState is DniCaptureDone) {
      return;
    }
    _countdownAnchor = DateTime.now();
    _countdownElapsedMs = 0;
    _advanceCapture();
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
      unawaited(_fireCapture(signal));
    }
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
      validation: const DocumentValidationResult.captureable(),
      stableFrames: widget.minStableFrames,
      userDataMatch: null,
      now: now,
      imuStill: _motionGate.isStill,
      lightingValid: _lightingValid,
    );
    if (!identical(next, _captureState)) {
      _captureState = next;
    }
  }

  @visibleForTesting
  void debugFeedCaptureReady(HuntSignal signal) => _onCaptureReady(signal);

  @visibleForTesting
  DniCaptureState get debugCaptureState => _captureState;

  @visibleForTesting
  void debugSetLightingValid(bool value) => _lightingValid = value;

  @visibleForTesting
  bool get debugManualModeActive => _manualModeActive;

  @visibleForTesting
  void debugResetToScanning() => _resetCaptureToScanning();

  @visibleForTesting
  void debugTriggerSideToggle() => _cameraController.onSideChanged(
        isBackSide: !_cameraController.isBackSide,
      );

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
        widget.onSideCaptured?.call(
          DniSideScanResult(
            photo: cropped,
            isBackSide: false,
            hunt: _hunter.snapshot,
            reniecData: _reniecData,
          ),
        );
        return;
      }
      _stateMachine.advanceToWaitingBack();
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
        widget.onDniReady?.call(result.data);
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
        widget.onSideCaptured?.call(
          DniSideScanResult(
            photo: cropped,
            isBackSide: true,
            hunt: _hunter.snapshot,
            reniecData: _reniecData,
          ),
        );
        return;
      }
      if (_frontPhoto != null) {
        final finalSnapshot = _hunter.snapshot;
        widget.onScanComplete?.call(
          DniScanResult(
            frontPhoto: _frontPhoto!,
            backPhoto: cropped,
            hunt: finalSnapshot,
            reniecData: _reniecData,
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

  static const List<String> _waitingFrontHints = [
    'Coloque el frente del DNI dentro del marco',
    'Verifique que los nombres y las fechas sean visibles',
    'Use buena iluminación y evite reflejos',
  ];
  static const List<String> _extractingFrontHints = [
    'Mantenga el documento quieto',
    'Acerque el documento si los datos pequeños no se ven',
    'No cubra la zona inferior con los dedos',
  ];
  static const List<String> _waitingBackHints = [
    'Voltee el documento',
    'Centre la dirección y los datos del reverso',
    'La cuadrícula de sufragio debe verse completa',
  ];
  static const List<String> _extractingBackHints = [
    'Mantenga el documento quieto',
    'Muestre el grupo de votación y la donación',
    'Si demora, acerque un poco más el documento',
  ];

  String _sideHint() {
    final list = switch (_stateMachine.phase) {
      HuntPhase.waitingFront => _waitingFrontHints,
      HuntPhase.extractingFront => _extractingFrontHints,
      HuntPhase.waitingBack => _waitingBackHints,
      HuntPhase.extractingBack => _extractingBackHints,
      HuntPhase.done => const ['Procesando…'],
    };
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
                      _manualModeActive
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
                visible: _stateMachine.phase == HuntPhase.waitingBack,
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

class _LightingRequest {
  const _LightingRequest({
    required this.luminancePlane,
    required this.bytesPerRow,
    required this.width,
    required this.height,
  });

  final List<int> luminancePlane;
  final int bytesPerRow;
  final int width;
  final int height;
}

LightingResult _analyzeLighting(_LightingRequest request) {
  return LightingGate.evaluate(_downscaleLuminance(request));
}

List<int> _downscaleLuminance(_LightingRequest request) {
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
    _analyzeLighting(
      _LightingRequest(
        luminancePlane: luminancePlane,
        bytesPerRow: bytesPerRow,
        width: width,
        height: height,
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
  const _FlipDocumentBanner({required this.visible});

  final bool visible;

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
                  const Flexible(
                    child: Text(
                      'Voltee el documento',
                      textAlign: TextAlign.center,
                      style: TextStyle(
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
    final frontProgress = isFrontDone
        ? 1.0
        : (frontFilled / effectiveFrontTotal).clamp(0.0, 1.0);
    final backProgress = isBackDone
        ? 1.0
        : (backFilled / effectiveBackTotal).clamp(0.0, 1.0);

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


