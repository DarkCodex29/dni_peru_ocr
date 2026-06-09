import 'package:dio/dio.dart';

import 'package:dni_peru_ocr/src/lookup/http/dni_http_client.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_http_response.dart';

/// Dio-backed implementation of [DniHttpClient].
final class DioDniHttpClient implements DniHttpClient {
  const DioDniHttpClient(this.dio);

  final Dio dio;

  @override
  Future<DniHttpResponse> get(Uri uri, {Map<String, String>? headers}) async {
    try {
      final response = await dio.getUri<String>(
        uri,
        options: Options(
          headers: headers,
          responseType: ResponseType.plain,
        ),
      );
      return DniHttpResponse(
        statusCode: response.statusCode ?? 0,
        body: response.data ?? '',
      );
    } on DioException catch (e) {
      if (e.response != null) {
        return DniHttpResponse(
          statusCode: e.response!.statusCode ?? 0,
          body: e.response!.data?.toString() ?? '',
        );
      }
      return DniHttpResponse(statusCode: 0, body: e.message ?? '');
    }
  }
}
