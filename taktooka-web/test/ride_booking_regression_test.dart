import 'map_test_support.dart';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:taktooka/core/app_theme.dart';
import 'package:taktooka/models/address_choice.dart';
import 'package:taktooka/pages/account_page.dart';
import 'package:taktooka/pages/phone_login_page.dart';
import 'package:taktooka/pages/profile_page.dart';
import 'package:taktooka/pages/ride_map_page.dart';
import 'package:taktooka/pages/favorite_place_picker_page.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/device_booking.dart';
import 'package:taktooka/services/offline_roads.dart';
import 'package:taktooka/widgets/captain_application_banner.dart';
import 'package:taktooka/widgets/destination_pin.dart';

void mapTestWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    await http.runWithClient(
      () async {
        try {
          await callback(tester);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(seconds: 30));
        }
      },
      () => MockClient((request) async {
        if (request.url.path.contains('/tiles/')) {
          return http.Response.bytes(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQABpfZFQAAAAABJRU5ErkJggg==',
            ),
            200,
            headers: {'content-type': 'image/png', 'cache-control': 'no-store'},
          );
        }
        return http.Response('{}', 503);
      }),
    );
  });
}

class BookingBackend extends Backend {
  @override
  Future<Position> locatePrecise() => locate(fresh: true);
  Completer<Position>? delayedLocation;
  int cancellations = 0;
  int bookings = 0;
  @override
  void watchNearby() {}
  @override
  void unwatchNearby() {}
  @override
  Future<dynamic> dispatch(String op, [Json data = const {}]) async {
    if (op == 'book') {
      bookings++;
      return {
        'id': 'ride',
        'status': 'pending',
        'fare': data['expected_fare'],
        'pickup': [33.34, 44.401],
        'destination': [33.35, 44.41],
        'payment_method': 'cash',
      };
    }
    return {};
  }

