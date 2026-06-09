import '../domain/extraction/extracted_fields.dart';
import '../domain/extraction/field_extractor.dart';

class StateCivilExtractor extends FieldExtractor {
  const StateCivilExtractor();

  static final RegExp _label = RegExp(r'EST[A-Z\.]*\s*CIVIL|^ESTADO$');
  static final RegExp _inline =
      RegExp(r'EST[A-Z\.]*[ \t]*CIVIL[ \t]*:?[ \t]+([A-ZÁÉÍÓÚÑ]+)\b');
  static const Map<String, String> _canonical = {
    'SOLTERO': 'SOLTERO',
    'SOLTERA': 'SOLTERO',
    'CASADO': 'CASADO',
    'CASADA': 'CASADO',
    'DIVORCIADO': 'DIVORCIADO',
    'DIVORCIADA': 'DIVORCIADO',
    'VIUDO': 'VIUDO',
    'VIUDA': 'VIUDO',
    'CONVIVIENTE': 'CONVIVIENTE',
  };
  static const Map<String, String> _initials = {
    'S': 'SOLTERO',
    'C': 'CASADO',
    'D': 'DIVORCIADO',
    'V': 'VIUDO',
    'CV': 'CONVIVIENTE',
  };

  @override
  ExtractedFields extract(String recognizedText) {
    final upper = recognizedText.toUpperCase();
    final inlineMatch = _inline.firstMatch(upper);
    if (inlineMatch != null) {
      final canonical = _toCanonical(inlineMatch.group(1)) ??
          _toInitial(inlineMatch.group(1));
      if (canonical != null) return ExtractedFields(stateCivil: canonical);
    }
    final lines = upper.split('\n').map((l) => l.trim()).toList();

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!_label.hasMatch(line)) continue;
      for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
        final next = lines[j].trim();
        if (next.isEmpty) continue;
        final canonical = _toCanonical(next) ?? _toInitial(next);
        if (canonical != null) return ExtractedFields(stateCivil: canonical);
        break;
      }
    }

    for (var i = 0; i < lines.length; i++) {
      if (!_label.hasMatch(lines[i])) continue;
      for (var j = i - 1; j >= 0 && j >= i - 2; j--) {
        final prev = lines[j].trim();
        if (prev.isEmpty) continue;
        final canonical = _toCanonical(prev) ?? _toInitial(prev);
        if (canonical != null) return ExtractedFields(stateCivil: canonical);
      }
    }

    for (final line in lines) {
      if (line.isEmpty) continue;
      final canonical = _toCanonical(line);
      if (canonical != null) return ExtractedFields(stateCivil: canonical);
    }
    return ExtractedFields();
  }

  String? _toCanonical(String? raw) {
    if (raw == null) return null;
    final normalized = _stripDiacritics(raw.trim());
    return _canonical[normalized];
  }

  String? _toInitial(String? raw) {
    if (raw == null) return null;
    final normalized = _stripDiacritics(raw.trim());
    if (normalized.length > 2) return null;
    return _initials[normalized];
  }

  String _stripDiacritics(String value) {
    return value
        .replaceAll(RegExp(r'[ÁÀÄÂÃ]'), 'A')
        .replaceAll(RegExp(r'[ÉÈËÊ]'), 'E')
        .replaceAll(RegExp(r'[ÍÌÏÎ]'), 'I')
        .replaceAll(RegExp(r'[ÓÒÖÔÕ]'), 'O')
        .replaceAll(RegExp(r'[ÚÙÜÛ]'), 'U')
        .replaceAll('Ñ', 'N');
  }
}
