import '../domain/extraction/extracted_fields.dart';
import '../domain/extraction/field_extractor.dart';

class SexExtractor extends FieldExtractor {
  const SexExtractor();

  static final RegExp _inline = RegExp(r'SEXO?\s*:?\s*([MF])\b');
  static final RegExp _word = RegExp(r'(MASCULINO|FEMENINO)\b');
  static final RegExp _horizontal =
      RegExp(r'\b([MF])\s+(?:PER\b|PERUAN[OA]\b)');
  static final RegExp _sexLabelFuzzy = RegExp(r'^S[E]?[XVRO]+[OEAi]?\b');

  @override
  ExtractedFields extract(String recognizedText) {
    final upper = recognizedText.toUpperCase();
    final inlineMatch = _inline.firstMatch(upper);
    if (inlineMatch != null) {
      return ExtractedFields(sex: inlineMatch.group(1));
    }
    final lines = upper.split('\n').map((l) => l.trim()).toList();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (RegExp(r'^SEX[O]?\b').hasMatch(line)) {
        for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
          final next = lines[j].trim();
          if (next.isEmpty) continue;
          if (next == 'M' || next == 'F') {
            return ExtractedFields(sex: next);
          }
          if (next == 'MASCULINO') return ExtractedFields(sex: 'M');
          if (next == 'FEMENINO') return ExtractedFields(sex: 'F');
          break;
        }
      }
    }
    final horizontalMatch = _horizontal.firstMatch(upper);
    if (horizontalMatch != null) {
      return ExtractedFields(sex: horizontalMatch.group(1));
    }
    final wordMatch = _word.firstMatch(upper);
    if (wordMatch != null) {
      return ExtractedFields(
        sex: wordMatch.group(1)!.startsWith('M') ? 'M' : 'F',
      );
    }

    for (var i = 1; i < lines.length; i++) {
      final value = lines[i].trim();
      if (value != 'M' && value != 'F') continue;
      for (var j = i - 1; j >= 0 && j >= i - 3; j--) {
        final prev = lines[j].trim();
        if (prev.isEmpty) continue;
        if (_sexLabelFuzzy.hasMatch(prev)) {
          return ExtractedFields(sex: value);
        }
        break;
      }
    }

    return ExtractedFields();
  }
}
