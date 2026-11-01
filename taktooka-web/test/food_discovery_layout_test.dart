import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taktooka/services/media_url.dart';
import 'package:taktooka/services/restaurant_range.dart';
import 'package:taktooka/widgets/food_discovery.dart';

void main() {
  test('range excludes restaurants just beyond fifteen kilometres', () {
    const origin = [33.4, 44.4];
    expect(
      restaurantWithinRange({
        'location': [33.5348, 44.4],
      }, origin),
      isTrue,
    );
    expect(
      restaurantWithinRange({
        'location': [33.535, 44.4],
      }, origin),
      isFalse,
    );
    expect(
      restaurantWithinRange({
        'location': [33.4, 44.4],
      }, null),
      isFalse,
    );
  });
  test('media keeps complete links and normalizes bucket paths', () {
    expect(
      mediaUrl(
        'https://example.com',
        'restaurant-images',
        'https://cdn.example/a.jpg',
      ),
      'https://cdn.example/a.jpg',
    );
    expect(
      mediaUrl(
        'https://example.com',
        'restaurant-images',
        '/restaurant-images/a b.jpg',
      ),
      'https://example.com/storage/v1/object/public/restaurant-images/a%20b.jpg',
    );
  });
  testWidgets('food discovery fits a narrow phone and opens meal search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final meal = <String, dynamic>{
      'id': 'm1',
      'name': 'بيتزا دجاج',
      'restaurant_name': 'بيت البيتزا',
      'price': 13000,
      'previous_price': 15000,
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FoodDiscovery(
                  restaurants: const [],
                  meals: [meal],
                  selectedCategory: '',
                  area: 'الحسينية',
                  offers: false,
                  locating: false,
                  search: (_) {},
                  category: (_) {},
                  filter: () {},
                  currentLocation: () {},
                  chooseLocation: () {},
                  openRestaurant: (_) {},
                  openMeal: (_) {},
                  banner: const SizedBox(height: 140),
                  photo: (_, {double height = 130}) => SizedBox(
                    height: height,
                    child: const ColoredBox(color: Colors.red),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('البحث عن الطعام'), findsOneWidget);
    expect(find.text('بيتزا دجاج'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'بركر');
    await tester.pump();
    expect(find.text('ماكو وجبات مطابقة للبحث'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
