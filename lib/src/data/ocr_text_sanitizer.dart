class OcrTextSanitizer {
  const OcrTextSanitizer();

  static const Set<String> _externalNoise = {
    'SABORIZANTES',
    'SABORIZADA',
    'SABORIZANTE',
    'NATURAL',
    'NATURALES',
    'REFRESCANTE',
    'REFRESCANTES',
    'EXTRACTO',
    'PURO',
    'AGUA',
    'BEBIDA',
    'GASEOSA',
    'JUGO',
    'COCA',
    'PEPSI',
    'FANTA',
    'INKA',
    'KOLA',
    'INKAKOLA',
    'POLLO',
    'TABLET',
    'PHONE',
    'IPHONE',
    'SAMSUNG',
    'GALAXY',
  };

  String sanitize(String text) {
    final cleaned = StringBuffer();
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (_isExternalNoiseLine(line)) continue;
      cleaned.writeln(line);
    }
    return cleaned.toString().trimRight();
  }

  bool _isExternalNoiseLine(String line) {
    final tokens = line.split(RegExp(r'\s+'));
    if (tokens.isEmpty) return false;
    var externalCount = 0;
    var nonNoiseCount = 0;
    for (final token in tokens) {
      final key = _normalize(token);
      if (key.length < 2) continue;
      if (_externalNoise.contains(key)) {
        externalCount++;
      } else {
        nonNoiseCount++;
      }
    }
    if (externalCount == 0) return false;
    return nonNoiseCount == 0;
  }

  String _normalize(String token) {
    return token
        .toUpperCase()
        .replaceAll(RegExp(r'[ÁÀÄÂÃ]'), 'A')
        .replaceAll(RegExp(r'[ÉÈËÊ]'), 'E')
        .replaceAll(RegExp(r'[ÍÌÏÎ]'), 'I')
        .replaceAll(RegExp(r'[ÓÒÖÔÕ]'), 'O')
        .replaceAll(RegExp(r'[ÚÙÜÛ]'), 'U')
        .replaceAll('Ñ', 'N')
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }
}
