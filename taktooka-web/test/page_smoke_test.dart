import 'package:taktooka/pages/ride_map_page.dart';
import 'package:taktooka/widgets/ride_endpoint_marker.dart';
import 'package:yet_another_json_isolate/yet_another_json_isolate.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/core/app_preferences.dart';
import 'package:taktooka/pages/about_page.dart';
import 'package:taktooka/pages/privacy_page.dart';
import 'package:taktooka/pages/phone_login_page.dart';
import 'package:taktooka/pages/account_page.dart';
import 'package:taktooka/pages/city_page.dart';
import 'package:taktooka/pages/registration_choice_page.dart';
import 'package:taktooka/pages/settings_page.dart';
import 'package:taktooka/pages/profile_page.dart';
import 'package:taktooka/pages/history_page.dart';
import 'package:taktooka/pages/wallet_page.dart';
import 'package:taktooka/pages/lines_page.dart';
import 'package:taktooka/pages/offers_page.dart';
import 'package:taktooka/pages/prize_wheel_page.dart';
import 'package:taktooka/pages/food_order_details_page.dart';
import 'package:taktooka/pages/restaurant_settings_page.dart';
import 'package:taktooka/pages/restaurant_couriers_page.dart';
import 'package:taktooka/pages/meal_editor_page.dart';
import 'package:taktooka/pages/chat_page.dart';

final orderFixture = <String, dynamic>{
  'id': '00000000-0000-0000-0000-000000000001',
  'status': 'delivered',
  'restaurant_name': 'مطعم تجريبي',
  'restaurant_address': 'عنوان المطعم',
  'customer_name': 'زبون تجريبي',
  'customer_address': 'عنوان الزبون',
  'items': <dynamic>[],
  'food_total': 1500,
  'service_fee': 500,
  'delivery_fee': 1500,
  'created_at': '2026-11-07T12:00:00Z',
  'updated_at': '2026-11-07T12:15:00Z',
};

class TestJson extends YAJsonIsolate {
  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<dynamic> decode(String value) async => jsonDecode(value);
  @override
  Future<String> encode(Object? value) async => jsonEncode(value);
}

class TestBackend extends Backend {
  TestBackend()
    : super(
        client: SupabaseClient(
          'https://example.test',
          'test-key',
          isolate: TestJson(),
          httpClient: MockClient(
            (request) async => http.Response(
              jsonEncode(
                request.body.contains('order_details') ? orderFixture : [],
              ),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      );
  int refreshes = 0;
  @override
  Future<void> refresh({
    bool lightweight = false,
    bool queueIfBusy = true,
  }) async {
    refreshes++;
    notifyListeners();
  }

  @override
  Future<dynamic> wheel(String action, [Json data = const {}]) async => {
    'enabled': true,
    'history': <dynamic>[],
    'server_now': DateTime.now().toUtc().toIso8601String(),
  };
}

void noop() {}
Future<void> run(Future<void> Function() action) => action();
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final pages = <String, Widget Function(TestBackend)>{
    'about': (b) => AboutPage(support: noop),
    'captain incoming ride preview': (b) {
      b.profile = {
        'captain': true,
        'name': 'كابتن',
        'expires_at': '2030-01-01T00:00:00Z',
      };
      b.tracking = true;
      b.requests = [
        {
          'id': 'ride',
          'offer_id': 'offer',
          'offer_expires_at': DateTime.now()
              .toUtc()
              .add(const Duration(seconds: 30))
              .toIso8601String(),
          'pickup': [33.3, 44.4],
          'destination': [33.31, 44.41],
          'pickup_name': 'مكان الزبون',
          'destination_name': 'وجهة الزبون',
          'eta_s': 60,
          'fare': 1500,
          'customer_due': 1500,
          'base_fare': 1500,
          'night_surcharge': 0,
        },
      ];
      return RideMap(
        backend: b,
        busy: false,
        run: run,
        toast: (_) {},
        openAccount: noop,
      );
    },
    'restaurant settings': (b) => RestaurantSettingsPage(
      b: b,
      restaurant: {
        'id': 'shop',
        'name': 'مطعم تجريبي',
        'phone': '07700000000',
        'address': 'بغداد',
        'open': true,
        'location': [33.3, 44.4],
      },
    ),
    'restaurant couriers': (b) => RestaurantCouriersPage(b: b, enabled: true),
    'meal editor': (b) => MealEditorPage(b: b),
    'support': (b) => ChatPage(b: b),
    'customer order details': (b) =>
        FoodOrderDetailsPage(b: b, initial: orderFixture),
    'restaurant order details': (b) {
      b.commerce = {
        'restaurant': {'id': 'shop', 'name': 'مطعم تجريبي'},
      };
      return FoodOrderDetailsPage(b: b, initial: orderFixture);
    },
    'privacy': (b) => const PrivacyPage(),
    'login': (b) => PhoneLoginPage(backend: b),
    'account': (b) =>
        AccountPage(backend: b, busy: false, run: run, toast: (_) {}),
    'city': (b) => CityPage(b: b),
    'registration': (b) => RegistrationChoicePage(b: b),
    'settings': (b) => SettingsPage(
      backend: b,
      editAccount: noop,
      selectCity: () async {},
      run: run,
    ),
    'profile': (b) => ProfileHub(
      b: b,
      edit: noop,
      wallet: noop,
      history: noop,
      addresses: noop,
      offers: noop,
      support: noop,
      settings: noop,
      about: noop,
      invite: noop,
    ),
    'history': (b) => HistoryPage(backend: b),
    'wallet': (b) => WalletPage(b: b, support: noop),
    'lines': (b) => LinesPage(b: b),
    'offers': (b) => OffersPage(b: b, run: run, login: noop),
    'captain wheel': (b) {
      b.profile = {'captain': true, 'name': 'كابتن'};
      return OffersPage(b: b, run: run, login: noop);
    },
  };
  for (final entry in pages.entries) {
    testWidgets('${entry.key} opens without framework errors', (tester) async {
      final b = TestBackend();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        PreferencesScope(
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(body: entry.value(b)),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      if (entry.key == 'captain incoming ride preview') {
        expect(b.activeRide, isNull);
        expect(find.byType(RideEndpointMarker), findsNWidgets(2));
      }
      if (entry.key == 'restaurant order details') {
        expect(find.text('المطعم — نقطة الاستلام'), findsNothing);
      }
      if (entry.key == 'captain wheel') {
        expect(find.byType(PrizeWheelPage), findsOneWidget);
        expect(find.text('العروض والخصومات'), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      if (entry.key == 'captain incoming ride preview')
        await tester.pump(const Duration(seconds: 13));
      await tester.pump(const Duration(milliseconds: 300));
      b.dispose();
      await tester.runAsync(() => b.db.dispose());
      await tester.binding.setSurfaceSize(null);
    });
  }
}
