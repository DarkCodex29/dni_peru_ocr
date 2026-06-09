import '../domain/extraction/extracted_fields.dart';
import '../domain/extraction/field_extractor.dart';

class GivenNamesExtractor extends FieldExtractor {
  const GivenNamesExtractor();

  static final RegExp _label = RegExp(
    r'PRE\s?N[O]?MBRES?|PR[I]?MER\s+NOMBRES?|^NOMBRES\b|DENOMBRES|^PRENMBRES?\b',
    multiLine: true,
  );

  static final RegExp _validName =
      RegExp(r'^[A-ZÁÉÍÓÚÑ]{2,}(\s[A-ZÁÉÍÓÚÑ]+)*$');

  static final RegExp _anyKnownLabel = RegExp(
    r'PRIMER\s+APELLIDO|APELLIDO\s+PATERNO'
    r'|SEGUNDO\s+APELLIDO|APELLIDO\s+MATERNO'
    r'|^APELLIDOS\s*:?\s*$'
    r'|SEXO|NACIONALIDAD|FECHA|DNI|CUI|ESTADO\s+CIVIL'
    r'|REP[UÚÙÛŨŬ]BLICA|DOCUMENTO|REGISTRO|IDENTIDAD|IDENTIFICACI[ÓO]N'
    r'|DUPLICADO|RENIEC|NRO[\s\.]+TARJETA|TARJETA'
    r'|DONACI[ÓO]N|CONSTANCIA|SUFRAGIO|GRUPO|VOTACI[ÓO]N|UBIGEO'
    r'|DEPARTAMENTO|PROVINCIA|DISTRITO|DIRECCI[ÓO]N|DOMICILIO',
  );

  @override
  ExtractedFields extract(String recognizedText) {
    final upper = recognizedText.toUpperCase();
    final lines = upper.split('\n').map((l) => l.trim()).toList();

    for (var i = 0; i < lines.length; i++) {
      if (_label.hasMatch(lines[i])) {
        final value = _nextValidName(lines, i);
        if (value != null) return ExtractedFields(firstName: value);
      }
    }

    for (var i = 0; i < lines.length; i++) {
      if (!_label.hasMatch(lines[i])) continue;
      final value = _previousValidName(lines, i);
      if (value != null) return ExtractedFields(firstName: value);
    }
    return ExtractedFields();
  }

  String? _nextValidName(List<String> lines, int fromIndex) {
    for (var j = fromIndex + 1; j < lines.length && j <= fromIndex + 2; j++) {
      final candidate = lines[j].trim();
      if (candidate.isEmpty) continue;
      if (_anyKnownLabel.hasMatch(candidate)) return null;
      if (_validName.hasMatch(candidate)) return candidate;
    }
    return null;
  }

  String? _previousValidName(List<String> lines, int fromIndex) {
    for (var j = fromIndex - 1; j >= 0 && j >= fromIndex - 2; j--) {
      final candidate = lines[j].trim();
      if (candidate.isEmpty) continue;
      if (_anyKnownLabel.hasMatch(candidate)) continue;
      if (_validName.hasMatch(candidate)) return candidate;
    }
    return null;
  }
}
