import 'package:dni_peru_ocr/src/lookup/models/dni_http_response.dart';

abstract interface class DniHttpClient {
  Future<DniHttpResponse> get(Uri uri, {Map<String, String>? headers});
}
