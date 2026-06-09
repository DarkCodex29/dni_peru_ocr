import '../domain/extraction/extracted_fields.dart';
import '../domain/extraction/field_extractor.dart';

class GrupoVotacionExtractor extends FieldExtractor {
  const GrupoVotacionExtractor();

  static final RegExp _label = RegExp(
    r'GRUPO(?:\s+DE)?\s+V[OL]TAC[IL][OÓ]N|GRUPO\s+VOT[A-Z]*[OÓ]N|^GV$',
  );
  static final RegExp _inline = RegExp(
    r'(?:GRUPO(?:\s+DE)?\s+V[OL]TAC[IL][OÓ]N|GRUPO\s+VOT[A-Z]*[OÓ]N|GV)'
    r'\s*:?\s*(\d{6})(?!\d)',
  );
  static final RegExp _six = RegExp(r'^(\d{6})$');

  @override
  ExtractedFields extract(String recognizedText) {
    final upper = recognizedText.toUpperCase();
    final inlineMatch = _inline.firstMatch(upper);
    if (inlineMatch != null) {
      return ExtractedFields(votingGroup: inlineMatch.group(1));
    }
    final lines = upper.split('\n').map((l) => l.trim()).toList();
    for (var i = 0; i < lines.length; i++) {
      if (!_label.hasMatch(lines[i])) continue;
      for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
        final next = lines[j].trim();
        if (next.isEmpty) continue;
        final match = _six.firstMatch(next);
        if (match != null) {
          return ExtractedFields(votingGroup: match.group(1));
        }
        break;
      }
    }
    return ExtractedFields();
  }
}
