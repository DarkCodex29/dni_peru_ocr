import '../domain/extraction/extracted_fields.dart';
import '../domain/extraction/field_extractor.dart';

class SurnameExtractor extends FieldExtractor {
  const SurnameExtractor();

  static final RegExp _paternalLabel = RegExp(
    r'PR[I]?MER\s+APELLIDO|APELLIDO\s+PATERNO',
  );
  static final RegExp _maternalLabel = RegExp(
    r'S[E]?GUNDO[.\s]+APELLIDO|APELLIDO\s+MATERNO',
  );
  static final RegExp _combinedLabel = RegExp(r'^APELLIDOS\s*:?\s*$');

  static final RegExp _validSurname =
      RegExp(r'^[A-ZÁÉÍÓÚÑ]{2,}(\s[A-ZÁÉÍÓÚÑ]+)*$');

  static final RegExp _anyKnownLabel = RegExp(
    r'PR[I]?MER\s+APELLIDO|APELLIDO\s+PATERNO'
    r'|S[E]?GUNDO[.\s]+APELLIDO|APELLIDO\s+MATERNO'
    r'|^APELLIDOS\s*:?\s*$'
    r'|PRE\s?NOMBRES?|NOMBRES'
    r'|SEXO|NACIONALIDAD|FECHA|DNI|CUI|ESTADO\s+CIVIL'
    r'|REP[UÚÙÛŨŬ]BLICA|DOCUMENTO|REGISTRO|IDENTIDAD|IDENTIFICACI[ÓO]N'
    r'|DUPLICADO|RENIEC|NRO[\s\.]+TARJETA|TARJETA',
  );

  @override
  ExtractedFields extract(String recognizedText) {
    final upper = recognizedText.toUpperCase();
    final lines = upper.split('\n').map((l) => l.trim()).toList();

    final fromSeparated = _extractFromSeparatedLabels(lines);
    if (fromSeparated.lastName != null || fromSeparated.secondLastName != null) {
      return fromSeparated;
    }

    final fromInverted = _extractFromInvertedLayout(lines);
    if (fromInverted.lastName != null) {
      return fromInverted;
    }

    return _extractFromCombinedLabel(lines);
  }

  ExtractedFields _extractFromSeparatedLabels(List<String> lines) {
    String? paternal;
    String? maternal;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (paternal == null && _paternalLabel.hasMatch(line)) {
        paternal = _nextValidSurname(lines, i);
      }
      if (maternal == null && _maternalLabel.hasMatch(line)) {
        maternal = _nextValidSurname(lines, i);
      }
    }
    return ExtractedFields(
      lastName: paternal,
      secondLastName: maternal,
    );
  }

  ExtractedFields _extractFromCombinedLabel(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      if (!_combinedLabel.hasMatch(lines[i])) continue;
      for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
        final candidate = lines[j].trim();
        if (candidate.isEmpty) continue;
        if (_anyKnownLabel.hasMatch(candidate)) return ExtractedFields();
        if (!_validSurname.hasMatch(candidate)) continue;
        final parts = candidate.split(' ');
        if (parts.length == 1) {
          return ExtractedFields(lastName: parts.first);
        }
        return ExtractedFields(
          lastName: parts.first,
          secondLastName: parts.sublist(1).join(' '),
        );
      }
    }
    return ExtractedFields();
  }

  ExtractedFields _extractFromInvertedLayout(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      if (!_combinedLabel.hasMatch(lines[i])) continue;
      for (var j = i - 1; j >= 0 && j >= i - 2; j--) {
        final candidate = lines[j].trim();
        if (candidate.isEmpty) continue;
        if (_anyKnownLabel.hasMatch(candidate)) continue;
        if (!_validSurname.hasMatch(candidate)) continue;
        final parts = candidate.split(' ');
        if (parts.length == 1) {
          return ExtractedFields(lastName: parts.first);
        }
        return ExtractedFields(
          lastName: parts.first,
          secondLastName: parts.sublist(1).join(' '),
        );
      }
    }
    return ExtractedFields();
  }

  String? _nextValidSurname(List<String> lines, int fromIndex) {
    for (var j = fromIndex + 1; j < lines.length && j <= fromIndex + 2; j++) {
      final candidate = lines[j].trim();
      if (candidate.isEmpty) continue;
      if (_anyKnownLabel.hasMatch(candidate)) return null;
      if (_validSurname.hasMatch(candidate)) return candidate;
    }
    return null;
  }
}
