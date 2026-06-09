import '../domain/extraction/extracted_fields.dart';
import '../domain/extraction/field_extractor.dart';

class DateFieldExtractor extends FieldExtractor {
  const DateFieldExtractor();

  static final RegExp _datePattern =
      RegExp(r'(\d{2})\s+(\d{2})\s+(\d{4})');

  @override
  ExtractedFields extract(String recognizedText) {
    final upper = recognizedText.toUpperCase();
    final lines = upper.split('\n').map((l) => l.trim()).toList();

    String? birth;
    String? expiration;
    String? emission;
    String? inscription;
    final assigned = <String>{};

    bool assign(String formatted, String field) {
      if (assigned.contains(formatted)) return false;
      switch (field) {
        case 'inscription':
          if (inscription != null) return false;
          inscription = formatted;
        case 'emission':
          if (emission != null) return false;
          emission = formatted;
        case 'expiration':
          if (expiration != null) return false;
          expiration = formatted;
        case 'birth':
          if (birth != null) return false;
          birth = formatted;
      }
      assigned.add(formatted);
      return true;
    }

    for (var i = 0; i < lines.length; i++) {
      final matches = _datePattern.allMatches(lines[i]).toList();
      if (matches.isEmpty) continue;
      final context = _buildContextBackward(lines, i);
      for (final match in matches) {
        if (!_isValidMatch(match)) continue;
        final formatted = _formatMatch(match);
        if (_isInscriptionContext(context) && assign(formatted, 'inscription')) {
          continue;
        }
        if (_isEmissionContext(context) && assign(formatted, 'emission')) {
          continue;
        }
        if (_isExpirationContext(context) && assign(formatted, 'expiration')) {
          continue;
        }
        if (_isBirthContext(context)) assign(formatted, 'birth');
      }
    }

    for (var i = 0; i < lines.length; i++) {
      final matches = _datePattern.allMatches(lines[i]).toList();
      if (matches.isEmpty) continue;
      final context = _buildContextForward(lines, i);
      for (final match in matches) {
        if (!_isValidMatch(match)) continue;
        final formatted = _formatMatch(match);
        if (_isInscriptionContext(context) && assign(formatted, 'inscription')) {
          continue;
        }
        if (_isEmissionContext(context) && assign(formatted, 'emission')) {
          continue;
        }
        if (_isExpirationContext(context) && assign(formatted, 'expiration')) {
          continue;
        }
        if (_isBirthContext(context)) assign(formatted, 'birth');
      }
    }

    return ExtractedFields(
      dateOfBirth: birth,
      expirationDate: expiration,
      emissionDate: emission,
      inscriptionDate: inscription,
    );
  }

  bool _isValidMatch(RegExpMatch match) {
    final d = int.tryParse(match.group(1)!) ?? 0;
    final m = int.tryParse(match.group(2)!) ?? 0;
    final y = int.tryParse(match.group(3)!) ?? 0;
    return _isValidDate(d, m, y);
  }

  String _formatMatch(RegExpMatch match) =>
      '${match.group(1)}/${match.group(2)}/${match.group(3)}';

  String _buildContextBackward(List<String> lines, int i) {
    final buf = StringBuffer(lines[i]);
    for (var k = 1; k <= 2 && i - k >= 0; k++) {
      buf.write(' ');
      buf.write(lines[i - k]);
    }
    return buf.toString();
  }

  String _buildContextForward(List<String> lines, int i) {
    final buf = StringBuffer(lines[i]);
    for (var k = 1; k <= 2 && i + k < lines.length; k++) {
      buf.write(' ');
      buf.write(lines[i + k]);
    }
    return buf.toString();
  }

  bool _isValidDate(int d, int m, int y) =>
      d >= 1 && d <= 31 && m >= 1 && m <= 12 && y >= 1900 && y <= 2050;

  bool _isInscriptionContext(String context) =>
      context.contains('INSCRIPCI');

  bool _isEmissionContext(String context) => context.contains('EMISI');

  static final RegExp _horizontalBirth =
      RegExp(r'\b[MF]\s+(?:PER\b|PERUAN[OA]\b)');

  bool _isBirthContext(String context) =>
      context.contains('NACIMIENTO') || _horizontalBirth.hasMatch(context);

  bool _isExpirationContext(String context) =>
      context.contains('CADUC') || context.contains('VENCIM');
}
