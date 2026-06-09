import 'package:dni_peru_ocr/src/domain/interfaces/ocr_logger.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_data.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_lookup_result.dart';
import 'package:dni_peru_ocr/src/lookup/reliable/dni_data_merger.dart';
import 'package:dni_peru_ocr/src/lookup/reliable/reliable_dni_pipeline.dart';
import 'package:dni_peru_ocr/src/lookup/services/dni_lookup_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

DniData _makeDniData({
  String dni = '12345678',
  String nombres = 'NOMBRES',
  String apellidoPaterno = 'PATERNO',
  String apellidoMaterno = 'MATERNO',
  String nombreCompleto = 'COMPLETO',
}) =>
    DniData(
      dni: dni,
      nombres: nombres,
      apellidoPaterno: apellidoPaterno,
      apellidoMaterno: apellidoMaterno,
      nombreCompleto: nombreCompleto,
    );

final class _FakeLookupService implements DniLookupService {
  _FakeLookupService(this._result);
  final DniLookupResult _result;

  @override
  Future<DniLookupResult> lookup(String dni) async => _result;
}

final class _DelayedLookupService implements DniLookupService {
  _DelayedLookupService(this._result, this._delay);
  final DniLookupResult _result;
  final Duration _delay;

  @override
  Future<DniLookupResult> lookup(String dni) async {
    await Future<void>.delayed(_delay);
    return _result;
  }
}

final class _CapturingLogger implements OcrLogger {
  final List<(String, String, Map<String, Object?>?)> calls = [];

  @override
  void breadcrumb(String category, String message, {Map<String, Object?>? data}) {
    calls.add((category, message, data));
  }
}

ReliableDniPipeline _makePipeline({
  required DniLookupService service,
  DniDataMerger merger = const DniDataMerger(),
  Duration timeout = const Duration(milliseconds: 1500),
  OcrLogger? logger,
}) =>
    ReliableDniPipeline(
      lookupService: service,
      merger: merger,
      timeout: timeout,
      logger: logger ?? const NoOpOcrLogger(),
    );

