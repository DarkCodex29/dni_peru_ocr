import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../data/ocr_field_extractor.dart';
import '../../data/ocr_field_normalizer.dart';
import 'ocr_field_strategy.dart';

/// Strategy that extracts OCR fields from heuristic text-block analysis.
///
/// Handles label-anchored name extraction, document number, dates, and sex.
/// Does NOT extract address — that is delegated to [AddressFieldStrategy].
/// Does NOT set [OcrExtractedFields.hasMrzData].
///
/// Returns `null` when no blocks are present. Returns an
/// [OcrExtractedFields] (possibly with all-null fields) otherwise —
/// the coordinator decides whether to use the output.
final class TextOcrFieldStrategy implements OcrFieldStrategy {
  const TextOcrFieldStrategy();

  @override
  OcrExtractedFields? extract(RecognizedText recognized) {
    if (recognized.blocks.isEmpty) return null;

    final result = OcrExtractedFields();
    _extractFromTextBlocks(recognized, result);

    // Return null only if truly nothing was found.
    final hasAnyField = result.documentNumber != null ||
        result.lastName != null ||
        result.secondLastName != null ||
        result.firstName != null ||
        result.dateOfBirth != null ||
        result.expirationDate != null ||
        result.sex != null;

    return hasAnyField ? result : null;
  }

  void _extractFromTextBlocks(
    RecognizedText recognized,
    OcrExtractedFields result,
  ) {
    final lines = <String>[];
    for (final block in recognized.blocks) {
      for (final line in block.text.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty && !_looksLikeMrzLine(trimmed)) {
          lines.add(trimmed);
        }
      }
    }

    for (int i = 0; i < lines.length; i++) {
      final upper = lines[i].toUpperCase();

      if (result.documentNumber == null) {
        final dniMatch = RegExp('DNI[/\\s]*(\\d{8})').firstMatch(upper);
        if (dniMatch != null) result.documentNumber = dniMatch.group(1);
      }

      _tryExtractNameByLabel(lines, i, result);
      _tryExtractDates(lines, i, result);

      if (result.sex == null &&
          (upper.contains('SEXO') || upper.contains('ESTADO C'))) {
        final sexMatch = RegExp('\\b([MF])\\b').firstMatch(upper);
        if (sexMatch != null) result.sex = sexMatch.group(1);
      }
    }

