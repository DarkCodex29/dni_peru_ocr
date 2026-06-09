import 'package:dni_peru_ocr/src/lookup/models/dni_data.dart';

sealed class DniLookupResult {
  const DniLookupResult();
}

final class DniLookupSuccess extends DniLookupResult {
  const DniLookupSuccess(this.data);
  final DniData data;
}

final class DniLookupNotFound extends DniLookupResult {
  const DniLookupNotFound();
}

final class DniLookupRateLimited extends DniLookupResult {
  const DniLookupRateLimited({this.retryAfterSeconds});
  final int? retryAfterSeconds;
}

final class DniLookupNetworkError extends DniLookupResult {
  const DniLookupNetworkError({this.cause});
  final String? cause;
}

final class DniLookupInvalidToken extends DniLookupResult {
  const DniLookupInvalidToken();
}

final class DniLookupServerError extends DniLookupResult {
  const DniLookupServerError({required this.statusCode, this.body});
  final int statusCode;
  final String? body;
}
