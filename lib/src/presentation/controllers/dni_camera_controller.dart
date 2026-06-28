import 'package:camera/camera.dart';

import '../../data/ocr_consensus.dart';
import '../../data/ocr_field_extractor.dart';
import '../../domain/interfaces/ocr_logger.dart';
import '../../lookup/models/dni_data.dart';
import '../../lookup/reliable/dni_data_merger.dart';
import '../../lookup/reliable/reliable_dni_pipeline.dart';
import '../../lookup/services/dni_lookup_service.dart';

/// Pure Dart lifecycle controller for the DNI camera capture flow.
///
/// PR5 (capture-redesign final migration) removed this controller's parallel
/// capture-STATE subsystem — the `captureState` notifier, the manual-fallback
/// timer, and the `captureManually` / `activateManualFallback` /
/// `restartManualFallbackTimer` / `start` methods. That state was the second,
/// unreconciled source of truth (#5494): it ran in parallel to the live
/// auto-capture and the manual button read it, surfacing the manual fallback
/// too soon (#5536). The single capture-readiness owner is now
/// `CaptureCoordinator` (countdown, presence, AND manual fallback). This
/// controller is now scoped to its remaining job: the back-side OCR consensus
/// accumulator + the reliable lookup pipeline + capture delivery. (Breaking
/// public removal noted in CHANGELOG, mirroring PR1's CaptureDecider removal.)
class DniCameraController {
  DniCameraController({
    required bool isBackSide,
    required void Function(XFile file, OcrConsensusResult? consensus) onValidCapture,
    OcrLogger logger = const NoOpOcrLogger(),
    DniLookupService? lookupService,
    void Function(DniData)? onDniReady,
    Duration lookupTimeout = const Duration(milliseconds: 1500),
  })  : _isBackSide = isBackSide,
        _onValidCapture = onValidCapture,
        _logger = logger,
        _onDniReady = onDniReady,
        _pipeline = lookupService != null
            ? ReliableDniPipeline(
                lookupService: lookupService,
                merger: const DniDataMerger(),
                timeout: lookupTimeout,
              )
            : null;

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

  bool _isDisposed = false;
  bool _pipelineFired = false;

  OcrConsensusAccumulator? _accumulator;

  bool get isBackSide => _isBackSide;

  /// Called when the user toggles between front and back side.
  void onSideChanged({
    bool isBackSide = false,
    OcrExtractedFields? frontSideFields,
  }) {
    if (_isDisposed) return;
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
  }

  /// Disposes the controller. Idempotent.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _accumulator?.dispose();
    _accumulator = null;
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
}
