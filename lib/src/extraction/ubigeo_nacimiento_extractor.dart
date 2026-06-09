import '../domain/extraction/extracted_fields.dart';
import '../domain/extraction/field_extractor.dart';

class UbigeoNacimientoExtractor extends FieldExtractor {
  const UbigeoNacimientoExtractor();

  static final RegExp _label = RegExp(
    r'UB[A-Z\.]*\s*(?:DE\s+)?NACIMIENTO|NACIMIENTO[^\n]*UBIGEO',
  );
  static final RegExp _inline = RegExp(
    r'UB[A-Z\.]*\s*(?:DE\s+)?NACIMIENTO\s*:?\s*(\d{6})(?!\d)',
  );
  static final RegExp _six = RegExp(r'^(\d{6})$');
  static final RegExp _datePattern = RegExp(r'^\d{2}\s+\d{2}\s+\d{4}$');

  @override
  ExtractedFields extract(String recognizedText) {
    final upper = recognizedText.toUpperCase();
    final inlineMatch = _inline.firstMatch(upper);
    if (inlineMatch != null) {
      return ExtractedFields(birthUbigeoCode: inlineMatch.group(1));
    }
    final lines = upper.split('\n').map((l) => l.trim()).toList();
    for (var i = 0; i < lines.length; i++) {
      if (!_label.hasMatch(lines[i])) continue;
      for (var j = i + 1; j < lines.length && j <= i + 3; j++) {
        final next = lines[j].trim();
        if (next.isEmpty) continue;
        if (_datePattern.hasMatch(next)) continue;
        final match = _six.firstMatch(next);
        if (match != null) {
          return ExtractedFields(birthUbigeoCode: match.group(1));
        }
        break;
      }
    }
    return ExtractedFields();
  }
}
