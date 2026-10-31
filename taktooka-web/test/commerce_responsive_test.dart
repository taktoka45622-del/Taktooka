import 'package:image/image.dart' as raster;
import 'package:taktooka/services/persistent_map_client.dart';
import 'package:taktooka/pages/home_page.dart';
import 'package:latlong2/latlong.dart';
import 'package:taktooka/models/address_choice.dart';
import 'package:taktooka/pages/food_checkout_page.dart';
import 'package:taktooka/pages/registration_choice_page.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taktooka/core/commerce_theme.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/pages/commerce_page.dart';
import 'package:taktooka/pages/commerce_dialogs.dart';
import 'package:taktooka/pages/meal_editor_page.dart';
import 'package:taktooka/pages/restaurant_settings_page.dart';
import 'package:taktooka/pages/restaurant_couriers_page.dart';
import 'package:taktooka/pages/captain_registration_page.dart';
import 'package:taktooka/pages/captain_service_preferences.dart';
import 'package:taktooka/pages/food_order_details_page.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/widgets/commerce_ui.dart';
import 'package:taktooka/widgets/keyboard_dismiss.dart';

import 'map_test_support.dart';

const actor = '11111111-1111-4111-8111-111111111111';
const shopId = '22222222-2222-4222-8222-222222222222';
var role = 'owner';
final shop = <String, dynamic>{
  'id': shopId,
  'owner_id': actor,
  'name': 'مطعم إمام ويس للوجبات السريعة',
  'phone': '+9647701234567',
  'address': 'بغداد — الحسينية، قرب شارع الطاقة',
  'description': 'وجبات طازجة كل يوم',
  'image_path': 'shop.jpg',
  'location': [33.55, 44.42],
  'open': true,
  'self_delivery': true,
  'closing_time': '23:30',
  'distance_km': 2.4,
};
final meal = <String, dynamic>{
  'id': 'meal',
  'name': 'بركر لحم مع الجبنة والصوص الخاص',
  'description': 'لحم بقري طازج مع الخضار والجبنة والصوص الخاص بالمطعم',
  'price': 25000,
  'previous_price': 30000,
  'category': 'بركر',
  'image_path': 'meal.jpg',
  'image_paths': ['meal.jpg', 'meal2.jpg'],
  'available': true,
  'sort_order': 0,
};
Map<String, dynamic> get order => {
  'id': '33333333-3333-4333-8333-333333333333',
  'restaurant_id': shopId,
  'restaurant_name': shop['name'],
  'restaurant_phone': shop['phone'],
  'restaurant_address': shop['address'],
  'restaurant_location': shop['location'],
  'customer_name': 'محمد أحمد عبد الله',
  'customer_phone': '+9647712345678',
  'customer_address': 'بغداد — الحسينية، شارع السوق، مقابل المدرسة',
  'customer_location': [33.56, 44.43],
  'captain_id': null,
  'status': 'searching',
  'delivery_mode': 'private',
  'items': [
    {'id': 'meal', 'name': meal['name'], 'price': 25000, 'quantity': 2},
  ],
  'food_total': 50000,
  'delivery_fee': 2500,
  'service_fee': 500,
  'commission_amount': 0,
  'created_at': DateTime.now().toUtc().toIso8601String(),
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};
final settlement = <String, dynamic>{
  'id': '44444444-4444-4444-8444-444444444444',
  'kind': 'captain_restaurant',
  'amount': 1250000,
  'status': 'pending',
  'recipient_name': 'مطعم إمام ويس للوجبات السريعة',
  'payer_name': 'أحمد محمد عبد الله — مندوب المطعم',
  'payer_phone': '+9647701234567',
  'created_at': '2026-10-31T08:30:00Z',
};
Map<String, dynamic> get responseMe => {
  'restaurant': role == 'owner' ? shop : null,
  'restaurant_stats': {'today_orders': 125, 'today_sales': 1250000},
  'restaurant_min_distance_m': 999999,
  'restaurant_max_distance_m': 1000000,
  'plan': 'weekly',
  'vehicle': 'tuktuk',
  'receive_food': true,
  'receive_rides': true,
  'food_active': false,
  'debt_blocked': false,
  if (role == 'private')
    'self_courier': {'active': true, 'restaurant_id': shopId},
};

