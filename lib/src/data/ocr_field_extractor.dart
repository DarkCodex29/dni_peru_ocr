import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'address_noise_filter.dart';
import 'strategies/address_field_strategy.dart';
import 'strategies/mrz_field_strategy.dart';
import 'strategies/ocr_field_strategy.dart';
import 'strategies/text_ocr_field_strategy.dart';
import '../domain/interfaces/ocr_logger.dart';

/// Container for fields extracted from a single OCR frame.
///
/// Mutable on purpose: the extractor merges values across frames in-place.
/// A snapshot of [_fromMrz] tracks whether the values originated from
/// MRZ checksum-valid parsing (highest confidence) or from text-OCR
/// fallback heuristics. MRZ values always win on merge.
class OcrExtractedFields {
  String? documentNumber;
  String? firstName;
  String? lastName;
  String? secondLastName;
  String? dateOfBirth;
  String? sex;
  String? expirationDate;
  String? nationality;
  String? address;

  /// Merges [other] into this instance.
  ///
  /// MRZ-sourced incoming always wins over text-OCR current.
  /// Pass an optional [logger] to record OCR/MRZ mismatch breadcrumbs.
  /// Defaults to a [NoOpOcrLogger] (silent) when not provided.
  void merge(OcrExtractedFields other, {OcrLogger? logger}) {
    // MRZ-sourced incoming always wins over text-OCR current.
    // When merging text into an MRZ accumulator, MRZ is preserved.
    final incomingIsMrz = other._fromMrz;
    final currentIsMrz = _fromMrz;
    final effectiveLogger = logger ?? const NoOpOcrLogger();

    documentNumber = _bestWithMrz(
      current: documentNumber,
      incoming: other.documentNumber,
      fieldName: 'documentNumber',
      incomingIsMrz: incomingIsMrz,
      currentIsMrz: currentIsMrz,
      logger: effectiveLogger,
    );
    firstName = _best(
      firstName,
      other.firstName,
      incomingIsMrz: incomingIsMrz,
      currentIsMrz: currentIsMrz,
    );
    lastName = _best(
      lastName,
      other.lastName,
      incomingIsMrz: incomingIsMrz,
      currentIsMrz: currentIsMrz,
    );
    secondLastName = _best(
      secondLastName,
      other.secondLastName,
      incomingIsMrz: incomingIsMrz,
      currentIsMrz: currentIsMrz,
    );
    dateOfBirth = _best(
      dateOfBirth,
      other.dateOfBirth,
      incomingIsMrz: incomingIsMrz,
      currentIsMrz: currentIsMrz,
    );
    sex = _best(
      sex,
      other.sex,
      incomingIsMrz: incomingIsMrz,
      currentIsMrz: currentIsMrz,
    );
    expirationDate = _best(
      expirationDate,
      other.expirationDate,
      incomingIsMrz: incomingIsMrz,
      currentIsMrz: currentIsMrz,
    );
    nationality = _best(
      nationality,
      other.nationality,
      incomingIsMrz: incomingIsMrz,
      currentIsMrz: currentIsMrz,
    );

    // address is never MRZ-sourced; prefer the longer (more complete) value.
    address = _best(
      address,
      other.address,
      incomingIsMrz: false,
      currentIsMrz: false,
    );

    // Promote MRZ flag if incoming was MRZ-sourced.
    if (incomingIsMrz) _fromMrz = true;
  }

  /// Merges [documentNumber] with a logger breadcrumb on mismatch.
  String? _bestWithMrz({
    required String? current,
    required String? incoming,
    required String fieldName,
    required bool incomingIsMrz,
    required bool currentIsMrz,
    required OcrLogger logger,
  }) {
    if (incoming == null || incoming.isEmpty) return current;
    if (current == null || current.isEmpty) return incoming;

    // MRZ incoming wins unconditionally over text-OCR current.
    if (incomingIsMrz && !currentIsMrz) {
      if (incoming != current) {
        _reportMismatch(fieldName, ocrValue: current, mrzValue: incoming, logger: logger);
      }
      return incoming;
    }

    // Text-OCR incoming does NOT overwrite an MRZ-sourced current.
    if (!incomingIsMrz && currentIsMrz) return current;

    // Both same source — prefer longer (original heuristic).
    return incoming.length >= current.length ? incoming : current;
  }

