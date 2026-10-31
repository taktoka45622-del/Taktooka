import 'package:flutter_test/flutter_test.dart';
import 'package:taktooka/models/food_cart.dart';

void main() {
  final shop = {'id': 'a', 'name': 'مطعم أول'},
      other = {'id': 'b', 'name': 'مطعم ثاني'};
  final line = {
    'id': 'meal',
    'name': 'بركر',
    'price': 7000,
    'base_price': 6000,
    'quantity': 2,
    'size_id': 'normal',
    'addon_ids': ['cheese'],
    'addons': [
      {'id': 'cheese', 'price': 1000, 'image_path': 'cheese.jpg'},
    ],
    'notes': 'بدون بصل',
    'image_path': 'burger.jpg',
  };
  test('extras are multiplied by meal quantity, identical choices merge', () {
    final cart = FoodCart();
    cart.add(shop, line);
    expect(cart.total, 14000);
    cart.add(shop, {...line, 'quantity': 1});
    expect(cart.items.length, 1);
    expect(cart.quantity, 3);
    expect(cart.total, 21000);
    expect(cart.requestItems.single['addon_ids'], ['cheese']);
    cart.dispose();
  });
  test(
    'restaurant boundary rejects mixing and retains the existing basket',
    () {
      final cart = FoodCart();
      cart.add(shop, line);
      expect(() => cart.add(other, line), throwsStateError);
      expect(cart.restaurant?['id'], 'a');
      expect(cart.total, 14000);
      cart.clear();
      cart.add(other, line);
      expect(cart.restaurant?['id'], 'b');
      cart.dispose();
    },
  );
  test('different sizes addons or notes remain distinct lines', () {
    final cart = FoodCart();
    cart.add(shop, line);
    cart.add(shop, {
      ...line,
      'size_id': 'double',
      'price': 9000,
      'quantity': 1,
    });
    cart.add(shop, {
      ...line,
      'addon_ids': [],
      'addons': [],
      'price': 6000,
      'quantity': 1,
    });
    cart.add(shop, {...line, 'notes': 'بدون صوص', 'quantity': 1});
    expect(cart.items.length, 4);
    expect(cart.total, 36000);
    cart.dispose();
  });
  test(
    'quantity edits recalculate extras and empty cart releases restaurant',
    () {
      final cart = FoodCart();
      cart.add(shop, line);
      cart.setQuantity(0, 1);
      expect(cart.total, 7000);
      cart.setQuantity(0, 0);
      expect(cart.isEmpty, true);
      expect(cart.restaurant, isNull);
      expect(cart.total, 0);
      cart.dispose();
    },
  );
  test('excess quantity does not silently drop meals or alter the basket', () {
    final cart = FoodCart();
    cart.add(shop, {...line, 'quantity': 99});
    expect(() => cart.add(shop, line), throwsStateError);
    expect(cart.quantity, 99);
    cart.dispose();
  });
}
