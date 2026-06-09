import 'dart:convert';

import 'package:dni_peru_ocr/src/lookup/http/dni_http_client.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_data.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_lookup_result.dart';
import 'package:dni_peru_ocr/src/lookup/services/dni_lookup_service.dart';

/// Resolves DNI data from a ReniecSunat-compatible backend.
///
/// Endpoint: `GET {baseUrl}/api/v1/dni/{dni}`
/// Placeholder `"-"` values in optional fields are preserved verbatim.
final class ReniecSunatLookupService implements DniLookupService {
  const ReniecSunatLookupService({
    required this.baseUrl,
    required this.client,
    this.extraHeaders,
    this.includeRaw = false,
  });

  final String baseUrl;
  final DniHttpClient client;
  final Map<String, String>? extraHeaders;
  final bool includeRaw;

  @override
  Future<DniLookupResult> lookup(String dni) async {
    final uri = Uri.parse('$baseUrl/api/v1/dni/$dni');

    try {
      final response = await client.get(
        uri,
        headers: extraHeaders,
      );
      final statusCode = response.statusCode;

      if (statusCode == 404) {
        return const DniLookupNotFound();
      }

      if (statusCode == 401 || statusCode == 403) {
        return const DniLookupInvalidToken();
      }

      if (statusCode == 429) {
        return const DniLookupRateLimited();
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

      final apellidoPaterno = (json['apellidoPaterno'] as String?) ?? '';
      final apellidoMaterno = (json['apellidoMaterno'] as String?) ?? '';
      final nombres = (json['nombres'] as String?) ?? '';
      final nombreCompleto =
          (json['nombreCompleto'] as String?) ??
          '$apellidoPaterno $apellidoMaterno $nombres'.trim();

      return DniLookupSuccess(
        DniData(
          dni: (json['dni'] as String?) ?? dni,
          nombres: nombres,
          apellidoPaterno: apellidoPaterno,
          apellidoMaterno: apellidoMaterno,
          nombreCompleto: nombreCompleto,
          ubigeo: json['ubigeo'] as String?,
          departamento: json['departamento'] as String?,
          provincia: json['provincia'] as String?,
          distrito: json['distrito'] as String?,
          rawSource: 'reniec-sunat',
          raw: includeRaw ? json : null,
        ),
      );
    } catch (e) {
      return DniLookupNetworkError(cause: e.toString());
    }
  }
}
