import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:taktooka/services/backend.dart';

class FoodCart extends ChangeNotifier {
  Json? restaurant;
  final List<Json> _items = [];
  List<Json> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  int get quantity => _items.fold(0, (s, i) => s + (i['quantity'] as int));
  int get total => _items.fold(
    0,
    (s, i) => s + (i['price'] as num).toInt() * (i['quantity'] as int),
  );
  bool accepts(String restaurantId) =>
      isEmpty || restaurant?['id'] == restaurantId;
  String keyFor(Json item) {
    final ids = List<String>.from(item['addon_ids'] ?? [])..sort();
    return jsonEncode([item['id'], item['size_id'], ids, item['notes'] ?? '']);
  }

  void add(Json shop, Json item) {
    if (!accepts(shop['id'].toString()))
      throw StateError('CART_RESTAURANT_CONFLICT');
    final key = keyFor(item),
        index = _items.indexWhere((i) => keyFor(i) == key);
    final count = (item['quantity'] as int);
    if (count < 1 || count > 99) throw StateError('INVALID_QUANTITY');
    if (index >= 0) {
      final combined = (_items[index]['quantity'] as int) + count;
      if (combined > 99) throw StateError('INVALID_QUANTITY');
      _items[index] = {...item, 'quantity': combined};
    } else {
      if (_items.length >= 100) throw StateError('BASKET_LIMIT');
      _items.add(Map<String, dynamic>.from(item));
    }
    restaurant = Map<String, dynamic>.from(shop);
    notifyListeners();
  }

  void setQuantity(int index, int quantity) {
    if (quantity <= 0) {
      _items.removeAt(index);
    } else if (quantity <= 99) {
      _items[index] = {..._items[index], 'quantity': quantity};
    }
    if (_items.isEmpty) restaurant = null;
    notifyListeners();
  }

  void clear() {
    _items.clear();
    restaurant = null;
    notifyListeners();
  }

  List<Json> get requestItems => [
    for (final i in _items)
      {
        'id': i['id'],
        'quantity': i['quantity'],
        'size_id': i['size_id'],
        'addon_ids': i['addon_ids'] ?? [],
        'notes': i['notes'] ?? '',
      },
  ];
}
