import 'package:latlong2/latlong.dart';
import 'package:taktooka/models/address_choice.dart';
import 'package:taktooka/services/backend.dart';

class _PlaceCacheEntry {
  final DateTime at;
  final List<AddressChoice> choices;
  _PlaceCacheEntry(this.choices) : at = DateTime.now();
}

class PlaceSearch {
  final Backend backend;
  PlaceSearch(this.backend);
  static final Map<String, _PlaceCacheEntry> _cache = {};
  final Map<String, Future<List<AddressChoice>>> _pending = {};

  static String normalize(String text) => text.toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670ـ]'), '')
      .replaceAll(RegExp('[أإآٱ]'), 'ا').replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه').replaceAll(RegExp(r'\s+'), ' ').trim();

  String _key(String query, LatLng origin) =>
      '${normalize(query)}|${origin.latitude.toStringAsFixed(3)}|${origin.longitude.toStringAsFixed(3)}';

  List<AddressChoice>? cached(String query, LatLng origin) {
    final key = _key(query, origin);
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.at) > const Duration(minutes: 5)) {
      _cache.remove(key);
      return null;
    }
    return List.of(entry.choices);
  }

  Future<List<AddressChoice>> find(String query, LatLng origin) {
    final saved = cached(query, origin);
    if (saved != null) return Future.value(saved);
    final key = _key(query, origin);
    final existing = _pending[key];
    if (existing != null) return existing;
    final request = Future<List<AddressChoice>>.microtask(() => _fetch(query, origin, key));
    _pending[key] = request;
    return request;
  }

  Future<List<AddressChoice>> _fetch(String query, LatLng origin, String key) async {
    try {
      final response = await backend.db.functions.invoke('taktooka-search', body: {
        'query': query,
        'point': [origin.latitude, origin.longitude],
      }).timeout(const Duration(seconds: 12));
      final data = response.data;
      if (data is! Map || data['error'] != null || data['results'] is! List) {
        throw Exception('SEARCH_UNAVAILABLE');
      }
      final results = <AddressChoice>[];
      for (final row in data['results'] as List) {
        if (row is! Map || row['label'] is! String || row['point'] is! List) continue;
        final xy = row['point'] as List;
        if (xy.length != 2 || xy.any((n) => n is! num || !n.isFinite)) continue;
        results.add(AddressChoice(row['label'] as String,
          LatLng((xy[0] as num).toDouble(), (xy[1] as num).toDouble())));
      }
      if (results.isNotEmpty) {
        if (_cache.length >= 100) _cache.remove(_cache.keys.first);
        _cache[key] = _PlaceCacheEntry(List.of(results));
      }
      return results;
    } finally {
      _pending.remove(key);
    }
  }
}