void main() {
  final ocrData = _makeDniData(
    dni: '12345678',
    nombres: 'OCR_N',
    apellidoPaterno: 'OCR_P',
    apellidoMaterno: 'OCR_M',
    nombreCompleto: 'OCR_C',
  );

  final reniecData = _makeDniData(
    dni: '12345678',
    nombres: 'RENIEC_N',
    apellidoPaterno: 'RENIEC_P',
    apellidoMaterno: 'RENIEC_M',
    nombreCompleto: 'RENIEC_C',
  );

  group('ReliableDniPipeline — happy path (Success + matching DNI)', () {
    test('returns merged data when Success and DNI matches', () async {
      final service = _FakeLookupService(DniLookupSuccess(reniecData));
      final pipeline = _makePipeline(service: service);
      final result = await pipeline.resolveOnConsensus(ocrData);

      expect(result.nombres, equals('RENIEC_N'));
      expect(result.apellidoPaterno, equals('RENIEC_P'));
      expect(result.dni, equals('12345678'));
      expect(result.rawSource, isNull);
    });

    test('merged result preserves ocr.dni invariant', () async {
      final service = _FakeLookupService(DniLookupSuccess(reniecData));
      final pipeline = _makePipeline(service: service);
      final result = await pipeline.resolveOnConsensus(ocrData);

      expect(result.dni, equals(ocrData.dni));
    });
  });

  group('ReliableDniPipeline — timeout falls back to OCR', () {
    test('timeout returns ocrData and logs timeout category', () {
      fakeAsync((async) {
        final logger = _CapturingLogger();
        final service = _DelayedLookupService(
          DniLookupSuccess(reniecData),
          const Duration(milliseconds: 2000),
        );
        final pipeline = _makePipeline(
          service: service,
          timeout: const Duration(milliseconds: 1500),
          logger: logger,
        );

        DniData? result;
        pipeline.resolveOnConsensus(ocrData).then((v) => result = v);

        async.elapse(const Duration(milliseconds: 1600));

        expect(result, isNotNull);
        expect(result!.nombres, equals('OCR_N'));
        expect(result!.dni, equals('12345678'));
        expect(logger.calls, hasLength(1));
        expect(logger.calls.first.$1, equals('kyc-ocr-lookup-timeout'));
      });
    });

    test('custom timeout duration is respected', () {
      fakeAsync((async) {
        final logger = _CapturingLogger();
        final service = _DelayedLookupService(
          DniLookupSuccess(reniecData),
          const Duration(milliseconds: 3000),
        );
        final pipeline = _makePipeline(
          service: service,
          timeout: const Duration(milliseconds: 500),
          logger: logger,
        );

        DniData? result;
        pipeline.resolveOnConsensus(ocrData).then((v) => result = v);

        async.elapse(const Duration(milliseconds: 600));

        expect(result, isNotNull);
        expect(result!.nombres, equals('OCR_N'));
        expect(logger.calls.first.$1, equals('kyc-ocr-lookup-timeout'));
      });
    });
  });

  group('ReliableDniPipeline — NetworkError falls back to OCR with log', () {
    test('NetworkError returns ocrData and logs error category', () async {
      final logger = _CapturingLogger();
      final service = _FakeLookupService(
        const DniLookupNetworkError(cause: 'Connection refused'),
      );
      final pipeline = _makePipeline(service: service, logger: logger);
      final result = await pipeline.resolveOnConsensus(ocrData);

      expect(result.nombres, equals('OCR_N'));
      expect(logger.calls, hasLength(1));
      expect(logger.calls.first.$1, equals('kyc-ocr-lookup-error'));
    });
  });

  group('ReliableDniPipeline — ServerError falls back to OCR with log', () {
    test('ServerError returns ocrData and logs error category', () async {
      final logger = _CapturingLogger();
      final service = _FakeLookupService(
        const DniLookupServerError(statusCode: 500),
      );
      final pipeline = _makePipeline(service: service, logger: logger);
      final result = await pipeline.resolveOnConsensus(ocrData);

      expect(result.nombres, equals('OCR_N'));
      expect(logger.calls, hasLength(1));
      expect(logger.calls.first.$1, equals('kyc-ocr-lookup-error'));
    });
  });

  group('ReliableDniPipeline — RateLimited falls back to OCR with log', () {
    test('RateLimited returns ocrData and logs error category', () async {
      final logger = _CapturingLogger();
      final service = _FakeLookupService(
        const DniLookupRateLimited(retryAfterSeconds: 60),
      );
      final pipeline = _makePipeline(service: service, logger: logger);
      final result = await pipeline.resolveOnConsensus(ocrData);

      expect(result.nombres, equals('OCR_N'));
      expect(logger.calls, hasLength(1));
      expect(logger.calls.first.$1, equals('kyc-ocr-lookup-error'));
    });
  });

  group('ReliableDniPipeline — InvalidToken falls back to OCR without log', () {
    test('InvalidToken returns ocrData silently', () async {
      final logger = _CapturingLogger();
      final service = _FakeLookupService(const DniLookupInvalidToken());
      final pipeline = _makePipeline(service: service, logger: logger);
      final result = await pipeline.resolveOnConsensus(ocrData);

      expect(result.nombres, equals('OCR_N'));
      expect(logger.calls, isEmpty);
    });
  });

  group('ReliableDniPipeline — NotFound falls back to OCR without log', () {
    test('NotFound returns ocrData silently', () async {
      final logger = _CapturingLogger();
      final service = _FakeLookupService(const DniLookupNotFound());
      final pipeline = _makePipeline(service: service, logger: logger);
      final result = await pipeline.resolveOnConsensus(ocrData);

      expect(result.nombres, equals('OCR_N'));
      expect(logger.calls, isEmpty);
    });
  });

  group('ReliableDniPipeline — DNI mismatch discards RENIEC and logs mismatch', () {
    test('Success with mismatched DNI returns ocrData and logs mismatch category', () async {
      final logger = _CapturingLogger();
      final mismatchedReniec = _makeDniData(
        dni: '99999999',
        nombres: 'RENIEC_N',
      );
      final service = _FakeLookupService(DniLookupSuccess(mismatchedReniec));
      final pipeline = _makePipeline(service: service, logger: logger);
      final result = await pipeline.resolveOnConsensus(ocrData);

      expect(result.nombres, equals('OCR_N'));
      expect(logger.calls, hasLength(1));
      expect(logger.calls.first.$1, equals('kyc-ocr-lookup-mismatch'));
    });
  });

  group('ReliableDniPipeline — idempotent guard', () {
    test('second call returns ocrData without invoking lookup again', () async {
      var lookupCallCount = 0;
      final countingService = _CountingLookupService(
        DniLookupSuccess(reniecData),
        onCall: () => lookupCallCount++,
      );
      final pipeline = _makePipeline(service: countingService);

      await pipeline.resolveOnConsensus(ocrData);
      final secondResult = await pipeline.resolveOnConsensus(ocrData);

      expect(lookupCallCount, equals(1));
      expect(secondResult.nombres, equals(ocrData.nombres));
    });

    test('second call returns ocrData immediately without merging', () async {
      final service = _FakeLookupService(DniLookupSuccess(reniecData));
      final pipeline = _makePipeline(service: service);

      final firstResult = await pipeline.resolveOnConsensus(ocrData);
      final secondResult = await pipeline.resolveOnConsensus(ocrData);

      expect(firstResult.nombres, equals('RENIEC_N'));
      expect(secondResult.nombres, equals('OCR_N'));
    });
  });
}

final class _CountingLookupService implements DniLookupService {
  _CountingLookupService(this._result, {required this.onCall});
  final DniLookupResult _result;
  final void Function() onCall;

  @override
  Future<DniLookupResult> lookup(String dni) async {
    onCall();
    return _result;
  }
}
