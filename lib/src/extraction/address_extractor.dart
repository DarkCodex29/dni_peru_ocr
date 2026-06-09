import '../data/address_noise_filter.dart';
import '../domain/extraction/extracted_fields.dart';
import '../domain/extraction/field_extractor.dart';

class AddressExtractor extends FieldExtractor {
  const AddressExtractor();

  static final RegExp _label = RegExp(r'DIRECCI[ÓO]N|DOMICILIO');
  static final RegExp _knownLabel = RegExp(
    r'SEXO|NACIONALIDAD|DEPARTAMENTO|PROVINCIA|DISTRITO|UBIGEO'
    r'|DONACI[ÓO]N|CONSTANCIA|GRUPO|JEFE|FECHA|SANGUINEO',
  );

  static final RegExp _streetAnchor = RegExp(
    r'^(URB\.?|AV\.?|JR\.?|JIRON|CALLE|PSJE\.?|PASAJE|MZ\.?|LT\.?|'
    r'AAHH\.?|ASOC\.?|COOP\.?|PJ\.?|CAR\.?|CARRETERA|CC\.?|PROL\.?|'
    r'PROLONGACI[OÓ]N|AVENIDA)\b',
  );

  @override
  ExtractedFields extract(String recognizedText) {
    final upper = recognizedText.toUpperCase();
    final lines = upper.split('\n').map((l) => l.trim()).toList();

    for (var i = 0; i < lines.length; i++) {
      if (!_label.hasMatch(lines[i])) continue;
      for (var j = i + 1; j < lines.length && j <= i + 3; j++) {
        final candidate = lines[j].trim();
        if (candidate.isEmpty) continue;
        if (_knownLabel.hasMatch(candidate)) break;
        final cleaned = AddressNoiseFilter.cleanAddressLine(candidate);
        if (cleaned != null && cleaned.isNotEmpty) {
          return ExtractedFields(address: cleaned);
        }
      }
    }

    for (final line in lines) {
      if (line.isEmpty) continue;
      if (!_streetAnchor.hasMatch(line)) continue;
      if (_knownLabel.hasMatch(line)) continue;
      final cleaned = AddressNoiseFilter.cleanAddressLine(line);
      if (cleaned != null && cleaned.isNotEmpty) {
        return ExtractedFields(address: cleaned);
      }
    }
    return ExtractedFields();
  }
}
