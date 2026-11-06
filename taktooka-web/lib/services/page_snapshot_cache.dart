import 'dart:convert';
import 'package:taktooka/services/backend.dart';

class PageSnapshotCache {
  static final Expando<Map<String, (DateTime, Json)>> _sessions = Expando();
  static String _key(Backend backend, String name) =>
      '${backend.db.auth.currentUser?.id}:${backend.cacheEpoch}:$name';
  static Json _copy(Json value) =>
      Json.from(jsonDecode(jsonEncode(value)) as Map);
  static Json? read(Backend backend, String name) {
    final cache = _sessions[backend];
    final key = _key(backend, name);
    final entry = cache?[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.$1).inMinutes >= 10) {
      cache?.remove(key);
      return null;
    }
    return _copy(entry.$2);
  }

  static void save(Backend backend, String name, Json value) {
    final cache = _sessions[backend] ??= {};
    final key = _key(backend, name);
    cache.remove(key);
    if (cache.length >= 50) cache.remove(cache.keys.first);
    cache[key] = (DateTime.now(), _copy(value));
  }

  static void invalidate(Backend backend, [String? name]) {
    if (name == null) {
      _sessions[backend]?.clear();
    } else {
      _sessions[backend]?.remove(_key(backend, name));
    }
  }
}