class PreviewBackend extends Backend {
  @override
  Position? get knownPosition => Position(
    latitude: 33.55,
    longitude: 44.42,
    timestamp: DateTime.now(),
    accuracy: 10,
    altitude: 0,
    altitudeAccuracy: 1,
    heading: 0,
    headingAccuracy: 1,
    speed: 0,
    speedAccuracy: 1,
  );
  @override
  Future<void> refresh({
    bool lightweight = false,
    bool queueIfBusy = true,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await mockMapCacheDirectories();
    // Freeze only the tile transport; Supabase retains its separate RPC fixture.
    http.runWithClient(
      () => PersistentMapClient.shared,
      () => MockClient(
        (request) async => http.Response.bytes(
          raster.encodePng(
            raster.Image(width: 256, height: 256)
              ..clear(raster.ColorRgb8(240, 240, 240)),
          ),
          200,
          headers: {'content-type': 'image/png'},
        ),
      ),
    );
    await Supabase.initialize(
      url: 'https://layout.test',
      anonKey: 'fixture',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        dynamic data;
        if (request.url.path.contains('/auth/v1/token')) {
          String part(Object v) =>
              base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
          data = {
            'access_token':
                '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': actor, 'exp': 4102444800, 'aud': 'authenticated', 'role': 'authenticated'})}.fixture',
            'refresh_token': 'fixture',
            'expires_in': 31536000,
            'token_type': 'bearer',
            'user': {
              'id': actor,
              'aud': 'authenticated',
              'role': 'authenticated',
              'email': 'fixture@layout.test',
              'created_at': '2026-01-01T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            },
          };
        } else {
          final p = request.body.isEmpty ? {} : jsonDecode(request.body) as Map;
          final action = p['p_action'];
          if (const bool.fromEnvironment('TRACE_LAYOUT'))
            print('RPC ${request.method} ${request.url.path}: $action');
          data = switch (action) {
            'me' => responseMe,
            'orders' => [order],
            'order_details' => order,
            'restaurants' => [shop],
            'menu' => [meal],
            'categories' => ['بركر', 'بيتزا'],
            'catalog' => [],
            'accounts' => {
              'statistics': [],
              'debts': [],
              'settlements': [settlement],
            },
            'courier_list' => [
              {
                'user_id': 'courier',
                'name': 'أحمد محمد عبد الله — مندوب المطعم',
                'phone': '+9647712345678',
                'active': true,
                'online': true,
                'busy': false,
                'location_at': DateTime.now().toUtc().toIso8601String(),
                'lat': 33.55,
                'lng': 44.42,
                'due': 1250000,
                'cash_collected': 1500000,
                'delivery_total': 250000,
                'delivered': 100,
                'settlements': [settlement],
              },
            ],
            'get' => null,
            _ => [],
          };
        }
        if (request.body.isNotEmpty && request.url.path.contains('/rpc/')) {
          final p = jsonDecode(request.body) as Map;
          if (p['p_action'] == 'restaurant_open') {
            shop['open'] = p['p_data']['open'];
            data = {...shop};
          }
        }
        return http.Response(
          jsonEncode(data),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'fixture@layout.test',
      password: 'local-fixture-only',
    );
    final snapshot = await Supabase.instance.client.rpc(
      'tkt_commerce',
      params: {'p_action': 'me', 'p_data': {}},
    );
    expect(snapshot, isA<Map>());
    expect(snapshot['restaurant'], isNotNull);
    for (final f in [
      ('Cairo', 'assets/fonts/Cairo.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ])
      await (FontLoader(f.$1)..addFont(rootBundle.load(f.$2))).load();
  });
  tearDownAll(() async {
    await Supabase.instance.dispose();
  });
  Future<void> open(
    WidgetTester tester,
    Widget page,
    Size size,
    double scale, {
    GlobalKey? capture,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(
      MaterialApp(
        theme: commerceTheme(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: GenderScope(
              child: DismissKeyboardOnOutsideTap(child: child!),
            ),
          ),
        ),
        home: capture == null
            ? page
            : RepaintBoundary(key: capture, child: page),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
  }

  Future<void> close(WidgetTester tester, PreviewBackend b) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(seconds: 15));
    b.dispose();
    debugDefaultTargetPlatformOverride = null;
    tester.view.resetViewInsets();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }

  Future<void> scroll(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    if (find.byType(Scrollable).evaluate().isNotEmpty)
      for (var i = 0; i < 5; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      }
  }

  final sizes = [
    const Size(320, 568),
    const Size(360, 640),
    const Size(390, 844),
    const Size(430, 932),
    const Size(568, 320),
    const Size(844, 390),
    const Size(768, 1024),
  ];
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS])
    for (final size in sizes)
      for (final scale in [1.0, 1.5, 2.0])
        for (final name in [
          'owner',
          'customer',
          'courier',
          'private',
          'meal',
          'settings',
          'couriers',
          'plans',
          'details',
          'ledger',
          'checkout',
          'registration',
          'customer_details',
        ]) {
          testWidgets('$name $platform $size text=$scale', (tester) async {
            debugDefaultTargetPlatformOverride = platform;
            role = ['owner', 'customer', 'courier', 'private'].contains(name)
                ? name
                : name == 'customer_details'
                ? 'customer'
                : 'owner';
            final b = PreviewBackend()
              ..profile = {
                'name': 'محمد أحمد',
                'phone': '+9647701234567',
                'captain': role == 'courier',
                'expires_at': '2099-01-01',
              }
              ..commerce = responseMe;
            final page = switch (name) {
              'checkout' => FoodCheckoutPage(
                restaurant: shop,
                items: [
                  {...meal, 'quantity': 2},
                ],
                place: const AddressChoice(
                  'بغداد — الحسينية، شارع السوق، مقابل المدرسة',
                  LatLng(33.55, 44.42),
                ),
                delivery: 1500,
                serviceFee: 500,
                photo: (dynamic path, {double height = 100}) => SizedBox(
                  height: height,
                  child: const Icon(Icons.restaurant),
                ),
              ),
              'registration' => RegistrationChoicePage(b: b),
              'customer_details' => FoodOrderDetailsPage(b: b, initial: order),
              'meal' => MealEditorPage(b: b, meal: meal),
              'settings' => RestaurantSettingsPage(b: b, restaurant: shop),
              'couriers' => RestaurantCouriersPage(b: b, enabled: true),
              'plans' => CaptainRegistrationPage(backend: b),
              'details' => FoodOrderDetailsPage(b: b, initial: order),
              'ledger' => Scaffold(
                body: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    SettlementRecord(record: settlement),
                    const CommerceAmountRow(
                      'الكاش المطلوب من الزبون',
                      1250000,
                      total: true,
                    ),
                  ],
                ),
              ),
              _ => FoodPage(b: b),
            };
            try {
              await open(tester, page, size, scale);
              if (name == 'owner')
                expect(find.text('إضافة وجبة'), findsOneWidget);
              if (name == 'couriers') {
                for (
                  var i = 0;
                  i < 5 &&
                      find
                          .text('أحمد محمد عبد الله — مندوب المطعم')
                          .evaluate()
                          .isEmpty;
                  i++
                ) {
                  await tester.drag(
                    find.byType(Scrollable).first,
                    const Offset(0, -200),
                  );
                  await tester.pump(const Duration(milliseconds: 100));
                }
                expect(
                  find.text('أحمد محمد عبد الله — مندوب المطعم'),
                  findsOneWidget,
                );
              }
              await scroll(tester);
            } finally {
              await close(tester, b);
            }
          });
        }
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS])
    for (final size in [const Size(320, 568), const Size(568, 320)])
      for (final name in ['cancel', 'code', 'services']) {
        testWidgets('sheet $name $platform $size text=2 keyboard', (
          tester,
        ) async {
          debugDefaultTargetPlatformOverride = platform;
          role = 'owner';
          final b = PreviewBackend()
            ..profile = {'captain': false}
            ..commerce = responseMe;
          try {
            await open(
              tester,
              Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () {
                      if (name == 'cancel') {
                        foodCancellationReason(context, customer: false);
                      } else if (name == 'code') {
                        showRestaurantSettlementCode(context, {
                          ...settlement,
                          'code': '349530',
                        });
                      } else {
                        showCaptainServicePreferences(context, b);
                      }
                    },
                    child: const Text('فتح'),
                  ),
                ),
              ),
              size,
              2,
            );
            await tester.tap(find.text('فتح'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (name == 'cancel') {
              await tester.ensureVisible(find.text('سبب آخر'));
              await tester.tap(find.text('سبب آخر'));
              await tester.pumpAndSettle();
              await tester.tap(find.byType(TextField));
              tester.view.viewInsets = const FakeViewPadding(bottom: 180);
              await tester.pump();
              await tester.enterText(
                find.byType(TextField),
                'سبب الإلغاء للاختبار',
              );
              await tester.pump();
            }
            await scroll(tester);
          } finally {
            await close(tester, b);
          }
        });
      }
  testWidgets('customer cannot see finance or private dispatch details', (
    tester,
  ) async {
    role = 'customer';
    final b = PreviewBackend()
      ..profile = {'captain': false}
      ..commerce = responseMe;
    try {
      await open(tester, FoodPage(b: b), const Size(390, 844), 1);
      expect(find.text('الحسابات'), findsNothing);
      await tester.tap(find.text('طلباتي'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
      expect(find.text('عنوان الزبون'), findsNothing);
      expect(find.text('هاتف الزبون'), findsNothing);
      expect(find.text('الكاش المطلوب من الزبون'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await close(tester, b);
    }
  });
  testWidgets('owner switches reception off and on without image upload', (
    tester,
  ) async {
    role = 'owner';
    shop['open'] = true;
    final b = PreviewBackend()
      ..profile = {'captain': false}
      ..commerce = responseMe;
    try {
      await open(tester, FoodPage(b: b), const Size(390, 844), 1);
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
      expect(shop['open'], false);
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
      expect(shop['open'], true);
      expect(tester.takeException(), isNull);
    } finally {
      shop['open'] = true;
      await close(tester, b);
    }
  });
  for (final size in [const Size(320, 568), const Size(568, 320)])
    testWidgets('finance is visible on the very first tap $size', (
      tester,
    ) async {
      role = 'owner';
      final b = PreviewBackend()
        ..profile = {'captain': false}
        ..commerce = responseMe;
      final key = GlobalKey();
      try {
        await open(tester, FoodPage(b: b), size, 2, capture: key);
        await tester.tap(find.text('الحسابات'));
        await tester.pump();
        expect(find.text('مستحقات تكتوكة'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pump();
        await scroll(tester);
      } finally {
        await close(tester, b);
      }
    });
  testWidgets('commission captain keeps both feature locations with locks', (
    tester,
  ) async {
    role = 'courier';
    final b = PreviewBackend()
      ..profile = {'captain': true, 'expires_at': '2099-01-01'}
      ..commerce = {...responseMe, 'plan': 'commission', 'vehicle': 'tuktuk'};
    try {
      await open(
        tester,
        HomePage(
          b: b,
          book: () {},
          history: () {},
          lines: () {},
          offers: () {},
          apply: () {},
          city: () {},
          support: () {},
        ),
        const Size(390, 844),
        1,
      );
      expect(find.text('الخطوط'), findsOneWidget);
      expect(find.text('طلبات الطعام'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
      await scroll(tester);
    } finally {
      await close(tester, b);
    }
  });
  testWidgets('capture loaded commerce screens', (tester) async {
    role = 'owner';
    final b = PreviewBackend()
      ..profile = {
        'name': 'محمد أحمد',
        'phone': '+9647701234567',
        'captain': false,
      }
      ..commerce = responseMe;
    for (final sample in [
      ('restaurant-dashboard', FoodPage(b: b)),
      ('customer-home', FoodPage(b: b)),
      ('customer-tracking', FoodOrderDetailsPage(b: b, initial: order)),
      ('registration', RegistrationChoicePage(b: b)),
      (
        'checkout',
        FoodCheckoutPage(
          restaurant: shop,
          items: [
            {...meal, 'quantity': 1},
          ],
          place: const AddressChoice('بغداد — الحسينية', LatLng(33.55, 44.42)),
          delivery: 1500,
          serviceFee: 500,
          photo: (dynamic p, {double height = 100}) =>
              SizedBox(height: height, child: const Icon(Icons.restaurant)),
        ),
      ),
      ('finance', FoodPage(b: b)),
      ('meal-editor', MealEditorPage(b: b, meal: meal)),
      ('couriers', RestaurantCouriersPage(b: b, enabled: true)),
      (
        'settlement',
        Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [SettlementRecord(record: settlement)],
          ),
        ),
      ),
    ]) {
      role = sample.$1.startsWith('customer') ? 'customer' : 'owner';
      b.commerce = responseMe;
      final key = GlobalKey();
      await open(tester, sample.$2, const Size(390, 844), 1, capture: key);
      if (sample.$1 == 'finance') {
        await tester.tap(find.text('الحسابات'));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pump();
      }
      if (sample.$1 == 'restaurant-dashboard')
        expect(find.text('إضافة وجبة'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('verification/responsive').createSync(recursive: true);
        File(
          'verification/responsive/${sample.$1}.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pump(const Duration(seconds: 15));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
    b.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
