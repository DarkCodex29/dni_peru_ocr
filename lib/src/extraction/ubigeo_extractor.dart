import '../domain/extraction/extracted_fields.dart';
import '../domain/extraction/field_extractor.dart';

class UbigeoExtractor extends FieldExtractor {
  const UbigeoExtractor();

  static final RegExp _slashTriple = RegExp(
    r'([A-ZÁÉÍÓÚÑ ]{2,})?\s*/\s*([A-ZÁÉÍÓÚÑ ]{2,})\s*/\s*([A-ZÁÉÍÓÚÑ ]{2,})',
  );
  static final RegExp _labelLike = RegExp(
    r'^(DEPARTAMENT[OE]|PR[OE]VINCIA|DISTRIT[OQ]|DOMICILIO|DIRECCI[OÓ]N)$',
  );
  static final RegExp _backgroundWatermark = RegExp(
    r'RENIEC|REP[UÚÙÛŨŬ]BLICA',
  );

  @override
  ExtractedFields extract(String recognizedText) {
    final upper = recognizedText.toUpperCase();
    final lines = upper.split('\n').map((l) => l.trim()).toList();

    final slashMatch = _findUbigeoSlash(lines);
    if (slashMatch != null) return slashMatch;

    final columnar = _findColumnarBlock(lines);
    if (columnar != null) return columnar;

    String? department;
    String? province;
    String? district;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains('DEPARTAMENTO') && department == null) {
        department = _nextValue(lines, i);
      }
      if (line.contains('PROVINCIA') && province == null) {
        province = _nextValue(lines, i);
      }
      if (line.contains('DISTRITO') && district == null) {
        district = _nextValue(lines, i);
      }
    }
    return ExtractedFields(
      department: department,
      province: province,
      district: district,
    );
  }

  ExtractedFields? _findColumnarBlock(List<String> lines) {
    for (var i = 0; i + 5 < lines.length; i++) {
      final l0 = lines[i].trim();
      final l1 = lines[i + 1].trim();
      final l2 = lines[i + 2].trim();
      if (!l0.contains('DEPARTAMENTO')) continue;
      if (!l1.contains('PROVINCIA')) continue;
      if (!l2.contains('DISTRITO')) continue;
      final values = <String>[];
      for (var j = i + 3; j < lines.length && values.length < 3; j++) {
        final v = lines[j].trim();
        if (v.isEmpty) continue;
        if (_isLabelToken(v)) continue;
        values.add(v);
      }
      if (values.length < 3) continue;
      return ExtractedFields(
        department: values[0],
        province: values[1],
        district: values[2],
      );
    }
    return null;
  }

  ExtractedFields? _findUbigeoSlash(List<String> lines) {
    for (final line in lines) {
      if (_backgroundWatermark.hasMatch(line)) continue;
      final match = _slashTriple.firstMatch(line);
      if (match == null) continue;
      final dep = match.group(1)?.trim();
      final prov = match.group(2)?.trim();
      final dist = match.group(3)?.trim();
      if (prov == null || dist == null) continue;
      if (_isLabelToken(dep) || _isLabelToken(prov) || _isLabelToken(dist)) {
        continue;
      }
      return ExtractedFields(
        department: dep != null && dep.isNotEmpty ? dep : null,
        province: prov,
        district: dist,
      );
    }
    return null;
  }

  bool _isLabelToken(String? token) {
    if (token == null) return false;
    return _labelLike.hasMatch(token.trim());
  }

  String? _nextValue(List<String> lines, int fromIndex) {
    for (var j = fromIndex + 1; j < lines.length && j <= fromIndex + 2; j++) {
      final candidate = lines[j].trim();
      if (candidate.isEmpty) continue;
      if (_isLabelToken(candidate)) continue;
      if (RegExp(r'^[A-ZÁÉÍÓÚÑ ]{2,}$').hasMatch(candidate)) {
        return candidate;
      }
    }
    return null;
  }
}