  String? _best(
    String? current,
    String? incoming, {
    required bool incomingIsMrz,
    required bool currentIsMrz,
  }) {
    if (incoming == null || incoming.isEmpty) return current;
    if (current == null || current.isEmpty) return incoming;

    if (incomingIsMrz && !currentIsMrz) return incoming;
    if (!incomingIsMrz && currentIsMrz) return current;

    // Both same source — prefer longer (original heuristic).
    return incoming.length >= current.length ? incoming : current;
  }

  static void _reportMismatch(
    String field, {
    required String ocrValue,
    required String mrzValue,
    required OcrLogger logger,
  }) {
    logger.breadcrumb(
      'kyc-ocr-mrz-mismatch',
      'KYC OCR/MRZ mismatch on $field: ocr="$ocrValue" mrz="$mrzValue"',
      data: {
        'field': field,
        'ocr': ocrValue,
        'mrz': mrzValue,
      },
    );
  }

  int get foundCount => fields.values.where((v) => v != null).length;
  int get totalCount => fields.length;
  bool get hasMrzData => _fromMrz;
  bool _fromMrz = false;

  /// Marks this instance as MRZ-sourced.
  ///
  /// Called by [MrzFieldStrategy] after a successful MRZ parse.
  /// Callers outside this package should use [hasMrzData] for reads.
  // ignore: avoid_setters_without_getters
  set markAsMrzSourced(bool value) => _fromMrz = value;

  /// Test-only helper — marks this instance as MRZ-sourced without going
  /// through the full MRZ parsing path. Callers should use [hasMrzData]
  /// for reads; a dedicated getter is intentionally omitted here.
  @visibleForTesting
  // ignore: avoid_setters_without_getters
  set fromMrzForTest(bool value) => _fromMrz = value;

  Map<String, String?> get fields => {
    'N° Documento': documentNumber,
    'Apellido paterno': lastName,
    'Apellido materno': secondLastName,
    'Nombres': firstName,
    'Nacimiento': dateOfBirth,
    'Sexo': sex,
    'Caducidad': expirationDate,
    'Nacionalidad': nationality,
    'Dirección': address,
  };

  @override
  String toString() {
    final buf = StringBuffer();
    final src = _fromMrz ? ' [MRZ]' : '';
    for (final entry in fields.entries) {
      final status = entry.value != null ? '✅' : '⬜';
      buf.writeln('$status ${entry.key}: ${entry.value ?? '—'}$src');
    }
    return buf.toString();
  }
}

/// Thin coordinator that turns [RecognizedText] into [OcrExtractedFields]
/// by delegating to three focused strategies.
///
/// Strategy order:
/// 1. [MrzFieldStrategy] — highest confidence, all fields except address.
/// 2. [TextOcrFieldStrategy] — label-anchored heuristics (skipped when MRZ
///    succeeded, except for `secondLastName` back-fill on DNI azul).
/// 3. [AddressFieldStrategy] — always runs (address is never in MRZ).
///
/// All strategies are stateless. The default instance uses the standard
/// three strategies; pass a custom [List<OcrFieldStrategy>] to the
/// constructor for testing or alternative pipelines.
///
/// Pass an [OcrLogger] to receive breadcrumb events (e.g. OCR/MRZ mismatch).
/// Defaults to [NoOpOcrLogger] when not provided.
class OcrFieldExtractor {
  /// Creates a coordinator with optional strategies and logger.
  ///
  /// [logger] defaults to [NoOpOcrLogger] (no-op) when not supplied.
  const OcrFieldExtractor({
    List<OcrFieldStrategy>? strategies,
    OcrLogger logger = const NoOpOcrLogger(),
  })  : _strategies = strategies,
        _logger = logger;

  final List<OcrFieldStrategy>? _strategies;
  final OcrLogger _logger;

