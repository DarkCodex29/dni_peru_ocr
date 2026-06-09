import 'package:dni_peru_ocr/src/lookup/models/dni_lookup_result.dart';
import 'package:dni_peru_ocr/src/lookup/services/dni_lookup_service.dart';

typedef DniLookupRetryPredicate = bool Function(DniLookupResult result);

/// Tries multiple [DniLookupService] instances, falling back on [retryOn].
final class FallbackDniLookupService implements DniLookupService {
  const FallbackDniLookupService({
    required this.services,
    this.retryOn = defaultRetryOn,
  }) : assert(services.length > 0);

  final List<DniLookupService> services;
  final DniLookupRetryPredicate retryOn;

  static bool defaultRetryOn(DniLookupResult result) {
    return result is DniLookupNetworkError || result is DniLookupServerError;
  }

  @override
  Future<DniLookupResult> lookup(String dni) async {
    DniLookupResult last = const DniLookupNetworkError();

    for (final service in services) {
      last = await service.lookup(dni);
      if (!retryOn(last)) {
        return last;
      }
    }

    return last;
  }
}
