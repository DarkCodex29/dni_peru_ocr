import 'package:camera/camera.dart';
import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter/material.dart';

import '../widgets/loading_overlay.dart';
import 'error_screen.dart';
import 'result_screen.dart';

/// Capture flow that orchestrates front-side then back-side scanning.
///
/// The screen walks the user through a small state machine:
/// `initializing → frontCapturing → frontComplete → backCapturing → backComplete`.
/// Front-side extraction seeds the back-side accumulator so the back capture
/// reaches higher consensus confidence — this is the integration pattern
/// consumers miss most often.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

enum _ScanStep {
  initializing,
  frontCapturing,
  frontComplete,
  backCapturing,
  backComplete,
}

class _ScanScreenState extends State<ScanScreen> {
  _ScanStep _step = _ScanStep.initializing;
  CameraController? _controller;

  /// Accumulated OCR fields from the front-side scan.
  ///
  /// Populated progressively via [DniCameraMask.onFrontSideOcrUpdated] and
  /// injected into the back-side widget as [DniCameraMask.frontSideFields].
  /// This is the state-holder injection pattern: the host persists OCR memory
  /// across the widget-tree swap so the back-side accumulator starts warm
  /// instead of empty.
  OcrExtractedFields? _frontFields;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  // ─── Camera lifecycle ───────────────────────────────────────────────────────

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _step = _ScanStep.frontCapturing;
      });
    } catch (error) {
      if (!mounted) return;
      await _goToError(ExampleErrorType.initialization);
    }
  }

  // ─── Navigation helpers ─────────────────────────────────────────────────────

  Future<void> _goToError(ExampleErrorType type) async {
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => ErrorScreen(type: type)),
    );
  }

  // ─── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Show a back button only when capture is in progress so the user can
        // cancel. During initializing we hide it to prevent a half-initialized
        // camera from being left running.
        leading: _step != _ScanStep.initializing
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => _goToError(ExampleErrorType.cancelled),
              )
            : null,
        title: Text(_appBarTitle()),
      ),
      body: _buildBody(),
    );
  }

  String _appBarTitle() {
    switch (_step) {
      case _ScanStep.initializing:
        return 'Starting camera';
      case _ScanStep.frontCapturing:
      case _ScanStep.frontComplete:
        return 'Scan front side';
      case _ScanStep.backCapturing:
      case _ScanStep.backComplete:
        return 'Scan back side';
    }
  }

  Widget _buildBody() {
    switch (_step) {
      case _ScanStep.initializing:
        return const LoadingOverlay(message: 'Preparing camera...');
      case _ScanStep.frontCapturing:
      case _ScanStep.frontComplete:
        return _buildFront();
      case _ScanStep.backCapturing:
      case _ScanStep.backComplete:
        return _buildBack();
    }
  }

  // ─── Front-side capture ────────────────────────────────────────────────────

  Widget _buildFront() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const LoadingOverlay(message: 'Preparing camera...');
    }
    // NOTE: DniCameraMask.onDocumentExpired fires with a DateTime argument
    // (not VoidCallback). We ignore the date value and route to ErrorScreen.
    return DniCameraMask(
      controller: controller,
      isBackSide: false,
      onValidCapture: (file, consensus) {
        // consensus is always null for the front side — the library only
        // builds a consensus snapshot during back-side capture. Fields are
        // accumulated progressively via onFrontSideOcrUpdated below.
        if (!mounted) return;
        setState(() {
          _step = _ScanStep.backCapturing;
        });
      },
      // Accumulate front-side OCR fields progressively so they are ready
      // to seed the back-side accumulator when the step transitions.
      onFrontSideOcrUpdated: (fields) {
        _frontFields = fields;
      },
      onDocumentExpired: (_) => _goToError(ExampleErrorType.expired),
    );
  }

  // ─── Back-side capture ─────────────────────────────────────────────────────

  Widget _buildBack() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const LoadingOverlay(message: 'Preparing camera...');
    }

    // The library's consensus accumulator can be SEEDED with fields from the
    // front-side capture before mounting the back-side camera. This dramatically
    // improves back-side OCR confidence because MRZ field hypotheses propagate
    // forward.
    //
    // Without seeding, the back-side reads from scratch and may produce
    // inferior consensus — this is the integration step consumers miss most.
    return DniCameraMask(
      controller: controller,
      isBackSide: true,
      frontSideFields: _frontFields, // <-- the seeding pattern
      onValidCapture: (file, consensus) {
        if (!mounted) return;
        setState(() {
          _step = _ScanStep.backComplete;
        });
        if (consensus == null) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          return;
        }
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => ResultScreen(result: consensus),
          ),
        );
      },
      onDocumentExpired: (_) => _goToError(ExampleErrorType.expired),
    );
  }
}
