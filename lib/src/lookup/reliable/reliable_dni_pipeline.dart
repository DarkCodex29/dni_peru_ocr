import 'dart:async';

import 'package:dni_peru_ocr/src/domain/interfaces/ocr_logger.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_data.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_lookup_result.dart';
import 'package:dni_peru_ocr/src/lookup/reliable/dni_data_merger.dart';
import 'package:dni_peru_ocr/src/lookup/services/dni_lookup_service.dart';

final class ReliableDniPipeline {
  ReliableDniPipeline({
    required DniLookupService lookupService,
    required DniDataMerger merger,
    Duration timeout = const Duration(milliseconds: 1500),
    OcrLogger logger = const NoOpOcrLogger(),
  })  : _lookupService = lookupService,
        _merger = merger,
        _timeout = timeout,
        _logger = logger;

  final DniLookupService _lookupService;
  final DniDataMerger _merger;
  final Duration _timeout;
  final OcrLogger _logger;
  bool _lookupFired = false;

  Future<DniData> resolveOnConsensus(DniData ocrData) async {
    if (_lookupFired) return ocrData;
    _lookupFired = true;

    late final DniLookupResult result;
    try {
      result = await _lookupService.lookup(ocrData.dni).timeout(_timeout);
    } on TimeoutException {
      _logger.breadcrumb(
        'kyc-ocr-lookup-timeout',
        'RENIEC lookup exceeded budget',
        data: {
          'dni_suffix': _suffix(ocrData.dni),
          'budget_ms': _timeout.inMilliseconds,
        },
      );
      return ocrData;
    }

    return switch (result) {
      DniLookupSuccess(:final data) when data.dni == ocrData.dni =>
        _merger.merge(ocr: ocrData, reniec: data),
      DniLookupSuccess(:final data) =>
        _logMismatchAndFallback(ocrData, data),
      DniLookupNotFound() =>
        ocrData,
      DniLookupNetworkError(:final cause) =>
        _logErrorAndFallback(ocrData, 'network_error', cause: cause),
      DniLookupServerError(:final statusCode) =>
        _logErrorAndFallback(ocrData, 'server_error_$statusCode', statusCode: statusCode),
      DniLookupInvalidToken() =>
        _logErrorAndFallback(ocrData, 'invalid_token', silent: true),
      DniLookupRateLimited() =>
        _logErrorAndFallback(ocrData, 'rate_limited'),
    };
  }

  DniData _logErrorAndFallback(
    DniData ocrData,
    String reason, {
    String? cause,
    int? statusCode,
    bool silent = false,
  }) {
    if (!silent) {
      final data = <String, Object?>{'dni_suffix': _suffix(ocrData.dni)};
      if (cause != null) data['cause'] = cause;
      if (statusCode != null) data['status_code'] = statusCode;
      _logger.breadcrumb(
        'kyc-ocr-lookup-error',
        'RENIEC lookup failed: $reason',
        data: data,
      );
    }
    return ocrData;
  }

  DniData _logMismatchAndFallback(DniData ocrData, DniData reniecData) {
    _logger.breadcrumb(
      'kyc-ocr-lookup-mismatch',
      'RENIEC returned different DNI; discarding',
      data: {
        'ocr_dni_suffix': _suffix(ocrData.dni),
        'reniec_dni_suffix': _suffix(reniecData.dni),
      },
    );
    return ocrData;
  }

  String _suffix(String dni) {
    if (dni.length <= 3) return dni;
    return dni.substring(dni.length - 3);
  }
}
