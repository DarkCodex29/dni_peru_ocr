import 'dart:async';

import 'package:flutter/foundation.dart';

import '../document_validator.dart';
import '../orchestrators/dni_capture_orchestrator.dart';
import '../orchestrators/dni_capture_state.dart';
import '../../data/ocr_consensus.dart';
import '../../data/ocr_field_extractor.dart';
import '../../domain/interfaces/ocr_logger.dart';

/// Diagnostic telemetry emitted each time a camera frame is processed.
///
/// Exposed via [DniCameraController.telemetry] for the debug overlay and
/// Sentry breadcrumbs. All fields are diagnostic-only and safe in release.
///
/// Value equality is implemented so that [ValueNotifier] consumers (e.g. the
/// debug overlay widget in PR3c) do not rebuild when two consecutive frames
/// emit identical telemetry.
@immutable
class DniTelemetry {
  const DniTelemetry({
    required this.stableFrames,
    required this.failingGate,
    this.tiltDegrees = 0.0,
    this.rawBlockCount = 0,
    this.filteredBlockCount = 0,
  });

  /// Consecutive stable-block frames observed so far.
  final int stableFrames;

  /// Name of the gate that rejected the last frame, or `null` when captureable.
  final String? failingGate;

  /// Median tilt in degrees derived from corner points (production signal).
  final double tiltDegrees;

  /// Raw OCR block count before hole filter.
  final int rawBlockCount;

  /// OCR block count after hole filter.
  final int filteredBlockCount;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DniTelemetry &&
        other.stableFrames == stableFrames &&
        other.failingGate == failingGate &&
        other.tiltDegrees == tiltDegrees &&
        other.rawBlockCount == rawBlockCount &&
        other.filteredBlockCount == filteredBlockCount;
  }

  @override
  int get hashCode => Object.hash(
        stableFrames,
        failingGate,
        tiltDegrees,
        rawBlockCount,
        filteredBlockCount,
      );
}

/// Pure Dart lifecycle controller for the DNI camera capture flow.
///
/// Owns:
/// - Manual-fallback timer (arms on [start], disarms on dispose / side toggle)
/// - State transitions via [DniCaptureOrchestrator]
/// - Document-expiration detection
///
/// Does NOT own the underlying `CameraController` — the host widget creates
/// and disposes it. [DniCameraController.dispose] only tears down its own
/// resources (timers, ValueNotifiers).
///
/// ### State exposure
/// ```dart
/// ValueListenable<DniCaptureState> get captureState
/// ValueListenable<DniTelemetry>   get telemetry
/// ```
///
/// ### Dispose ordering (per design #4641 Ch.3)
/// 1. Flip [_isDisposed] — blocks all new frame/timer callbacks
/// 2. Cancel timers
/// 3. Transition state to [DniCaptureDone]
/// 4. Dispose [ValueNotifier]s
///
/// ### Frame processing
/// The widget calls [processFrame] on every processed camera frame, passing
/// the already-computed [DocumentValidationResult] and ancillary data. The
/// controller delegates to the [DniCaptureOrchestrator] for state transitions
/// and notifies the widget via [captureState] to trigger the actual camera
/// shutter when [DniCaptureInFlight] is reached.
///
/// ### Test seams
/// [processFrame] IS the test seam — tests call it directly with a
/// `DocumentValidationResult.forTest(isCaptureable: ...)` value, so no device
/// or ML Kit dependency is needed in unit tests.
class DniCameraController {
  DniCameraController({
    required DniCaptureOrchestrator orchestrator,
    required bool isBackSide,
    required void Function(dynamic file, dynamic consensus) onValidCapture,
    void Function(DateTime expirationDate)? onDocumentExpired,
    OcrLogger logger = const NoOpOcrLogger(),
  })  : _orchestrator = orchestrator,
        _isBackSide = isBackSide,
        _onValidCapture = onValidCapture,
        _onDocumentExpired = onDocumentExpired,
        _logger = logger,
        _captureStateNotifier = ValueNotifier(
          const DniCaptureScanning(
            guideText: '',
            failingGate: null,
            validationProgress: 0,
            stableFrames: 0,
            userDataMatch: null,
            manualModeActive: false,
          ),
        ),
        _telemetryNotifier = ValueNotifier(
          const DniTelemetry(stableFrames: 0, failingGate: null),
        );

