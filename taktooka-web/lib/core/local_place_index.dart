import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:taktooka/core/place_text.dart';

class LocalPlaceIndex {
  final List<List<dynamic>> rows;
  final _tokens = <String, Set<int>>{};
  LocalPlaceIndex(List<dynamic> data)
    : rows = data.map((r) => List<dynamic>.from(r as List)).toList() {
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      for (final word
          in (r.length > 7
                  ? (r[7] as String).split(' ')
                  : PlaceText.words('${r[0]} ${r[1]} ${r[5]}'))
              .where((word) => word.isNotEmpty)
              .toSet()) {
        (_tokens[word] ??= {}).add(i);
      }
    }
  }
  List<Map<String, dynamic>> search(
    String query,
    LatLng origin, {
    bool areasOnly = false,
  }) {
    final words = PlaceText.words(query);
    if (words.isEmpty) return [];
    final exact =
        words.where(_tokens.containsKey).map((w) => _tokens[w]!).toList()
          ..sort((a, b) => a.length.compareTo(b.length));
    final pool = <int>{};
    if (exact.isNotEmpty) {
      for (final ids in exact.take(2)) pool.addAll(ids);
    } else {
      for (final token in _tokens.keys) {
        if (token.startsWith(words.first)) pool.addAll(_tokens[token]!);
      }
      if (pool.isEmpty) {
        for (final token in _tokens.keys) {
          if (PlaceText.tokenQuality(token, words.first) > 0)
            pool.addAll(_tokens[token]!);
        }
      }
    }
    double match(int i) {
      final r = rows[i];
      final tokens = r.length > 7
          ? (r[7] as String).split(' ')
          : PlaceText.words('${r[0]} ${r[1]} ${r[5]}');
      var sum = 0.0;
      for (final word in words) {
        var best = 0.0;
        for (final token in tokens)
          best = math.max(best, PlaceText.tokenQuality(token, word));
        if (best == 0) return 0;
        sum += best;
      }
      return sum / words.length;
    }

    final selected = pool
        .where((i) => (!areasOnly || rows[i][6] == true) && match(i) >= .7)
        .toList();
    double distance(int i) {
      final r = rows[i],
          a = ((r[2] as num) - origin.latitude) * 111320,
          b =
              ((r[3] as num) - origin.longitude) *
              111320 *
              math.cos(origin.latitude * math.pi / 180);
      return math.sqrt(a * a + b * b);
    }

    final scores = {
      for (final i in selected)
        i: match(i) * 130 - math.min(distance(i) / 3000, 100),
    };
    selected.sort((a, b) {
      final localA = distance(a) <= 25000, localB = distance(b) <= 25000;
      if (localA != localB) return localA ? -1 : 1;
      return scores[b]!.compareTo(scores[a]!);
    });
    return selected.take(40).map((i) {
      final r = rows[i];
      return <String, dynamic>{
        'title': r[0],
        'aliases': r[1],
        'label': [r[0], r[5]].where((s) => s.toString().isNotEmpty).join('، '),
        'point': LatLng((r[2] as num).toDouble(), (r[3] as num).toDouble()),
        'area': r[6],
      };
    }).toList();
  }
}
