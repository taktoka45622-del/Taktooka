import 'package:flutter/foundation.dart';
import 'backend.dart';
import 'commerce.dart';

final _stores = Expando<RestaurantFavorites>();
RestaurantFavorites favoritesFor(Backend b) =>
    _stores[b] ??= RestaurantFavorites(b);

class RestaurantFavorites extends ChangeNotifier {
  final Backend b;
  RestaurantFavorites(this.b);
  List<Json> _restaurants = [];
  List<Json> get restaurants =>
      _user == b.db.auth.currentUser?.id ? _restaurants : const [];
  final Set<String> pending = {};
  String? _user;
  int _generation = 0;
  bool contains(String id) =>
      _user == b.db.auth.currentUser?.id &&
      restaurants.any((r) => r['id'] == id);
  Future<void> load() async {
    final user = b.db.auth.currentUser?.id;
    if (_user != user) {
      _user = user;
      _restaurants = [];
      pending.clear();
      _generation++;
      notifyListeners();
    }
    if (user == null) return;
    final generation = ++_generation;
    final rows = Backend.rows(await commerceRpc(b, 'favorites'));
    if (generation == _generation && user == b.db.auth.currentUser?.id) {
      _restaurants = rows;
      notifyListeners();
    }
  }

  Future<bool> toggle(Json restaurant) async {
    final id = restaurant['id'].toString();
    if (pending.contains(id)) return contains(id);
    if (_user != b.db.auth.currentUser?.id) await load();
    final saved = !contains(id);
    pending.add(id);
    notifyListeners();
    final user = b.db.auth.currentUser?.id;
    try {
      await commerceRpc(b, 'favorite_set', {
        'restaurant_id': id,
        'saved': saved,
      });
      if (user == b.db.auth.currentUser?.id) {
        _generation++;
        _restaurants = [
          if (saved) Json.from(restaurant),
          ...restaurants.where((r) => r['id'] != id),
        ];
        notifyListeners();
      }
      return saved;
    } finally {
      pending.remove(id);
      notifyListeners();
    }
  }
}