  // ── Dependencies ────────────────────────────────────────────────────────

  final DniCaptureOrchestrator _orchestrator;

  /// Logger for observability breadcrumbs. Defaults to no-op.
  final OcrLogger _logger;

  /// Emits a breadcrumb through the injected logger.
  ///
  /// Widget-level callers (e.g. [DniCameraMask]) use this to route
  /// telemetry breadcrumbs through the same logger as the controller,
  /// avoiding any need for a direct logger reference in the widget tree.
  void emitBreadcrumb(
    String category,
    String message, {
    Map<String, Object?>? data,
  }) {
    _logger.breadcrumb(category, message, data: data);
  }

  /// Whether this controller instance currently represents the back side
  /// of the document.
  ///
  /// Used by [onCaptureDelivered] to decide whether the consensus snapshot
  /// is meaningful (back side) or must be scrubbed (front side, where the
  /// consensus pipeline is not active).
  ///
  /// **Mutable by design.** Flutter may reuse a [State] instance across a
  /// host's widget rebuild when the widget tree shape is preserved (e.g.
  /// the host swaps `isBackSide: false` → `isBackSide: true` on the same
  /// `DniCameraMask` slot). In that case `initState` does NOT re-run, so
  /// the controller's side flag must be updateable at runtime. The
  /// authoritative update path is [onSideChanged], which synchronises this
  /// flag with the caller's intent before touching the accumulator.
  bool _isBackSide;

  /// Fired when a capture is delivered to the host.
  ///
  /// Called from [onCaptureDelivered] — the widget calls [onCaptureDelivered]
  /// after it takes the photo and obtains the file path so the controller never
  /// holds a reference to the real CameraController.
  final void Function(dynamic file, dynamic consensus) _onValidCapture;

  final void Function(DateTime expirationDate)? _onDocumentExpired;

  // ── State ────────────────────────────────────────────────────────────────

  final ValueNotifier<DniCaptureState> _captureStateNotifier;
  final ValueNotifier<DniTelemetry> _telemetryNotifier;

  bool _isDisposed = false;
  bool _expiredHandled = false;
  Timer? _manualFallbackTimer;

  // ── Consensus accumulator (back-side only) ────────────────────────────────
  OcrConsensusAccumulator? _accumulator;

  // ── Public API ───────────────────────────────────────────────────────────

  /// Observable capture state — single source of truth for the widget.
  ValueListenable<DniCaptureState> get captureState => _captureStateNotifier;

  /// Observable telemetry — diagnostic overlay and Sentry breadcrumbs.
  ValueListenable<DniTelemetry> get telemetry => _telemetryNotifier;

  /// Whether this controller instance is managing the back side.
  bool get isBackSide => _isBackSide;

  /// Starts the manual-fallback timer.
  ///
  /// Call after the camera stream is running. In production the widget calls
  /// this after `startImageStream` succeeds.
  Future<void> start() async {
    if (_isDisposed) return;
    _startManualFallbackTimer();
  }

  /// Stops any in-progress frame work. Does NOT dispose the controller.
  void stop() {
    _manualFallbackTimer?.cancel();
  }

  /// Triggers a manual capture.
  ///
  /// No-op if the state is already terminal (InFlight, Expired, Done).
  void captureManually() {
    if (_isDisposed) return;
    final current = _captureStateNotifier.value;
    if (current is DniCaptureInFlight ||
        current is DniCaptureExpired ||
        current is DniCaptureDone) {
      return;
    }
    // Transition to InFlight — the widget observes this and fires the shutter.
    _updateState(const DniCaptureInFlight(showFlash: true));
  }

