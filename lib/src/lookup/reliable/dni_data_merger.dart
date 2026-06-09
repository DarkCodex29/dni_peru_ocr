import 'package:dni_peru_ocr/src/domain/extraction/dni_field.dart';
import 'package:dni_peru_ocr/src/domain/extraction/dni_fields.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_data.dart';

final class DniDataMerger {
  const DniDataMerger();

  DniData merge({
    required DniData ocr,
    required DniData reniec,
    DniFields? fields,
  }) {
    final nombres =
        reniec.nombres.trim().isNotEmpty ? reniec.nombres : ocr.nombres;
    final apellidoPaterno = reniec.apellidoPaterno.trim().isNotEmpty
        ? reniec.apellidoPaterno
        : ocr.apellidoPaterno;
    final apellidoMaterno = reniec.apellidoMaterno.trim().isNotEmpty
        ? reniec.apellidoMaterno
        : ocr.apellidoMaterno;
    final nombreCompleto = reniec.nombreCompleto.trim().isNotEmpty
        ? reniec.nombreCompleto
        : ocr.nombreCompleto;

    final ubigeo = _mergeOptional(reniec.ubigeo, ocr.ubigeo);
    final departamento =
        _mergeOptional(reniec.departamento, ocr.departamento);
    final provincia = _mergeOptional(reniec.provincia, ocr.provincia);
    final distrito = _mergeOptional(reniec.distrito, ocr.distrito);

    if (fields == null || fields.length == DniField.values.length) {
      return DniData(
        dni: ocr.dni,
        nombres: nombres,
        apellidoPaterno: apellidoPaterno,
        apellidoMaterno: apellidoMaterno,
        nombreCompleto: nombreCompleto,
        ubigeo: ubigeo,
        departamento: departamento,
        provincia: provincia,
        distrito: distrito,
        rawSource: null,
        raw: reniec.raw ?? ocr.raw,
      );
    }

    final hasAnyNameField = fields.contains(DniField.firstName) ||
        fields.contains(DniField.lastName) ||
        fields.contains(DniField.secondLastName);

    return DniData(
      dni: ocr.dni,
      nombres: fields.contains(DniField.firstName) ? nombres : '',
      apellidoPaterno:
          fields.contains(DniField.lastName) ? apellidoPaterno : '',
      apellidoMaterno:
          fields.contains(DniField.secondLastName) ? apellidoMaterno : '',
      nombreCompleto: hasAnyNameField ? nombreCompleto : '',
      ubigeo: fields.contains(DniField.department) ? ubigeo : null,
      departamento:
          fields.contains(DniField.department) ? departamento : null,
      provincia: fields.contains(DniField.province) ? provincia : null,
      distrito: fields.contains(DniField.district) ? distrito : null,
      rawSource: null,
      raw: reniec.raw ?? ocr.raw,
    );
  }

  String? _mergeOptional(String? reniecField, String? ocrField) {
    if (reniecField != null && reniecField.trim().isNotEmpty) {
      return reniecField;
    }
    return ocrField;
  }
}
