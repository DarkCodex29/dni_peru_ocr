import '../domain/extraction/extracted_fields.dart';
import '../domain/extraction/field_extractor.dart';

class TarjetaExtractor extends FieldExtractor {
  const TarjetaExtractor();

  static final RegExp _label =
      RegExp(r'(N(RO|UMERO|\.|°)?\s*(DE\s*)?TARJETA|TARJETA)');
  static final RegExp _inline = RegExp(
    r'(N(?:RO|UMERO|\.|°)?\s*(?:DE\s*)?TARJETA|TARJETA)\s*:?\s*(\d{10})(?!\d)',
  );
  static final RegExp _ten = RegExp(r'(?<!\d)(\d{10})(?!\d)');

  @override
  ExtractedFields extract(String recognizedText) {
    final upper = recognizedText.toUpperCase();
    final inlineMatch = _inline.firstMatch(upper);
    if (inlineMatch != null) {
      return ExtractedFields(cardNumber: inlineMatch.group(2));
    }
    final lines = upper.split('\n').map((l) => l.trim()).toList();
    for (var i = 0; i < lines.length; i++) {
      if (!_label.hasMatch(lines[i])) continue;
      for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
        final next = lines[j].trim();
        if (next.isEmpty) continue;
        final tenMatch = _ten.firstMatch(next);
        if (tenMatch != null) {
          return ExtractedFields(cardNumber: tenMatch.group(1));
        }
        break;
      }
    }
    for (final line in lines) {
      if (!line.contains('EMISI')) continue;
      final tenMatch = _ten.firstMatch(line);
      if (tenMatch != null) {
        return ExtractedFields(cardNumber: tenMatch.group(1));
      }
    }
    return ExtractedFields();
  }
}