  /// Called when the user toggles between front/back side.
  ///
  /// Resets countdown, manual mode, and timers; re-arms the fallback timer.
  ///
  /// When transitioning to the back side ([isBackSide] = true), pass the
  /// [frontSideFields] accumulated on the front so the new accumulator is
  /// seeded immediately. Omit both parameters when calling for a generic reset.
  ///
  /// Widget callers should use this instead of managing the accumulator directly.
  void onSideChanged({
    bool isBackSide = false,
    OcrExtractedFields? frontSideFields,
  }) {
    if (_isDisposed) return;
    _manualFallbackTimer?.cancel();
    _expiredHandled = false;

    // Authoritative side-flag update path. Synchronises the controller
    // with the caller's intent before mutating the accumulator so that
    // [onCaptureDelivered] decisions stay consistent for any frame
    // processed after this call.
    _isBackSide = isBackSide;

    // Tear down previous accumulator regardless of direction.
    _accumulator?.dispose();
    _accumulator = null;

    if (isBackSide) {
      _accumulator = OcrConsensusAccumulator();
      // Seed with front-side fields when available.
      final seed = frontSideFields;
      if (seed != null) {
        final seedVotes = <String, String?>{};
        if (seed.firstName != null) seedVotes['firstName'] = seed.firstName;
        if (seed.lastName != null) seedVotes['lastName'] = seed.lastName;
        if (seed.secondLastName != null)
          seedVotes['secondLastName'] = seed.secondLastName;
        if (seed.documentNumber != null)
          seedVotes['documentNumber'] = seed.documentNumber;
        if (seed.dateOfBirth != null)
          seedVotes['dateOfBirth'] = seed.dateOfBirth;
        if (seed.expirationDate != null)
          seedVotes['expirationDate'] = seed.expirationDate;
        if (seed.address != null) seedVotes['address'] = seed.address;
        if (seedVotes.isNotEmpty) _accumulator!.recordVote(seedVotes);
        // DNI azul: seed MRZ fast-lock from front-side MRZ data.
        if (seed.hasMrzData) {
          _accumulator!.lockFromMrzFields(
            documentNumber: seed.documentNumber,
            firstName: seed.firstName,
            lastName: seed.lastName,
            secondLastName: seed.secondLastName,
            dateOfBirth: seed.dateOfBirth,
            expirationDate: seed.expirationDate,
          );
        }
      }
    }

    _updateState(_orchestrator.onSideToggle(_captureStateNotifier.value));
    _startManualFallbackTimer();
  }

