import 'map_test_support.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:taktooka/core/app_theme.dart';
import 'package:taktooka/models/address_choice.dart';
import 'package:taktooka/pages/account_page.dart';
import 'package:taktooka/pages/phone_login_page.dart';
import 'package:taktooka/pages/profile_page.dart';
import 'package:taktooka/pages/ride_map_page.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/widgets/captain_application_banner.dart';

class BookingBackend extends Backend {
  int cancellations = 0;
  @override
  bool get loggedIn => true;
  @override
  Future<void> refresh({
    bool lightweight = false,
    bool queueIfBusy = true,
  }) async {}
  @override
  Future<dynamic> action(String action, [Json data = const {}]) async {
    if (action == 'ride_status' && data['status'] == 'cancelled')
      cancellations++;
    return {'ok': true};
  }

  @override
  Future<Position> locate({bool fresh = false}) async => Position(
    latitude: 33.34,
    longitude: 44.401,
    timestamp: DateTime.now(),
    accuracy: 10,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  Json? application;
  int quotes = 0;
  setUpAll(() async {
    await mockMapCacheDirectories();
    SharedPreferences.setMockInitialValues({});
    for (final name in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (_) async => null);
    }
    await Supabase.initialize(
      url: 'https://example.test',
      anonKey: 'test',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((request) async {
        dynamic result = application;
        if (request.url.path.contains('taktooka-pin')) {
          final body = jsonDecode(request.body) as Map;
          final chosen = List<num>.from(body['point']);
          result = {
            'point': [chosen[0] + .0003, chosen[1] + .0003],
            'name': 'شارع القاهرة',
            'address_complete': true,
          };
        } else if (request.url.path.contains('taktooka-quote')) {
          quotes++;
          result = {
            'id': 'quote',
            'fare': 1500,
            'distance_m': 1200,
            'duration_s': 300,
            'geometry': {
              'coordinates': [
                [44.401, 33.34],
                [44.41, 33.35],
              ],
            },
          };
        }
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  Widget screen(Widget child) => MaterialApp(
    theme: appTheme(),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: child),
    ),
  );

  testWidgets(
    'profile save remains available after parent runner becomes busy',
    (tester) async {
      final b = BookingBackend()
        ..profile = {'name': 'كرار', 'phone': '07700000000'};
      var parentCalls = 0;
      final messages = <String>[];
      await tester.pumpWidget(
        screen(
          AccountPage(
            backend: b,
            busy: true,
            run: (_) async {
              parentCalls++;
            },
            toast: messages.add,
          ),
        ),
      );
      await tester.tap(find.text('حفظ بياناتي'));
      await tester.pump();
      expect(parentCalls, 0);
      expect(messages, contains('تم حفظ بياناتك'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'حفظ بياناتي'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      b.dispose();
    },
  );

  testWidgets('captain profile hides rider addresses and coupons', (
    tester,
  ) async {
    final b = BookingBackend();
    void noop() {}
    for (final captain in [false, true]) {
      b.profile = {'name': 'كرار', 'captain': captain};
      await tester.pumpWidget(
        screen(
          ProfileHub(
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
        ),
      );
      expect(
        find.text('العناوين المفضلة'),
        captain ? findsNothing : findsOneWidget,
      );
      expect(find.text('قسائم الخصم'), captain ? findsNothing : findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    b.dispose();
  });

  testWidgets('locked login offers recovery rather than a disabled button', (
    tester,
  ) async {
    final b = BookingBackend();
    await tester.pumpWidget(screen(PhoneLoginPage(backend: b)));
    final dynamic state = tester.state(find.byType(PhoneLoginPage));
    state.setState(() {
      state.passwordStep = true;
      state.existing = true;
      state.locked = true;
    });
    await tester.pump();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'استرجاع الحساب'),
    );
    expect(button.onPressed, isNotNull);
    await tester.tap(find.text('استرجاع الحساب'));
    await tester.pumpAndSettle();
    expect(find.text('دعم استرجاع الحساب'), findsOneWidget);
    await tester.pump(const Duration(seconds: 21));
    await tester.pumpWidget(const SizedBox.shrink());
    b.dispose();
  });

  testWidgets('captain follow-up appears only for a pending application', (
    tester,
  ) async {
    final b = BookingBackend();
    for (final state in [
      null,
      'draft',
      'pending',
      'changes_required',
      'approved',
      'rejected',
    ]) {
      application = state == null ? null : {'status': state};
      await tester.pumpWidget(
        screen(
          CaptainApplicationBanner(
            key: ValueKey(state),
            backend: b,
            open: () {},
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      final dynamic banner = tester.state(
        find.byType(CaptainApplicationBanner),
      );
      banner.setState(() => banner.application = application);
      await tester.pump();
      expect(
        find.text('طلب الكابتن قيد المراجعة'),
        state == 'pending' ? findsOneWidget : findsNothing,
      );
      expect(find.text('أكمل تسجيل الكابتن'), findsNothing);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    b.dispose();
  });

  testWidgets(
    'road lookup snaps to the nearby street once and quotes on confirmation',
    (tester) async {
      final b = BookingBackend()
        ..profile = {'name': 'كرار', 'phone': '07700000000'};
      await tester.pumpWidget(
        screen(
          RideMap(
            backend: b,
            busy: false,
            run: (f) => f(),
            toast: (_) {},
            openAccount: () {},
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      final dynamic state = tester.state(find.byType(RideMap));
      state.bookingStep = 1;
      const chosen = LatLng(33.35, 44.41);
      state.selected(chosen);
      await tester.runAsync(() async {
        await state.snapPin();
      });
      await tester.pump(const Duration(seconds: 1));
      final road = LatLng(chosen.latitude + .0003, chosen.longitude + .0003);
      expect(state.destination, road);
      await tester.runAsync(() async {
        await state.snapPin();
      });
      expect(state.destination, road);
      expect(quotes, 0);
      await tester.runAsync(() async {
        await state.confirmPoint();
      });
      await tester.pump();
      expect(quotes, 1);
      expect(state.destination, road);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      b.dispose();
      await tester.pump(const Duration(seconds: 9));
    },
  );

  testWidgets(
    'shared destination quotes from current GPS without auto booking',
    (tester) async {
      quotes = 0;
      final b = BookingBackend()
        ..profile = {'name': 'كرار', 'phone': '07700000000'};
      await tester.pumpWidget(
        screen(
          RideMap(
            backend: b,
            busy: false,
            run: (f) => f(),
            toast: (_) {},
            openAccount: () {},
            favoriteDestination: AddressChoice(
              'الموقع المرسل إليك',
              const LatLng(33.35, 44.41),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      final dynamic state = tester.state(find.byType(RideMap));
      expect(state.pickup, const LatLng(33.34, 44.401));
      expect(state.destination, const LatLng(33.35, 44.41));
      expect(state.bookingStep, 2);
      expect(quotes, 1);
      expect(b.activeRide, isNull);
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpWidget(const SizedBox.shrink());
      b.dispose();
    },
  );

  testWidgets(
    'cancel button works even while generic background work is busy',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      final b = BookingBackend()
        ..activeRide = {
          'id': 'ride',
          'status': 'pending',
          'fare': 1500,
          'pickup': [33.34, 44.401],
          'destination': [33.35, 44.41],
          'payment_method': 'cash',
        };
      await tester.pumpWidget(
        screen(
          RideMap(
            backend: b,
            busy: true,
            run: (_) async {},
            toast: (_) {},
            openAccount: () {},
          ),
        ),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('إلغاء الرحلة'));
      await tester.pump();
      await tester.tap(find.text('إلغاء الرحلة'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'إلغاء الرحلة'));
      await tester.pumpAndSettle();
      expect(b.cancellations, 1);
      expect(b.activeRide, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      b.dispose();
    },
  );
}
