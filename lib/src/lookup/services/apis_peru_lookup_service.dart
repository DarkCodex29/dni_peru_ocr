import 'dart:convert';

import 'package:dni_peru_ocr/src/lookup/http/dni_http_client.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_data.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_lookup_result.dart';
import 'package:dni_peru_ocr/src/lookup/services/dni_lookup_service.dart';

/// Resolves DNI data using the ApisPeru endpoint.
final class ApisPeruLookupService implements DniLookupService {
  const ApisPeruLookupService({
    required this.token,
    required this.client,
    this.baseUrl = 'https://dniruc.apisperu.com',
    this.includeRaw = false,
  });

  final String token;
  final DniHttpClient client;
  final String baseUrl;
  final bool includeRaw;

  @override
  Future<DniLookupResult> lookup(String dni) async {
    final uri = Uri.parse(
      '$baseUrl/api/v1/dni/$dni?token=$token',
    );

    try {
      final response = await client.get(uri);
      final statusCode = response.statusCode;

      if (statusCode == 429) {
        return const DniLookupRateLimited();
      }

      if (statusCode == 401 || statusCode == 403) {
        return const DniLookupInvalidToken();
      }

      if (statusCode == 500) {
        Map<String, dynamic>? json;
        try {
          json = jsonDecode(response.body) as Map<String, dynamic>;
        } catch (_) {
          return const DniLookupInvalidToken();
        }
        return DniLookupServerError(statusCode: 500, body: jsonEncode(json));
      }

      if (statusCode != 200) {
        return DniLookupServerError(
          statusCode: statusCode,
          body: response.body,
        );
      }

      Map<String, dynamic> json;
      try {
        json = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        return DniLookupServerError(
          statusCode: 200,
          body: response.body.length > 200
              ? response.body.substring(0, 200)
              : response.body,
        );
      }

      final success = json['success'];
      if (success == false) {
        return const DniLookupNotFound();
      }

      final apellidoPaterno = (json['apellidoPaterno'] as String?) ?? '';
      final apellidoMaterno = (json['apellidoMaterno'] as String?) ?? '';
      final nombres = (json['nombres'] as String?) ?? '';
      final nombreCompleto =
          '$apellidoPaterno $apellidoMaterno $nombres'.trim();

      return DniLookupSuccess(
        DniData(
          dni: (json['dni'] as String?) ?? dni,
          nombres: nombres,
          apellidoPaterno: apellidoPaterno,
          apellidoMaterno: apellidoMaterno,
          nombreCompleto:
              (json['nombreCompleto'] as String?) ?? nombreCompleto,
          rawSource: 'apisperu',
          raw: includeRaw ? json : null,
        ),
      );
    } catch (e) {
      return DniLookupNetworkError(cause: e.toString());
    }
  }
}
