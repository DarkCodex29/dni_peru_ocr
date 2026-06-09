import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'address_noise_filter.dart';
import 'strategies/address_field_strategy.dart';
import 'strategies/mrz_field_strategy.dart';
import 'strategies/ocr_field_strategy.dart';
import 'strategies/text_ocr_field_strategy.dart';
import '../domain/interfaces/ocr_logger.dart';

/// Container for fields extracted from a single OCR frame.
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
  String? department;
  String? province;
  String? district;

  /// Merges [other] into this instance. MRZ-sourced values win.
  void merge(OcrExtractedFields other, {OcrLogger? logger}) {
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

    address = _best(
      address,
      other.address,
      incomingIsMrz: false,
      currentIsMrz: false,
    );

    department = _best(
      department,
      other.department,
      incomingIsMrz: false,
      currentIsMrz: false,
    );
    province = _best(
      province,
      other.province,
      incomingIsMrz: false,
      currentIsMrz: false,
    );
    district = _best(
      district,
      other.district,
      incomingIsMrz: false,
      currentIsMrz: false,
    );

    if (incomingIsMrz) _fromMrz = true;
  }

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

    if (incomingIsMrz && !currentIsMrz) {
      if (incoming != current) {
        _reportMismatch(fieldName,
            ocrValue: current, mrzValue: incoming, logger: logger);
      }
      return incoming;
    }

    if (!incomingIsMrz && currentIsMrz) return current;

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

  // ignore: avoid_setters_without_getters
  set markAsMrzSourced(bool value) => _fromMrz = value;

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
        'Departamento': department,
        'Provincia': province,
        'Distrito': district,
      };

  static const _kMrzSourcedKeys = {
    'N° Documento',
    'Apellido paterno',
    'Apellido materno',
    'Nombres',
    'Nacimiento',
    'Sexo',
    'Caducidad',
    'Nacionalidad',
  };

  @override
  String toString() {
    final buf = StringBuffer();
    for (final entry in fields.entries) {
      final status = entry.value != null ? '✅' : '⬜';
      final src =
          (_fromMrz && _kMrzSourcedKeys.contains(entry.key)) ? ' [MRZ]' : '';
      buf.writeln('$status ${entry.key}: ${entry.value ?? '—'}$src');
    }
    return buf.toString();
  }
}

/// Coordinator that turns [RecognizedText] into [OcrExtractedFields].
class OcrFieldExtractor {
  const OcrFieldExtractor({
    List<OcrFieldStrategy>? strategies,
    OcrLogger logger = const NoOpOcrLogger(),
  })  : _strategies = strategies,
        _logger = logger;

  final List<OcrFieldStrategy>? _strategies;
  final OcrLogger _logger;

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

  static OcrExtractedFields extract(RecognizedText recognized) {
    return _runPipeline(
      recognized,
      const MrzFieldStrategy(),
      const TextOcrFieldStrategy(),
      const AddressFieldStrategy(),
      const NoOpOcrLogger(),
    );
  }

  static OcrExtractedFields _runPipeline(
    RecognizedText recognized,
    OcrFieldStrategy mrzStrategy,
    OcrFieldStrategy textStrategy,
    OcrFieldStrategy addressStrategy,
    OcrLogger logger,
  ) {
    final empty = OcrExtractedFields();
    if (recognized.blocks.isEmpty) return empty;

    final mrzResult = mrzStrategy.extract(recognized);

    if (mrzResult != null) {
      final addressResult = addressStrategy.extract(recognized);
      if (addressResult != null) {
        if (addressResult.address != null) {
          mrzResult.address = addressResult.address;
        }
        if (addressResult.department != null) {
          mrzResult.department = addressResult.department;
        }
        if (addressResult.province != null) {
          mrzResult.province = addressResult.province;
        }
        if (addressResult.district != null) {
          mrzResult.district = addressResult.district;
        }
      }

      if (mrzResult.secondLastName == null) {
        final textResult = textStrategy.extract(recognized);
        if (textResult?.secondLastName != null) {
          mrzResult.secondLastName = textResult!.secondLastName;
        }
      }

      return mrzResult;
    }

    final textResult = textStrategy.extract(recognized) ?? OcrExtractedFields();

    final addressResult = addressStrategy.extract(recognized);
    if (addressResult != null) {
      if (addressResult.address != null) {
        textResult.address = addressResult.address;
      }
      if (addressResult.department != null) {
        textResult.department = addressResult.department;
      }
      if (addressResult.province != null) {
        textResult.province = addressResult.province;
      }
      if (addressResult.district != null) {
        textResult.district = addressResult.district;
      }
    }

    return textResult;
  }

  static String? cleanAddressLine(String rawLine) =>
      AddressNoiseFilter.cleanAddressLine(rawLine);

  static String stripAddressLabelTail(String address) =>
      AddressNoiseFilter.stripAddressLabelTail(address);
}
