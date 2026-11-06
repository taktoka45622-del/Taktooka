import 'package:taktooka/services/restaurant_availability.dart';
import 'package:taktooka/services/food_contact.dart';
import 'package:taktooka/widgets/persistent_media_image.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taktooka/widgets/food_price_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taktooka/services/media_url.dart';
import 'package:taktooka/services/restaurant_range.dart';
import 'package:taktooka/widgets/food_discovery.dart';

void main() {
  test(
    'closing deadline works across midnight and a closed restaurant stays closed',
    () {
      final restaurant = {'open': true, 'closing_at': '2026-11-02T00:00:00Z'};
      expect(
        restaurantIsOpen(
          restaurant,
          now: DateTime.parse('2026-11-01T23:59:59Z'),
        ),
        true,
      );
      expect(
        restaurantIsOpen(
          restaurant,
          now: DateTime.parse('2026-11-02T00:00:00Z'),
        ),
        false,
      );
      expect(restaurantIsOpen({'open': false}), false);
    },
  );
  test('WhatsApp includes numeric order, all parties and amounts', () {
    final uri = foodWhatsAppUri(
      '07701234567',
      order: {
        'order_number': 123456,
        'restaurant_name': 'مطعم',
        'customer_name': 'زبون',
        'captain_name': 'كابتن',
        'food_total': 13000,
        'delivery_fee': 2000,
      },
    );
    expect(uri.path, '/9647701234567');
    expect(foodPhoneNumbers('هاتف 07701234567 ورقم طلب 200770123456789'), [
      '07701234567',
    ]);
    for (final label in ['123456', 'مطعم', 'زبون', 'كابتن', '13,000'])
      expect(uri.queryParameters['text'], contains(label));
  });
  test('food media coalesces downloads and reuses cached bytes', () async {
    var requests = 0;
    final cache = FoodMediaCache(
      client: MockClient((r) async {
        requests++;
        return http.Response.bytes([1, 2, 3], 200);
      }),
    );
    const url = 'https://cache.test/unique-image';
    final values = await Future.wait([cache.load(url), cache.load(url)]);
    expect(values.first, [1, 2, 3]);
    await cache.load(url);
    expect(requests, 1);
  });

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
  testWidgets(
    'price filter validates input and keeps the slider synchronized',
    (tester) async {
      RangeValues? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showFoodPriceFilter(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '3000');
      await tester.enterText(find.byType(TextField).last, '1000');
      await tester.tap(find.text('تطبيق'));
      await tester.pump();
      expect(find.text('أدخل نطاقًا صحيحًا بين 0 و100,000'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '5000');
      await tester.pump();
      expect(
        tester.widget<RangeSlider>(find.byType(RangeSlider)).values,
        const RangeValues(3000, 5000),
      );
      await tester.tap(find.text('تطبيق'));
      await tester.pumpAndSettle();
      expect(selected, const RangeValues(3000, 5000));
      expect(tester.takeException(), isNull);
    },
  );
}
