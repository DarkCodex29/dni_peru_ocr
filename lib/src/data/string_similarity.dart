/// Pure-Dart utilities for comparing strings with tolerance for OCR noise.
///
/// Used by the KYC confirmation step to decide whether an OCR-extracted
/// name "matches" the user's stored profile name, even when the OCR
/// inserts/deletes/substitutes a few characters (e.g. `ERMITANXXO`
/// extracted from a DNI whose real value is `ERMITAÑO` → `ERMITANO`
/// after [OcrFieldNormalizer.normalizeName]).
///
/// All comparisons assume both inputs are ALREADY normalized via
/// `OcrFieldNormalizer`. This file contains NO normalization logic —
/// it only measures structural similarity.
class StringSimilarity {
  StringSimilarity._();

  /// Default similarity threshold (0.0 .. 1.0) above which two strings
  /// are considered "the same name" for KYC purposes.
  ///
  /// 0.80 means at most 20% of the longer string can differ. Tuned for
  /// Peruvian DNI OCR where 1-2 character glitches per surname are
  /// common but full mismatches are not.
  static const double defaultThreshold = 0.80;

  /// Returns the Levenshtein edit distance between [a] and [b]:
  /// the minimum number of single-character insertions, deletions, or
  /// substitutions required to transform one into the other.
  ///
  /// Implementation: iterative Wagner-Fischer with a single-row buffer
  /// (O(min(|a|,|b|)) memory instead of O(|a|*|b|)).
  ///
  /// Examples:
  ///   distance("ERMITANO", "ERMITANO")    -> 0
  ///   distance("ERMITANO", "ERMITANXXO")  -> 2   (insert "XX")
  ///   distance("JOSE", "JOSEPH")          -> 2   (insert "PH")
  ///   distance("ABC", "XYZ")              -> 3   (3 substitutions)
  static int distance(String a, String b) {
    if (identical(a, b) || a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    // Ensure shorter string is on the right to keep the buffer small.
    final longer = a.length >= b.length ? a : b;
    final shorter = a.length >= b.length ? b : a;

    final n = longer.length;
    final m = shorter.length;
    final prev = List<int>.generate(m + 1, (i) => i);

    for (var i = 1; i <= n; i++) {
      var topLeft = prev[0];
      prev[0] = i;

      for (var j = 1; j <= m; j++) {
        final saved = prev[j];
        final cost =
            longer.codeUnitAt(i - 1) == shorter.codeUnitAt(j - 1) ? 0 : 1;
        prev[j] = _min3(
          prev[j] + 1, // deletion
          prev[j - 1] + 1, // insertion
          topLeft + cost, // substitution
        );
        topLeft = saved;
      }
    }

    return prev[m];
  }

  /// Returns a similarity ratio in the range `[0.0, 1.0]` derived from Levenshtein
  /// distance:
  ///
  ///   similarity = 1 - (distance / max(|a|, |b|))
  ///
  /// Two empty strings are defined as fully similar (1.0). An empty
  /// string vs a non-empty string is 0.0.
  ///
  /// Examples:
  ///   similarity("ERMITANO", "ERMITANO")    -> 1.0    (identical)
  ///   similarity("ERMITANO", "ERMITANXXO")  -> 0.80   (2 / 10)
  ///   similarity("JOSE", "JOSEPH")          -> 0.667  (2 / 6)
  ///   similarity("ABC", "XYZ")              -> 0.0    (full mismatch)
  static double similarity(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    final maxLen = a.length > b.length ? a.length : b.length;
    final d = distance(a, b);
    return 1.0 - (d / maxLen);
  }

  /// Returns `true` when [a] and [b] are similar enough to be considered
  /// the same name, using [threshold] (defaults to [defaultThreshold]).
  ///
  /// This is the function the KYC confirmation step should call after
  /// normalizing both inputs.
  static bool isMatch(
    String a,
    String b, {
    double threshold = defaultThreshold,
  }) {
    return similarity(a, b) >= threshold;
  }

  static int _min3(int a, int b, int c) {
    final ab = a < b ? a : b;
    return ab < c ? ab : c;
  }
}
