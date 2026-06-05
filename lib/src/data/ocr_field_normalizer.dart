/// Pure functions for normalizing OCR-extracted field values.
///
/// Used by [OcrConsensusAccumulator] before inserting votes into the vote map,
/// so that normalized variants (e.g. `JOSE` vs `JOSÉ`) are treated as equal.
class OcrFieldNormalizer {
  OcrFieldNormalizer._();

  /// Normalizes a name field:
  /// 1. Strips diacritics (replaces accented characters with their ASCII base).
  /// 2. Uppercases the result.
  /// 3. Collapses multiple whitespace runs into a single space.
  /// 4. Trims leading/trailing whitespace.
  static String normalizeName(String value) {
    if (value.isEmpty) return value;
    // Step 0: repair ML Kit `Ñ → NXX` corruption BEFORE stripping diacritics
    // so that a noisy "MUNXXOZ" and a clean "MUÑOZ" collapse to the same
    // ASCII vote-key ("MUNOZ"). Without this, `_stripDiacritics` would not
    // see the rebuilt `Ñ` and the X-noise would survive into the key.
    final denoised = denoiseTildeNoise(value);
    final stripped = _stripDiacritics(denoised);
    return stripped.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Display normalizer for name fields: trims, denoises tilde noise, and
  /// uppercases — **without** stripping diacritics. The result is what the
  /// user (and the backend) should see, so a `Ñ` repaired from `NXX` is
  /// preserved instead of being collapsed to `N`.
  static String normalizeForDisplay(String input) {
    if (input.isEmpty) return input;
    return denoiseTildeNoise(input.trim()).toUpperCase();
  }

  /// Repairs the ML Kit Latin recognizer's `Ñ → NXX` corruption pattern.
  ///
  /// ML Kit emits `Ñ` as a sequence of `N` followed by 2-3 literal `X` glyphs
  /// when the document character is partially occluded by the tilde. This
  /// function rewrites `N[X]{2,3}` to `Ñ` only when flanked by a vowel or
  /// string boundary on both sides — keeping unrelated tokens like
  /// `ANXIETY`, `EXTRA`, `TAXI` untouched.
  ///
  /// The replacement case follows the surrounding token:
  ///   - upper-case neighbor → `Ñ`
  ///   - lower-case neighbor → `ñ`
  ///
  /// Pure function; safe to compose with any other normalizer.
  static String denoiseTildeNoise(String input) {
    if (input.isEmpty) return input;
    return input.replaceAllMapped(_tildeNoisePattern, (match) {
      // Decide case from the first letter of the matched run (the `N`).
      final firstChar = match.group(0)![0];
      final isUpper = firstChar == firstChar.toUpperCase();
      return isUpper ? 'Ñ' : 'ñ';
    });
  }

  /// Normalizes a document number:
  /// 1. Removes all whitespace.
  /// 2. Trims leading/trailing whitespace.
  static String normalizeDocument(String value) {
    if (value.isEmpty) return value;
    return value.replaceAll(RegExp(r'\s+'), '').trim();
  }

  /// Normalizes a date string:
  /// 1. Trims leading/trailing whitespace.
  /// No transformation is applied to the content (date formats vary).
  static String normalizeDate(String value) {
    return value.trim();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Internal
  // ─────────────────────────────────────────────────────────────────────────

  /// ML Kit tilde-noise marker: an `N` followed by 2-3 literal `X` glyphs,
  /// surrounded by a vowel or string boundary on both sides. Case-insensitive
  /// so it matches both `MUNXXOZ` and `munxxoz`.
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