    // Pass 2: ordinal matching for two-column DNI layouts.
    if (result.lastName == null ||
        result.secondLastName == null ||
        result.firstName == null) {
      _extractNamesByOrdinal(lines, result);
    }
  }

  /// Collects name labels and person-name values in document order, then
  /// assigns them by ordinal: 1st label → 1st value, 2nd → 2nd, etc.
  void _extractNamesByOrdinal(
    List<String> lines,
    OcrExtractedFields result,
  ) {
    final labelOrder = <String>[];
    final namePool = <String>[];

    for (final line in lines) {
      final upper = line.toUpperCase().trim();
      if (upper.contains('PRIMER APEL') || upper.contains('PRMER APEL')) {
        if (!labelOrder.contains('lastName')) labelOrder.add('lastName');
      } else if (upper.contains('SEGUNDO APEL') ||
          upper.contains('SGUNDO APEL')) {
        if (!labelOrder.contains('secondLastName')) {
          labelOrder.add('secondLastName');
        }
      } else if (upper.contains('PRENOMBRES') ||
          upper.contains('PRE NOMBRE') ||
          upper.contains('PRE NOM')) {
        if (!labelOrder.contains('firstName')) labelOrder.add('firstName');
      } else if (_isPersonName(line.trim())) {
        namePool.add(line.trim().toUpperCase());
      }
    }

    for (int i = 0; i < labelOrder.length && i < namePool.length; i++) {
      final field = labelOrder[i];
      final name = OcrFieldNormalizer.normalizeForDisplay(namePool[i]);
      if (field == 'lastName') result.lastName ??= name;
      if (field == 'secondLastName') result.secondLastName ??= name;
      if (field == 'firstName') result.firstName ??= name;
    }
  }

  /// Returns true when a single OCR line looks like a MRZ line.
  bool _looksLikeMrzLine(String line) {
    final clean = line.replaceAll(' ', '');
    return clean.length >= 20 && '<'.allMatches(clean).length >= 3;
  }

  void _tryExtractNameByLabel(
    List<String> lines,
    int i,
    OcrExtractedFields result,
  ) {
    final upper = lines[i].toUpperCase();

    if (upper.contains('PRIMER APEL') || upper.contains('PRMER APEL')) {
      final value = _findNameNear(lines, i);
      if (value != null) result.lastName ??= value;
    }

    if (upper.contains('SEGUNDO APEL') || upper.contains('SGUNDO APEL')) {
      final value = _findNameNear(lines, i);
      if (value != null) result.secondLastName ??= value;
    }

    if (upper.contains('PRENOMBRES') ||
        upper.contains('PRE NOMBRE') ||
        upper.contains('PRE NOM')) {
      final value = _findNameNear(lines, i);
      if (value != null) result.firstName ??= value;
    }
  }

  String? _findNameNear(List<String> lines, int labelIdx) {
    if (labelIdx + 1 < lines.length) {
      final next = lines[labelIdx + 1].trim();
      if (_isPersonName(next)) {
        return OcrFieldNormalizer.normalizeForDisplay(next);
      }
    }
    if (labelIdx > 0) {
      final prev = lines[labelIdx - 1].trim();
      if (_isPersonName(prev)) {
        return OcrFieldNormalizer.normalizeForDisplay(prev);
      }
    }
    return null;
  }

  void _tryExtractDates(
    List<String> lines,
    int i,
    OcrExtractedFields result,
  ) {
    final line = lines[i];
    final upper = line.toUpperCase();
    final dateRegex = RegExp('(\\d{2})\\s+(\\d{2})\\s+(\\d{4})');
    final matches = dateRegex.allMatches(line).toList();
    if (matches.isEmpty) return;

    final context = i > 0 ? '${lines[i - 1].toUpperCase()} $upper' : upper;

    for (final match in matches) {
      final d = int.tryParse(match.group(1)!) ?? 0;
      final m = int.tryParse(match.group(2)!) ?? 0;
      final y = int.tryParse(match.group(3)!) ?? 0;
      if (y < 1950 || y > 2035 || m < 1 || m > 12 || d < 1 || d > 31) continue;

      final date = '${match.group(1)}/${match.group(2)}/${match.group(3)}';

      if (context.contains('NACIMIENTO')) {
        result.dateOfBirth = date;
      } else if (context.contains('CADUC')) {
        result.expirationDate = date;
      } else if (y < 2010 && result.dateOfBirth == null) {
        result.dateOfBirth = date;
      } else if (y > 2026 && result.expirationDate == null) {
        result.expirationDate = date;
      }
    }
  }

  bool _isPersonName(String text) {
    final clean = text.trim();
    if (clean.length < 2 || clean.length > 25) return false;
    if (clean != clean.toUpperCase()) return false;
    if (RegExp('[0-9<>/]').hasMatch(clean)) return false;
    if (!RegExp('^[A-ZÁÉÍÓÚÑ ]+\$').hasMatch(clean)) return false;

    // Reject text with too many consecutive consonants (corrupt OCR).
    if (RegExp('[BCDFGHJKLMNPQRSTVWXYZ]{4,}').hasMatch(clean)) return false;

    // Reject DNI labels.
    const forbidden = [
      'REPUBLICA',
      'PERU',
      'REGISTRO',
      'NACIONAL',
      'IDENTIFICACION',
      'ESTADO',
      'CIVIL',
      'DOCUMENTO',
      'IDENTIDAD',
      'DNI',
      'DUPLICADO',
      'FECHA',
      'INSCRIPCION',
      'EMISION',
      'CADUCIDAD',
      'NACIMIENTO',
      'SEXO',
      'UBIGEO',
      'PRIMER',
      'SEGUNDO',
      'APELLIDO',
      'APELLIDOS',
      'NOMBRES',
      'PRENOMBRES',
      'PRE',
      'NOMBRE',
    ];
    final words = clean.split(' ');
    for (final word in words) {
      for (final f in forbidden) {
        if (word == f) return false;
      }
    }

    return true;
  }
}
