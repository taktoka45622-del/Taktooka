import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'backend.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

class FoodCatalogCache extends ChangeNotifier {
  static final _stores = Expando<FoodCatalogCache>();
  static FoodCatalogCache forBackend(Backend b) =>
      _stores[b] ??= FoodCatalogCache._(b);
  final Map<String, (DateTime, dynamic)> _values = {};
  final Map<String, Future<dynamic>> _pending = {};
  final Backend b;
  int generation = 0;
  RealtimeChannel? channel;
  FoodCatalogCache._(this.b);
  bool liveSupported = false;
  void enableLiveUpdates() {
    liveSupported = true;
    if (hasListeners && channel == null)
      channel = b.db
          .channel('food-catalog-${identityHashCode(this)}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'tkt_food_catalog_state',
            callback: (_) => invalidate(),
          )
          .subscribe();
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (liveSupported) enableLiveUpdates();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners && channel != null) {
      if (b.db.getChannels().length == 1) b.db.realtime.disconnect();
      b.db.removeChannel(channel!);
      channel = null;
    }
  }

  String key(String action, Json data) =>
      '${b.db.auth.currentUser?.id}:${b.cacheEpoch}:$action:${jsonEncode(data)}';
  void clearForRefresh() {
    generation++;
    _values.clear();
  }

  void invalidate() {
    generation++;
    _values.clear();
    notifyListeners();
  }

  Future<dynamic> read(
    String action,
    Json data,
    Future<dynamic> Function() request,
  ) async {
    final round = generation;
    final requestKey = key(action, data);
    final name = '$generation:$requestKey', saved = _values[requestKey];
    if (saved != null && DateTime.now().difference(saved.$1).inSeconds < 8)
      return jsonDecode(jsonEncode(saved.$2));
    final value = await (_pending[name] ??= request().whenComplete(() {
      _pending.remove(name);
    }));
    if (round == generation && requestKey == key(action, data)) {
      _values.remove(requestKey);
      if (_values.length >= 50) _values.remove(_values.keys.first);
      _values[requestKey] = (DateTime.now(), jsonDecode(jsonEncode(value)));
    }
    return jsonDecode(jsonEncode(value));
  }
}
