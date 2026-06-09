/// Pure functions for normalizing OCR-extracted field values.
class OcrFieldNormalizer {
  OcrFieldNormalizer._();

  /// Strips diacritics, uppercases, and collapses whitespace.
  static String normalizeName(String value) {
    if (value.isEmpty) return value;
    final denoised = denoiseTildeNoise(value);
    final stripped = _stripDiacritics(denoised);
    return stripped.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Display normalizer that preserves diacritics.
  static String normalizeForDisplay(String input) {
    if (input.isEmpty) return input;
    return denoiseTildeNoise(input.trim()).toUpperCase();
  }

  /// Repairs the ML Kit `Ñ → NXX` corruption pattern.
  static String denoiseTildeNoise(String input) {
    if (input.isEmpty) return input;
    return input.replaceAllMapped(_tildeNoisePattern, (match) {
      final firstChar = match.group(0)![0];
      final isUpper = firstChar == firstChar.toUpperCase();
      return isUpper ? 'Ñ' : 'ñ';
    });
  }

  /// Removes whitespace from a document number.
  static String normalizeDocument(String value) {
    if (value.isEmpty) return value;
    return value.replaceAll(RegExp(r'\s+'), '').trim();
  }

  /// Trims a date string.
  static String normalizeDate(String value) {
    return value.trim();
  }

  static final RegExp _tildeNoisePattern = RegExp(
    r'(?<=^|[\sAEIOUaeiou])N[X]{2,3}(?=$|[\sAEIOUaeiou])',
    caseSensitive: false,
  );

  static const _diacriticMap = {
    'À': 'A',
    'Á': 'A',
    'Â': 'A',
    'Ã': 'A',
    'Ä': 'A',
    'Å': 'A',
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'å': 'a',
    'È': 'E',
    'É': 'E',
    'Ê': 'E',
    'Ë': 'E',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'Ì': 'I',
    'Í': 'I',
    'Î': 'I',
    'Ï': 'I',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'Ò': 'O',
    'Ó': 'O',
    'Ô': 'O',
    'Õ': 'O',
    'Ö': 'O',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'Ù': 'U',
    'Ú': 'U',
    'Û': 'U',
    'Ü': 'U',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'Ñ': 'N',
    'ñ': 'n',
    'Ç': 'C',
    'ç': 'c',
    'Ý': 'Y',
    'ý': 'y',
    'ÿ': 'y',
  };

  static String _stripDiacritics(String value) {
    final buf = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      buf.write(_diacriticMap[char] ?? char);
    }
    return buf.toString();
  }
}
