import '../domain/extraction/extracted_fields.dart';
import '../domain/extraction/field_extractor.dart';

class NationalityExtractor extends FieldExtractor {
  const NationalityExtractor();

  static final RegExp _label = RegExp(r'NACIONALIDAD');
  static final RegExp _peruShort = RegExp(r'^PER\b');
  static final RegExp _peruWord = RegExp(r'PERUANA');
  static final RegExp _horizontal = RegExp(r'\b[MF]\s+(?:PER\b|PERUAN[OA]\b)');
  static final RegExp _mrzStart = RegExp(r'\bI\s*<\s*PER\b');
  static final RegExp _mrzTrailing = RegExp(r'PER\s*<{2,}');
  static final RegExp _peruvianHeader = RegExp(
    r'REP[UÚÙÛŨŬ]BLICA\s+DEL\s+PER[UÚÙÛŨŬ]'
    r'|REGISTRO\s+NACIONAL\s+DE\s+IDENTIFICACI[ÓO]N',
  );

  @override
  ExtractedFields extract(String recognizedText) {
    final upper = recognizedText.toUpperCase();
    if (_horizontal.hasMatch(upper) ||
        _mrzStart.hasMatch(upper) ||
        _mrzTrailing.hasMatch(upper) ||
        _peruvianHeader.hasMatch(upper)) {
      return ExtractedFields(nationality: 'PERUANA');
    }
    if (!_label.hasMatch(upper)) return ExtractedFields();

    if (_peruWord.hasMatch(upper)) {
      return ExtractedFields(nationality: 'PERUANA');
    }
    final lines = upper.split('\n').map((l) => l.trim()).toList();
    for (var i = 0; i < lines.length; i++) {
      if (_label.hasMatch(lines[i])) {
        for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
          final next = lines[j].trim();
          if (_peruShort.hasMatch(next)) {
            return ExtractedFields(nationality: 'PERUANA');
          }
          if (_peruWord.hasMatch(next)) {
            return ExtractedFields(nationality: 'PERUANA');
          }
        }
      }
    }
    return ExtractedFields();
  }
}
