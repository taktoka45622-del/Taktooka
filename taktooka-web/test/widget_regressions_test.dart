import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taktooka/core/app_preferences.dart';
import 'package:taktooka/pages/meal_details_page.dart';
import 'package:taktooka/widgets/food_restaurant_payment.dart';
import 'package:taktooka/widgets/food_discovery.dart';
import 'package:taktooka/services/backend.dart';

Widget host(
  Widget child, {
  Size size = const Size(390, 844),
  double scale = 1,
}) => PreferencesScope(
  child: MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
      child: Directionality(textDirection: TextDirection.rtl, child: child),
    ),
  ),
);
Widget photo(dynamic path, {double height = 100}) =>
    SizedBox(height: height, width: double.infinity);
const shop = <String, dynamic>{
  'id': 'shop',
  'name': 'مطعم تجريبي',
  'open': true,
};
Map<String, dynamic> meal({bool available = true, int price = 1500}) => {
  'id': 'meal',
  'name': 'وجبة تجريبية',
  'price': price,
  'available': available,
  'image_paths': <String>[],
  'options': <String, dynamic>{'sizes': <dynamic>[], 'addons': <dynamic>[]},
};
Future<void> configure(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('unavailable meal cannot be added to cart', (tester) async {
    await configure(tester);
    await tester.pumpWidget(
      host(
        MealDetailsPage(
          meal: meal(available: false),
          restaurant: shop,
          favorite: false,
          toggleFavorite: () async => true,
          photo: photo,
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('غير متوفرة حاليًا'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('غير متوفرة حاليًا'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton).last);
    expect(button.onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('meal refresh obtains new availability and preserves notes', (
    tester,
  ) async {
    var reads = 0;
    await tester.pumpWidget(
      host(
        MealDetailsPage(
          meal: meal(),
          restaurant: shop,
          favorite: false,
          toggleFavorite: () async => true,
          photo: photo,
          refreshData: () async {
            reads++;
            return (
              meal: meal(available: false, price: 2000),
              restaurant: shop,
            );
          },
        ),
      ),
    );
    final notes = find.byType(TextField);
    await tester.scrollUntilVisible(
      notes,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(notes, 'بدون بصل');
    final indicator = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    await indicator.onRefresh();
    await tester.pump();
    expect(reads, 1);
    expect(find.text('بدون بصل'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'paid order shows actual settlement date without unpaid warning',
    (tester) async {
      await configure(tester);
      await tester.pumpWidget(
        host(
          const Scaffold(
            body: FoodRestaurantPayment(
              paidAt: '2026-11-07T12:30:00Z',
              showUnpaid: true,
            ),
          ),
        ),
      );
      expect(find.text('تم تسديد الأموال'), findsOneWidget);
      expect(find.textContaining('07/11/2026'), findsOneWidget);
      expect(find.text('يجب التوجه للمطعم وتسليمه الأموال'), findsNothing);
    },
  );
  testWidgets('closed restaurant and unavailable meal stay visible', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      host(
        Scaffold(
          body: SingleChildScrollView(
            child: FoodDiscovery(
              restaurants: [
                {...shop, 'open': false},
              ],
              meals: [
                {...meal(available: false), 'restaurant_name': 'مطعم تجريبي'},
              ],
              selectedCategory: '',
              area: 'بغداد',
              offers: false,
              locating: false,
              search: (_) {},
              category: (_) {},
              filter: () {},
              currentLocation: () {},
              chooseLocation: () {},
              openRestaurant: (_) {},
              openMeal: (_) {
                selected++;
              },
              banner: const SizedBox(),
              photo: photo,
            ),
          ),
        ),
      ),
    );
    expect(find.text('المطعم مغلق حاليًا'), findsWidgets);
    expect(find.text('غير متوفرة حاليًا'), findsWidgets);
    await tester.ensureVisible(find.text('غير متوفرة حاليًا').first);
    await tester.tap(find.text('غير متوفرة حاليًا').first);
    await tester.pump();
    expect(selected, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('empty search results retain pull to refresh', (tester) async {
    await configure(tester);
    var reads = 0;
    await tester.pumpWidget(
      host(
        FoodSearchPage(
          meals: const [],
          restaurants: const [],
          photo: photo,
          open: (_) {},
          findMeals: (_) async {
            reads++;
            return <Json>[];
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    final indicator = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    final before = reads;
    await indicator.onRefresh();
    await tester.pump();
    expect(reads, before + 1);
    await tester.pumpWidget(const SizedBox());
  });
}