  @override
  Future<void> kickDispatch() async {}
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
  Future<Position> locate({bool fresh = false}) async => delayedLocation != null
      ? delayedLocation!.future
      : Position(
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

class AvailabilityBackend extends BookingBackend {
  int activations = 0;
  @override
  Future<void> startTracking() async {
    activations++;
    tracking = true;
    notifyListeners();
  }
}

void main() {
  Json? application;
  int quotes = 0;
  int serverPins = 0;
  setUpAll(() async {
    await mockMapCacheDirectories();
    SharedPreferences.setMockInitialValues({});
    DeviceBooking.shared = DeviceBooking(
      client: MockClient((request) async {
        if (request.url.path.contains('directions')) {
          final coordinates = request.url.pathSegments.last
              .split(';')
              .first
              .split(',')
              .map(double.parse)
              .toList();
          return http.Response(
            jsonEncode({
              'code': 'Ok',
              'waypoints': [
                {
                  'location': [coordinates[0] + .0003, coordinates[1] + .0003],
                  'name': 'شارع القاهرة',
                },
              ],
              'routes': [
                {
                  'distance': 1200,
                  'duration': 300,
                  'geometry': {
                    'type': 'LineString',
                    'coordinates': [
                      [44.401, 33.34],
                      [44.41, 33.35],
                    ],
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(jsonEncode({'features': []}), 200);
      }),
    );
    OfflineRoads.shared.snapOverride = (lat, lng) =>
        DeviceBooking.shared.snap(LatLng(lat, lng));
    OfflineRoads.shared.routeOverride = (a, b, c, d) =>
        DeviceBooking.shared.route(LatLng(a, b), LatLng(c, d));
    for (final name in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (call) async {
            if (call.method == 'create' && call.arguments is Map) {
              final id = (call.arguments as Map)['playerId'];
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                  .setMockMethodCallHandler(
                    MethodChannel('xyz.luan/audioplayers/events/$id'),
                    (_) async => null,
                  );
            }
            return null;
          });
    }
    await Supabase.initialize(
      url: 'https://example.test',
      anonKey: 'test',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((request) async {
        dynamic result = application;
        if (request.url.path.contains('taktooka-pin')) {
          serverPins++;
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

  mapTestWidgets(
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

  mapTestWidgets('captain profile hides rider addresses and coupons', (
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

  mapTestWidgets('locked login offers recovery rather than a disabled button', (
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

  mapTestWidgets('captain follow-up appears only for a pending application', (
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

  mapTestWidgets(
    'road snapping is local and displayed fare is authorized before booking',
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
      expect(state.quote['id'], 'quote');
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

  mapTestWidgets('fare survives an unavailable local routing package', (
    tester,
  ) async {
    quotes = 0;
    final previous = OfflineRoads.shared.routeOverride;
    OfflineRoads.shared.routeOverride = (a, b, c, d) async =>
        throw StateError('LOCAL_ROUTING_UNAVAILABLE');
    final b = BookingBackend()
      ..profile = {'name': 'كرار', 'phone': '07700000000'};
    try {
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
      state.bookingStep = 2;
      state.destination = const LatLng(33.35, 44.41);
      await tester.runAsync(() async {
        await state.calculate();
      });
      await tester.pump();
      expect(quotes, 1);
      expect(state.quote['fare'], 1500);
      expect(state.quoting, false);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      b.dispose();
      OfflineRoads.shared.routeOverride = previous;
    }
  });

  mapTestWidgets('GPS waiting leaves map visible and preserves manual pickup', (
    tester,
  ) async {
    final b = BookingBackend()
      ..profile = {'name': 'كرار', 'phone': '07700000000'}
      ..delayedLocation = Completer<Position>();
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
    await tester.pump();
    expect(find.text('جاري تحديد موقعك الحالي'), findsNothing);
    expect(find.text('تأكيد نقطة الانطلاق'), findsOneWidget);
    final dynamic state = tester.state(find.byType(RideMap));
    const selected = LatLng(33.35, 44.41);
    state.selected(selected);
    b.delayedLocation!.complete(
      Position(
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
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    expect(state.pickup, selected);
    await tester.pumpWidget(const SizedBox.shrink());
    b.dispose();
  });

  mapTestWidgets(
    'location button immediately uses a fresh fix without global loading',
    (tester) async {
      final b = BookingBackend()
        ..profile = {'name': 'كرار', 'phone': '07700000000'};
      var runnerCalls = 0;
      await tester.pumpWidget(
        screen(
          RideMap(
            backend: b,
            busy: false,
            run: (f) async {
              runnerCalls++;
              await f();
            },
            toast: (_) {},
            openAccount: () {},
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      b.position = Position(
        latitude: 33.36,
        longitude: 44.42,
        timestamp: DateTime.now(),
        accuracy: 12,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      b.delayedLocation = Completer<Position>();
      final dynamic state = tester.state(find.byType(RideMap));
      await state.locate();
      expect(state.myLocation, const LatLng(33.36, 44.42));
      expect(state.pickup, const LatLng(33.36, 44.42));
      expect(runnerCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      b.dispose();
    },
  );

  mapTestWidgets('pin settles before a pending street lookup completes', (
    tester,
  ) async {
    final b = BookingBackend()
      ..profile = {'name': 'كرار', 'phone': '07700000000'};
    final original = OfflineRoads.shared.snapOverride;
    final gate = Completer<Map<String, dynamic>>();
    try {
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
      await tester.pump(const Duration(milliseconds: 200));
      OfflineRoads.shared.snapOverride = (a, c) => gate.future;
      final dynamic state = tester.state(find.byType(RideMap));
      state.bookingStep = 1;
      state.selected(const LatLng(33.35, 44.41));
      await tester.pump();
      expect(
        tester.widget<DestinationPin>(find.byType(DestinationPin)).moving,
        true,
      );
      await tester.pump(const Duration(milliseconds: 181));
      expect(
        tester.widget<DestinationPin>(find.byType(DestinationPin)).moving,
        false,
      );
      expect(gate.isCompleted, false);
      gate.complete({
        'point': [33.35, 44.41],
        'name': 'شارع القاهرة',
      });
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 200));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      b.dispose();
      OfflineRoads.shared.snapOverride = original;
    }
  });

  mapTestWidgets(
    'captain marker follows new GPS instead of the cached map location',
    (tester) async {
      final b = AvailabilityBackend()
        ..profile = {
          'captain': true,
          'name': 'Test',
          'expires_at': DateTime.now()
              .add(const Duration(days: 1))
              .toIso8601String(),
        };
      Position gps(double lat, double lng) => Position(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime.now(),
        accuracy: 8,
        altitude: 0,
        altitudeAccuracy: 1,
        heading: 0,
        headingAccuracy: 1,
        speed: 0,
        speedAccuracy: 1,
      );
      b.acceptCaptainFix(gps(33.34, 44.4));
      await tester.pumpWidget(
        screen(
          AnimatedBuilder(
            animation: b,
            builder: (_, _) => RideMap(
              backend: b,
              busy: false,
              run: (f) => f(),
              toast: (_) {},
              openAccount: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      b.acceptCaptainFix(gps(33.341, 44.401));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final dynamic state = tester.state(find.byType(RideMap));
      expect(state.myLocation, const LatLng(33.341, 44.401));
      final layers = tester.widgetList<MarkerLayer>(find.byType(MarkerLayer));
      expect(
        layers
            .expand((layer) => layer.markers)
            .where((m) => m.width == 28)
            .single
            .point,
        const LatLng(33.341, 44.401),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      b.dispose();
    },
  );

  mapTestWidgets(
    'availability starts without waiting for Firebase token registration',
    (tester) async {
      final b = AvailabilityBackend()
        ..profile = {
          'captain': true,
          'name': 'Test',
          'expires_at': DateTime.now()
              .add(const Duration(days: 1))
              .toIso8601String(),
        };
      final token = Completer<void>();
      b.enableOrderNotifications = () => token.future;
      await tester.pumpWidget(
        screen(
          AnimatedBuilder(
            animation: b,
            builder: (_, _) => RideMap(
              backend: b,
              busy: false,
              run: (f) => f(),
              toast: (_) {},
              openAccount: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('تفعيل لاستقبال الطلبات'));
      await tester.pump();
      expect(b.activations, 1);
      expect(token.isCompleted, false);
      expect(find.text('إيقاف استلام الطلبات'), findsOneWidget);
      token.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      b.dispose();
    },
  );

  for (final origin in [true, false]) {
    mapTestWidgets(
      'favorite and line picker keep anchor during zoom ($origin)',
      (tester) async {
        final b = BookingBackend();
        await tester.pumpWidget(
          screen(
            FavoritePlacePicker(
              b: b,
              origin: origin,
              title: origin ? null : 'حدد نقطة الوصول',
              existing: {'label': 'البيت', 'lat': 33.34, 'lng': 44.401},
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump(const Duration(milliseconds: 300));
        final dynamic state = tester.state(find.byType(FavoritePlacePicker));
        final selected = state.point;
        final revision = state.sequence;
        final old = state.map.camera as MapCamera;
        state.handleMapEvent(
          MapEventScrollWheelZoom(
            source: MapEventSource.scrollWheel,
            oldCamera: old,
            camera: old.withPosition(
              center: const LatLng(33.6, 44.6),
              zoom: old.zoom - 2,
            ),
          ),
        );
        await tester.pump();
        expect(state.point, selected);
        expect(state.map.camera.center, selected);
        expect(state.sequence, revision);
        expect(state.map.camera.zoom, old.zoom - 2);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        b.dispose();
      },
    );
  }

  mapTestWidgets(
    'pinch zoom keeps the selected coordinate and does not restart street lookup',
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
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final dynamic state = tester.state(find.byType(RideMap));
      final selected = state.pickup;
      final pinRevision = state.pinSeq;
      final beforeZoom = state.controller.camera.zoom as double;
      final center = tester.getCenter(find.byType(FlutterMap));
      final first = await tester.startGesture(
        center + const Offset(-40, -20),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(40, -20),
        pointer: 2,
      );
      await tester.pump();
      await first.moveTo(center + const Offset(-100, -20));
      await second.moveTo(center + const Offset(100, -20));
      await tester.pump(const Duration(milliseconds: 30));
      await first.up();
      await second.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.controller.camera.zoom, isNot(beforeZoom));
      expect(state.pickup, selected);
      expect(state.pinSeq, pinRevision);
      final old = state.controller.camera;
      state.handleMapEvent(
        MapEventScrollWheelZoom(
          source: MapEventSource.scrollWheel,
          oldCamera: old,
          camera: old.withPosition(
            center: const LatLng(33.6, 44.6),
            zoom: old.zoom - 2,
          ),
        ),
      );
      await tester.pump();
      expect(state.pickup, selected);
      expect(state.controller.camera.center, selected);
      expect(state.pinSeq, pinRevision);
      await tester.pumpWidget(const SizedBox.shrink());
      b.dispose();
    },
  );

  mapTestWidgets('one finger pan still selects a new point', (tester) async {
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
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final dynamic state = tester.state(find.byType(RideMap));
    final before = state.pickup;
    await tester.drag(find.byType(FlutterMap), const Offset(70, 35));
    await tester.pump(const Duration(milliseconds: 20));
    expect(state.pickup, isNot(before));
    await tester.pumpWidget(const SizedBox.shrink());
    b.dispose();
  });

  mapTestWidgets(
    'cold street correction uses the direct provider before the server fallback',
    (tester) async {
      final b = BookingBackend()
        ..profile = {'name': 'كرار', 'phone': '07700000000'};
      final original = OfflineRoads.shared.snapOverride;
      try {
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
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump(const Duration(milliseconds: 300));
        OfflineRoads.shared.snapOverride = null;
        final dynamic state = tester.state(find.byType(RideMap));
        state.bookingStep = 1;
        state.selected(const LatLng(33.35, 44.41));
        final beforeServer = serverPins;
        await tester.runAsync(() async {
          expect(await state.snapPin(), true);
        });
        expect(state.destination.latitude, closeTo(33.3503, 1e-8));
        expect(state.destination.longitude, closeTo(44.4103, 1e-8));
        expect(serverPins, beforeServer);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        OfflineRoads.shared.snapOverride = original;
        b.dispose();
      }
    },
  );

  mapTestWidgets('area label arrives while road correction is still pending', (
    tester,
  ) async {
    final b = BookingBackend()
      ..profile = {'name': 'كرار', 'phone': '07700000000'};
    final originalSnap = OfflineRoads.shared.snapOverride;
    final originalBooking = DeviceBooking.shared;
    final gate = Completer<Map<String, dynamic>>();
    try {
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
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      DeviceBooking.shared = DeviceBooking(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'features': request.url.path.contains('geocode')
                  ? [
                      {
                        'geometry': {
                          'coordinates': [44.41, 33.35],
                        },
                        'properties': {
                          'feature_type': 'street',
                          'name': 'شارع أبو جلال',
                          'context': {
                            'region': {'name': 'بغداد'},
                            'locality': {'name': 'القاهرة'},
                          },
                        },
                      },
                    ]
                  : [],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      OfflineRoads.shared.snapOverride = (a, c) => gate.future;
      final dynamic state = tester.state(find.byType(RideMap));
      state.bookingStep = 1;
      state.selected(const LatLng(33.35, 44.41));
      await tester.pump(const Duration(milliseconds: 181));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(gate.isCompleted, false);
      expect(state.destinationLabel, contains('القاهرة'));
      gate.complete({
        'point': [33.35, 44.41],
        'name': 'شارع أبو جلال',
        'street': 'شارع أبو جلال',
      });
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(state.destinationLabel, contains('القاهرة'));
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      OfflineRoads.shared.snapOverride = originalSnap;
      DeviceBooking.shared = originalBooking;
      b.dispose();
    }
  });

  mapTestWidgets(
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
      for (var attempt = 0; attempt < 20 && state.quote == null; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(state.pickup, const LatLng(33.34, 44.401));
      expect(state.destination, const LatLng(33.35, 44.41));
      expect(state.bookingStep, 2);
      expect(quotes, 1);
      expect(state.quote['id'], 'quote');
      expect(b.activeRide, isNull);
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpWidget(const SizedBox.shrink());
      b.dispose();
    },
  );

  for (final status in ['pending', 'accepted']) {
    mapTestWidgets(
      'customer route and route button follow captain acceptance ($status)',
      (tester) async {
        final shape = {
          'type': 'LineString',
          'coordinates': [
            [44.401, 33.34],
            [44.41, 33.35],
          ],
        };
        final b = BookingBackend()
          ..activeRide = {
            'id': 'ride',
            'status': status,
            'fare': 1500,
            'pickup': [33.34, 44.401],
            'destination': [33.35, 44.41],
            'geometry': shape,
            'payment_method': 'cash',
            'navigation': {
              'ride_id': 'ride',
              'phase': '$status::0',
              'geometry': shape,
            },
          };
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
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          find.byType(PolylineLayer),
          status == 'accepted' ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('عرض المسار'),
          status == 'accepted' ? findsOneWidget : findsNothing,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        b.dispose();
      },
    );
  }

  mapTestWidgets(
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