  /// Runs the extraction pipeline using this instance's strategy list.
  OcrExtractedFields extractWith(RecognizedText recognized) {
    final mrz = _mrzStrategy;
    final text = _textStrategy;
    final address = _addressStrategy;
    return _runPipeline(recognized, mrz, text, address, _logger);
  }

  OcrFieldStrategy get _mrzStrategy =>
      _strategies?.whereType<MrzFieldStrategy>().firstOrNull ??
      const MrzFieldStrategy();

  OcrFieldStrategy get _textStrategy =>
      _strategies?.whereType<TextOcrFieldStrategy>().firstOrNull ??
      const TextOcrFieldStrategy();

  OcrFieldStrategy get _addressStrategy =>
      _strategies?.whereType<AddressFieldStrategy>().firstOrNull ??
      const AddressFieldStrategy();

  /// Runs the extraction pipeline on [recognized] and returns the merged
  /// [OcrExtractedFields]. Returns an empty instance when no blocks are
  /// present.
  ///
  /// Uses the default three strategies (MRZ → Text → Address).
  static OcrExtractedFields extract(RecognizedText recognized) {
    return _runPipeline(
      recognized,
      const MrzFieldStrategy(),
      const TextOcrFieldStrategy(),
      const AddressFieldStrategy(),
      const NoOpOcrLogger(),
    );
  }

  /// Deprecated alias for [extract]. Will be removed in 0.7.0.
  ///
  /// Kept for InClub migration softening — the `static` name was the
  /// original API before the Strategy decomposition. Replace call sites
  /// with `OcrFieldExtractor.extract(recognized)` at your convenience.
  ///
  /// TODO(0.7.0): Remove this alias.
  @Deprecated(
    'Use OcrFieldExtractor.extract() instead. '
    'extractStatic will be removed in v0.7.0.',
  )
  static OcrExtractedFields extractStatic(RecognizedText recognized) =>
      extract(recognized);

  static OcrExtractedFields _runPipeline(
    RecognizedText recognized,
    OcrFieldStrategy mrzStrategy,
    OcrFieldStrategy textStrategy,
    OcrFieldStrategy addressStrategy,
    OcrLogger logger,
  ) {
    final empty = OcrExtractedFields();
    if (recognized.blocks.isEmpty) return empty;

    // Step 1: Try MRZ — highest confidence source.
    final mrzResult = mrzStrategy.extract(recognized);

    if (mrzResult != null) {
      // Step 2 (address): always runs — address is never in MRZ.
      final addressResult = addressStrategy.extract(recognized);
      if (addressResult?.address != null) {
        mrzResult.address = addressResult!.address;
      }

      // Step 3 (secondLastName back-fill): DNI azul has the "Segundo Apellido"
      // label on the same physical side as the MRZ. MRZ only carries one
      // surname, so extract the second surname from text if MRZ missed it.
      if (mrzResult.secondLastName == null) {
        final textResult = textStrategy.extract(recognized);
        if (textResult?.secondLastName != null) {
          mrzResult.secondLastName = textResult!.secondLastName;
        }
      }

      return mrzResult;
    }

    // Step 1 failed: run text-OCR extraction.
    final textResult = textStrategy.extract(recognized) ?? OcrExtractedFields();

    // Step 2 (address): always runs.
    final addressResult = addressStrategy.extract(recognized);
    if (addressResult?.address != null) {
      textResult.address = addressResult!.address;
    }

    return textResult;
  }

  // ── Address noise filter delegators ──────────────────────────────────
  //
  // The actual implementation lives in [AddressNoiseFilter].
  // These delegating static methods preserve the public API surface so
  // existing callers (including the 1621-line regression test) keep
  // working without modification.

  /// Per-line address noise filter.
  ///
  /// Delegates to [AddressNoiseFilter.cleanAddressLine].
  static String? cleanAddressLine(String rawLine) =>
      AddressNoiseFilter.cleanAddressLine(rawLine);

  /// Removes denylist tokens from both the head and tail of an address.
  ///
  /// Delegates to [AddressNoiseFilter.stripAddressLabelTail].
  static String stripAddressLabelTail(String address) =>
      AddressNoiseFilter.stripAddressLabelTail(address);
}
