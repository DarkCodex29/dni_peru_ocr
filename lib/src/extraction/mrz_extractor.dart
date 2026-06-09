import 'package:mrz_parser/mrz_parser.dart';

import '../domain/extraction/extracted_fields.dart';
import '../domain/extraction/field_extractor.dart';

class MrzExtractor extends FieldExtractor {
  const MrzExtractor();

  @override
  ExtractedFields extract(String recognizedText) {
    final lines = _findMrzLines(recognizedText);
    if (lines.length < 3) return ExtractedFields();
    try {
      final parsed = MRZParser.parse(lines);
      return ExtractedFields(
        documentNumber: parsed.documentNumber,
        firstName: parsed.givenNames,
        lastName: _firstSurname(parsed.surnames),
        secondLastName: _secondSurname(parsed.surnames),
        dateOfBirth: _formatDate(parsed.birthDate),
        expirationDate: _formatDate(parsed.expiryDate),
        sex: _normalizeSex(parsed.sex.toString().split('.').last),
        nationality: parsed.nationalityCountryCode,
      );
    } catch (_) {
      return ExtractedFields();
    }
  }

  List<String> _findMrzLines(String text) {
    final cleaned = text.split('\n').map((l) {
      return l
          .replaceAll(' ', '')
          .replaceAll('K', '<')
          .replaceAll('k', '<')
          .replaceAll('«', '<')
          .trim();
    });
    return cleaned
        .where((l) => l.length >= 25 && l.contains('<') && _looksLikeMrz(l))
        .toList();
  }

  bool _looksLikeMrz(String line) {
    final fillerCount = '<'.allMatches(line).length;
    return fillerCount >= 3;
  }

  String? _firstSurname(String surnames) {
    final parts = surnames.split(' ');
    if (parts.isEmpty) return null;
    return parts.first.isEmpty ? null : parts.first;
  }

  String? _secondSurname(String surnames) {
    final parts = surnames.split(' ');
    if (parts.length < 2) return null;
    return parts.sublist(1).join(' ');
  }

  String? _formatDate(DateTime? d) {
    if (d == null) return null;
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return '$dd/$mm/$yyyy';
  }

  String? _normalizeSex(String raw) {
    final v = raw.trim().toUpperCase();
    if (v == 'M' || v == 'MALE') return 'M';
    if (v == 'F' || v == 'FEMALE') return 'F';
    return null;
  }
}
