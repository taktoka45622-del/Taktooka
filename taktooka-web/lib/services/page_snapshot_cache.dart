import 'package:taktooka/services/backend.dart';

class PageSnapshotCache {
  static final Expando<Map<String, (DateTime, Json)>> _sessions = Expando();
  static String _key(Backend backend, String name) =>
      '${backend.db.auth.currentUser?.id}:$name';
  static Json? read(Backend backend, String name) {
    final entry = _sessions[backend]?[_key(backend, name)];
    if (entry == null || DateTime.now().difference(entry.$1).inMinutes >= 2)
      return null;
    return Json.from(entry.$2);
  }

  static void save(Backend backend, String name, Json value) {
    final cache = _sessions[backend] ??= {};
    if (cache.length >= 50) cache.remove(cache.keys.first);
    cache[_key(backend, name)] = (DateTime.now(), Json.from(value));
  }
}
