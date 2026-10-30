import 'package:latlong2/latlong.dart';
import 'package:taktooka/models/address_choice.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/device_places.dart';

class _PlaceCacheEntry {
  final DateTime at;
  final List<AddressChoice> choices;
  _PlaceCacheEntry(this.choices) : at = DateTime.now();
}

class PlaceSearch {
  static final _places = DevicePlaces();
  final Backend backend;
  PlaceSearch(this.backend);
  static final Map<String, _PlaceCacheEntry> _cache = {};
  final Map<String, Future<List<AddressChoice>>> _pending = {};

  static String normalize(String text) => DevicePlaces.normalize(text);

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
    final request = Future<List<AddressChoice>>.microtask(
      () => _fetch(query, origin, key),
    );
    _pending[key] = request;
    return request;
  }

  Future<List<AddressChoice>> _fetch(
    String query,
    LatLng origin,
    String key,
  ) async {
    try {
      final results = await _places.find(query, origin);
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
