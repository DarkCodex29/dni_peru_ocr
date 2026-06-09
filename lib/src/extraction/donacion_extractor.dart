import '../domain/extraction/extracted_fields.dart';
import '../domain/extraction/field_extractor.dart';

class DonacionExtractor extends FieldExtractor {
  const DonacionExtractor();

  static final RegExp _label = RegExp(r'DONACI[OÓ]N');
  static final RegExp _inline =
      RegExp(r'DONACI[OÓ]N(?:\s+DE\s+[OÓ]RGANOS)?\s*:?\s*(SI|NO|SÍ)\b');

  @override
  ExtractedFields extract(String recognizedText) {
    final upper = recognizedText.toUpperCase();
    final inlineMatch = _inline.firstMatch(upper);
    if (inlineMatch != null) {
      return ExtractedFields(organDonor: _normalize(inlineMatch.group(1)!));
    }
    final lines = upper.split('\n').map((l) => l.trim()).toList();
    for (var i = 0; i < lines.length; i++) {
      if (!_label.hasMatch(lines[i])) continue;
      for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
        final next = lines[j].trim();
        if (next.isEmpty) continue;
        if (next == 'SI' || next == 'SÍ') {
          return ExtractedFields(organDonor: 'SI');
        }
        if (next == 'NO') return ExtractedFields(organDonor: 'NO');
        break;
      }
    }
    return ExtractedFields();
  }

  String _normalize(String value) {
    return value == 'SÍ' ? 'SI' : value;
  }
}
