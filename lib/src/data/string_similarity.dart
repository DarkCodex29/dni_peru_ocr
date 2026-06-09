/// Pure-Dart utilities for comparing strings with tolerance for OCR noise.
class StringSimilarity {
  StringSimilarity._();

  static const double defaultThreshold = 0.80;

  /// Returns the Levenshtein edit distance between [a] and [b].
  static int distance(String a, String b) {
    if (identical(a, b) || a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

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
          prev[j] + 1,
          prev[j - 1] + 1,
          topLeft + cost,
        );
        topLeft = saved;
      }
    }

    return prev[m];
  }

  /// Returns a similarity ratio in `[0.0, 1.0]` derived from Levenshtein distance.
  static double similarity(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    final maxLen = a.length > b.length ? a.length : b.length;
    final d = distance(a, b);
    return 1.0 - (d / maxLen);
  }

  /// Whether [a] and [b] are similar enough using [threshold].
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
