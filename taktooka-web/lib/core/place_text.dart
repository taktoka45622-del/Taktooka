import 'dart:math' as math;

class PlaceText {
  static final _diacritics = RegExp(r'[\u064B-\u065F\u0670ـ]');
  static final _alef = RegExp('[أإآٱ]');
  static final _punctuation = RegExp(
    r'[^a-z0-9\u0621-\u063A\u0641-\u064A\u0660-\u0669\u0671-\u06D3\u06FA-\u06FF\u00C0-\u024F]+',
  );
  static String normalize(String s) => s
      .toLowerCase()
      .replaceAll(_diacritics, '')
      .replaceAll(_alef, 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll('ئ', 'ي')
      .replaceAll('ؤ', 'و')
      .replaceAll('گ', 'ك')
      .replaceAll('السوك', 'السوق')
      .replaceAll(_punctuation, ' ')
      .trim();
  static List<String> words(String s) =>
      normalize(s).split(' ').where((s) => s.isNotEmpty).toList();
  static int edits(String a, String b) {
    var prior = List.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final next = <int>[i];
      for (var j = 1; j <= b.length; j++)
        next.add(
          math.min(
            math.min(next[j - 1] + 1, prior[j] + 1),
            prior[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
          ),
        );
      prior = next;
    }
    return prior.last;
  }

  static double tokenQuality(String c, String word) {
    if (c == word) return 1;
    if (word.length >= 2 && c.startsWith(word)) return .9;
    if (word.length >= 4 &&
        (c.length - word.length).abs() <= 1 &&
        edits(c, word) <= 1)
      return .85;
    if (word.length >= 7 &&
        (c.length - word.length).abs() <= 2 &&
        edits(c, word) <= 2)
      return .7;
    return 0;
  }

  static double quality(String label, String query) {
    final candidates = words(label),
        scores = words(query)
            .map(
              (word) => candidates.fold<double>(
                0,
                (best, c) => math.max(best, tokenQuality(c, word)),
              ),
            )
            .toList();
    return scores.isEmpty || scores.any((s) => s == 0)
        ? 0
        : scores.reduce((a, b) => a + b) / scores.length;
  }
}