  /// Records a processed OCR frame result in the active consensus accumulator.
  ///
  /// No-op when the accumulator is not initialized (front side or already disposed).
  /// Returns `true` when the accumulator has reached consensus (MRZ locked or
  /// all thresholds met), which the widget uses to trigger capture.
  bool recordOcrFrame(OcrExtractedFields frameFields) {
    final acc = _accumulator;
    if (acc == null) return false;

    if (frameFields.hasMrzData) {
      acc
        ..lockFromMrzFields(
          documentNumber: frameFields.documentNumber,
          firstName: frameFields.firstName,
          lastName: frameFields.lastName,
          secondLastName: frameFields.secondLastName,
          dateOfBirth: frameFields.dateOfBirth,
          expirationDate: frameFields.expirationDate,
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
      return acc.isMrzLocked;
    } else {
      acc
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
      return acc.checkAllThresholds();
    }
  }

  /// Emits the current consensus snapshot.
  ///
  /// Returns `null` when no accumulator is active (front side).
  OcrConsensusResult? snapshotConsensus() => _accumulator?.snapshot();

  /// Processes a single camera frame.
  ///
  /// The caller (widget or test) provides the already-computed
  /// [DocumentValidationResult] and ancillary frame data. The controller
  /// delegates to the [DniCaptureOrchestrator] for state transitions, updates
  /// [telemetry], and fires the [onDocumentExpired] callback when appropriate.
  ///
  /// **This is the primary test seam** — tests call this directly with
  /// `DocumentValidationResult.forTest(isCaptureable: ...)` to drive state
  /// transitions without a real camera or ML Kit device.
  ///
  /// Parameters:
  /// - [validation] — quality-gate result for this frame.
  /// - [stableFrames] — consecutive stable-block frames observed so far.
  /// - [userDataMatch] — OCR/user-data match (`null` if no data to match).
  /// - [expirationDate] — if non-null AND in the past, fires [onDocumentExpired].
  /// - [failingGate] — string code of the failing gate for telemetry.
  /// - [tiltDegrees] — computed tilt for telemetry.
  /// - [rawBlockCount] — raw block count for telemetry.
  /// - [filteredBlockCount] — filtered block count for telemetry.
  void processFrame({
    required DocumentValidationResult validation,
    required int stableFrames,
    required bool? userDataMatch,
    DateTime? expirationDate,
    String? failingGate,
    double tiltDegrees = 0.0,
    int rawBlockCount = 0,
    int filteredBlockCount = 0,
  }) {
    if (_isDisposed) return;

    // Expiration gate — fires once per session.
    if (expirationDate != null && !_expiredHandled) {
      if (expirationDate.isBefore(DateTime.now())) {
        _expiredHandled = true;
        _updateState(DniCaptureExpired(expirationDate));
        _onDocumentExpired?.call(expirationDate);
        return;
      }
    }

    // Delegate to orchestrator for the next state.
    final next = _orchestrator.onFrame(
      current: _captureStateNotifier.value,
      validation: validation,
      stableFrames: stableFrames,
      userDataMatch: userDataMatch,
      now: DateTime.now(),
    );
    _updateState(next);

    // Update diagnostic telemetry.
    _telemetryNotifier.value = DniTelemetry(
      stableFrames: stableFrames,
      failingGate: failingGate,
      tiltDegrees: tiltDegrees,
      rawBlockCount: rawBlockCount,
      filteredBlockCount: filteredBlockCount,
    );
  }

  /// Notifies the controller that the widget has completed a capture.
  ///
  /// Called by the widget after `CameraController.takePicture()` completes
  /// and the file is ready. Fires [onValidCapture] with the file and consensus.
  ///
  /// The [consensus] argument is the back-side [OcrConsensusResult] snapshot,
  /// or `null` on front-side captures. This mirrors the [_isBackSide] semantics.
  void onCaptureDelivered({
    required dynamic file,
    dynamic consensus,
  }) {
    if (_isDisposed) return;
    // On front-side captures, consensus is always null — _isBackSide determines
    // whether the host passed meaningful consensus data.
    _onValidCapture(file, _isBackSide ? consensus : null);
    _updateState(const DniCaptureDone());
  }

  /// Disposes the controller. Idempotent.
  ///
  /// Dispose ordering (per design #4641 Ch.3):
  /// 1. Flip [_isDisposed] — blocks all new frame/timer callbacks
  /// 2. Cancel timers
  /// 3. Transition state to [DniCaptureDone]
  /// 4. Dispose consensus accumulator (if any)
  /// 5. Dispose [ValueNotifier]s
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _manualFallbackTimer?.cancel();
    _captureStateNotifier.value = const DniCaptureDone();
    _accumulator?.dispose();
    _accumulator = null;
    _captureStateNotifier.dispose();
    _telemetryNotifier.dispose();
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  void _updateState(DniCaptureState next) {
    if (_isDisposed) return;
    _captureStateNotifier.value = next;
  }

  void _startManualFallbackTimer() {
    _manualFallbackTimer?.cancel();
    _manualFallbackTimer = Timer(
      Duration(milliseconds: _orchestrator.manualFallbackMs),
      _onManualFallbackTimeout,
    );
  }

  void _onManualFallbackTimeout() {
    if (_isDisposed) return;
    final next = _orchestrator.onManualFallbackTimeout(
      _captureStateNotifier.value,
    );
    _updateState(next);
  }
}
