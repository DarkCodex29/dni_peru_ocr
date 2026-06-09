import 'package:dni_peru_ocr/src/lookup/models/dni_lookup_result.dart';
import 'package:dni_peru_ocr/src/lookup/services/dni_lookup_service.dart';

typedef DniLookupRetryPredicate = bool Function(DniLookupResult result);

/// Decorator that tries multiple [DniLookupService] instances in order,
/// falling back to the next when the current result satisfies [retryOn].
///
/// By default, retries only on transient failures ([DniLookupNetworkError]
/// and [DniLookupServerError]). Configuration errors such as
/// [DniLookupInvalidToken] immediately stop the chain.
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
