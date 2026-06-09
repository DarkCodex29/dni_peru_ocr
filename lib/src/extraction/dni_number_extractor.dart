import '../domain/extraction/extracted_fields.dart';
import '../domain/extraction/field_extractor.dart';

class DniNumberExtractor extends FieldExtractor {
  const DniNumberExtractor();

  static final RegExp _labeled = RegExp(r'DNI\s*:?\s*(\d{8})\b');
  static final RegExp _isolated = RegExp(r'(?<!\d)(\d{8})(?!\d)');

  @override
  ExtractedFields extract(String recognizedText) {
    final upper = recognizedText.toUpperCase();
    final labeledMatch = _labeled.firstMatch(upper);
    if (labeledMatch != null) {
      return ExtractedFields(documentNumber: labeledMatch.group(1));
    }
    final isolatedMatch = _isolated.firstMatch(upper);
    if (isolatedMatch != null) {
      return ExtractedFields(documentNumber: isolatedMatch.group(1));
    }
    return ExtractedFields();
  }
}
