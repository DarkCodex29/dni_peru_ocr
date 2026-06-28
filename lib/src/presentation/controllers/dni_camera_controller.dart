import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../orchestrators/dni_capture_orchestrator.dart';
import '../orchestrators/dni_capture_state.dart';
import '../../data/ocr_consensus.dart';
import '../../data/ocr_field_extractor.dart';
import '../../domain/interfaces/ocr_logger.dart';
import '../../lookup/models/dni_data.dart';
import '../../lookup/reliable/dni_data_merger.dart';
import '../../lookup/reliable/reliable_dni_pipeline.dart';
import '../../lookup/services/dni_lookup_service.dart';

/// Pure Dart lifecycle controller for the DNI camera capture flow.
class DniCameraController {
  DniCameraController({
    required DniCaptureOrchestrator orchestrator,
    required bool isBackSide,
    required void Function(XFile file, OcrConsensusResult? consensus) onValidCapture,
    OcrLogger logger = const NoOpOcrLogger(),
    DniLookupService? lookupService,
    void Function(DniData)? onDniReady,
    Duration lookupTimeout = const Duration(milliseconds: 1500),
  })  : _orchestrator = orchestrator,
        _isBackSide = isBackSide,
        _onValidCapture = onValidCapture,
        _logger = logger,
        _onDniReady = onDniReady,
        _pipeline = lookupService != null
            ? ReliableDniPipeline(
                lookupService: lookupService,
                merger: const DniDataMerger(),
                timeout: lookupTimeout,
              )
            : null,
        _captureStateNotifier = ValueNotifier(
          const DniCaptureScanning(
            guideText: '',
            failingGate: null,
            validationProgress: 0,
            stableFrames: 0,
            userDataMatch: null,
            manualModeActive: false,
          ),
        );

  final DniCaptureOrchestrator _orchestrator;

  final OcrLogger _logger;

  final ReliableDniPipeline? _pipeline;
  final void Function(DniData)? _onDniReady;

  /// Emits a breadcrumb through the injected logger.
  void emitBreadcrumb(
    String category,
    String message, {
    Map<String, Object?>? data,
  }) {
    _logger.breadcrumb(category, message, data: data);
  }

  bool _isBackSide;

  final void Function(XFile file, OcrConsensusResult? consensus) _onValidCapture;

  final ValueNotifier<DniCaptureState> _captureStateNotifier;

  bool _isDisposed = false;
  bool _pipelineFired = false;
  Timer? _manualFallbackTimer;

  OcrConsensusAccumulator? _accumulator;

  ValueListenable<DniCaptureState> get captureState => _captureStateNotifier;

  bool get isBackSide => _isBackSide;

  /// Starts the manual-fallback timer.
  Future<void> start() async {
    if (_isDisposed) return;
    _startManualFallbackTimer();
  }

  /// Stops any in-progress frame work. Does NOT dispose the controller.
  void stop() {
    _manualFallbackTimer?.cancel();
  }

  /// Restarts the manual-fallback window so it measures from the CURRENT side
  /// rather than from scanner open (#5536). The live front->back handoff does
  /// not route through [onSideChanged], so without this the back inherits the
  /// front's already-elapsing timer and the manual button surfaces too soon.
  /// Call it when a new side starts trying so the fallback gives auto-capture a
  /// full per-side window before offering the manual escape.
  void restartManualFallbackTimer() {
    if (_isDisposed) return;
    _startManualFallbackTimer();
  }

  /// Surfaces manual-assisted capture on demand, reusing the same transition
  /// as the manual fallback. Used to escape a stuck waiting phase without
  /// auto-capturing an unconfirmed side.
  void activateManualFallback() {
    if (_isDisposed) return;
    _updateState(
      _orchestrator.onManualFallbackTimeout(_captureStateNotifier.value),
    );
  }

  /// Triggers a manual capture.
  void captureManually() {
    if (_isDisposed) return;
    final current = _captureStateNotifier.value;
    if (current is DniCaptureInFlight ||
        current is DniCaptureExpired ||
        current is DniCaptureDone) {
      return;
    }
    _updateState(const DniCaptureInFlight(showFlash: true));
  }

  /// Called when the user toggles between front and back side.
  void onSideChanged({
    bool isBackSide = false,
    OcrExtractedFields? frontSideFields,
  }) {
    if (_isDisposed) return;
    _manualFallbackTimer?.cancel();
    _pipelineFired = false;

    _isBackSide = isBackSide;

    _accumulator?.dispose();
    _accumulator = null;

    if (isBackSide) {
      _accumulator = OcrConsensusAccumulator();
      final seed = frontSideFields;
      if (seed != null) {
        final seedVotes = <String, String?>{};
        if (seed.firstName != null) seedVotes['firstName'] = seed.firstName;
        if (seed.lastName != null) seedVotes['lastName'] = seed.lastName;
        if (seed.secondLastName != null) {
          seedVotes['secondLastName'] = seed.secondLastName;
        }
        if (seed.documentNumber != null) {
          seedVotes['documentNumber'] = seed.documentNumber;
        }
        if (seed.dateOfBirth != null) {
          seedVotes['dateOfBirth'] = seed.dateOfBirth;
        }
        if (seed.expirationDate != null) {
          seedVotes['expirationDate'] = seed.expirationDate;
        }
        if (seed.address != null) seedVotes['address'] = seed.address;
        if (seedVotes.isNotEmpty) _accumulator!.recordVote(seedVotes);
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

  /// Records a processed OCR frame in the active consensus accumulator.
  bool recordOcrFrame(OcrExtractedFields frameFields) {
    final acc = _accumulator;
    if (acc == null) return false;

    late final bool consensusReached;
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
      consensusReached = acc.isMrzLocked;
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
      consensusReached = acc.checkAllThresholds();
    }

    if (consensusReached && _pipeline != null && !_pipelineFired) {
      _pipelineFired = true;
      _resolveAndDeliver(_dniDataFromSnapshot(acc.snapshot()));
    }

    return consensusReached;
  }

  /// Emits the current consensus snapshot, or `null` when no accumulator is active.
  OcrConsensusResult? snapshotConsensus() => _accumulator?.snapshot();

  /// Notifies the controller that the widget has completed a capture.
  void onCaptureDelivered({
    required XFile file,
    OcrConsensusResult? consensus,
  }) {
    if (_isDisposed) return;
    _onValidCapture(file, _isBackSide ? consensus : null);
    _updateState(const DniCaptureDone());
  }

  /// Disposes the controller. Idempotent.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _manualFallbackTimer?.cancel();
    _captureStateNotifier.value = const DniCaptureDone();
    _accumulator?.dispose();
    _accumulator = null;
    _captureStateNotifier.dispose();
  }

  void _resolveAndDeliver(DniData ocrData) {
    _pipeline!
        .resolveOnConsensus(ocrData)
        .then((data) => _onDniReady?.call(data));
  }

  DniData _dniDataFromSnapshot(OcrConsensusResult snapshot) {
    return DniData(
      dni: snapshot.documentNumber.value ?? '',
      nombres: snapshot.firstName.value ?? '',
      apellidoPaterno: snapshot.lastName.value ?? '',
      apellidoMaterno: snapshot.secondLastName.value ?? '',
      nombreCompleto: [
        snapshot.firstName.value ?? '',
        snapshot.lastName.value ?? '',
        snapshot.secondLastName.value ?? '',
      ].where((s) => s.isNotEmpty).join(' '),
    );
  }

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
