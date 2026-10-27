import 'map_test_support.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:taktooka/core/app_theme.dart';
import 'package:taktooka/pages/about_page.dart';
import 'package:taktooka/pages/account_deletion.dart';
import 'package:taktooka/pages/captain_registration_page.dart';
import 'package:taktooka/pages/history_page.dart';
import 'package:taktooka/pages/home_page.dart';
import 'package:taktooka/pages/notifications_page.dart';
import 'package:taktooka/pages/offers_page.dart';
import 'package:taktooka/pages/privacy_page.dart';
import 'package:taktooka/pages/profile_page.dart';
import 'package:taktooka/pages/ride_map_page.dart';
import 'package:taktooka/pages/wallet_page.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/notifications.dart';
import 'package:taktooka/widgets/brand_title.dart';

class PreviewBackend extends Backend {
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
  @override
  bool get loggedIn => true;
  @override
  Future<void> refresh({
    bool lightweight = false,
    bool queueIfBusy = true,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

    await (FontLoader(
      'Cairo',
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await Supabase.initialize(
      url: 'https://example.test',
      anonKey: 'test-public',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient(
        (r) async => http.Response(
          '{"status":"draft","documents":{},"full_name":"كرار نبيل علي","province":"بغداد","area":"القاهرة"}',
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
  });
  void action() {}
  testWidgets(
    'Reference pages fit narrow and standard phones; wallet and coupon use live values',
    (tester) async {
      final oldShadows = debugDisableShadows;
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = oldShadows);
      final b = PreviewBackend()
        ..profile = {
          'name': 'كرار',
          'phone': '+9647736578908',
          'captain': false,
        }
        ..extras = {
          'balance': 5000,
          'coupon': {'amount': 1000, 'code': '158935792'},
          'ledger': [
            {
              'kind': 'refund',
              'amount': 2500,
              'created_at': '2026-10-10T18:39:00Z',
            },
            {
              'kind': 'ride_payment',
              'amount': -2500,
              'created_at': '2026-10-10T18:38:00Z',
            },
            {
              'kind': 'topup',
              'amount': 5000,
              'created_at': '2026-10-10T18:38:00Z',
            },
          ],
        };
      final notices = NotificationCenter(b, (_) {})
        ..inbox = [
          {
            'id': '1',
            'kind': 'wallet',
            'screen': 'wallet',
            'title': 'تحديث المحفظة',
            'body': 'تم تسجيل حركة مالية؛ افتح المحفظة لعرض التفاصيل',
          },
          {
            'id': '2',
            'kind': 'ride_status',
            'screen': 'ride',
            'title': 'تحديث مشوارك',
            'body': 'تم إلغاء الرحلة',
          },
          {
            'id': '3',
            'kind': 'wallet',
            'screen': 'wallet',
            'title': 'تحديث المحفظة',
            'body': 'تم تسجيل حركة مالية؛ افتح المحفظة لعرض التفاصيل',
          },
          {
            'id': '4',
            'kind': 'wallet',
            'screen': 'wallet',
            'title': 'تحديث المحفظة',
            'body': 'تم تسجيل حركة مالية؛ افتح المحفظة لعرض التفاصيل',
          },
          {
            'id': '5',
            'kind': 'coupon',
            'screen': 'offers',
            'title': 'عرض خصم جديد',
            'body': 'كود الخصم 158935792 متاح الآن؛ افتح العروض لمراجعة الشروط',
          },
        ];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            MethodChannel(
              'xyz.luan/audioplayers/events/${notices.player.playerId}',
            ),
            (_) async => null,
          );
      PreviewBackend activePreview(bool captain) => PreviewBackend()
        ..profile = {
          'captain': captain,
          'name': 'كرار',
          'expires_at': '2099-01-01',
        }
        ..activeRide = {
          'id': '00000000-0000-4000-8000-000000000123',
          'status': 'arrived',
          'fare': 1000,
          'customer_due': 1000,
          'payment_method': 'wallet',
          'pickup': [33.34, 44.401],
          'destination': [33.345, 44.406],
          'geometry': {
            'coordinates': [
              [44.401, 33.34],
              [44.401, 33.345],
              [44.406, 33.345],
            ],
          },
        }
        ..contact = {
          'name': captain ? 'كرار' : 'إيهاب',
          'phone': '+9647736578908',
          'location_at': '2020-01-01T00:00:00Z',
        };
      final captainTrip = activePreview(true), riderTrip = activePreview(false);
      b.rides = [
        for (final entry in [
          ('in_progress', 'wallet'),
          ('completed', 'cash'),
          ('cancelled', 'wallet'),
        ])
          {
            'id': '9ec2d2c4-1234',
            'status': entry.$1,
            'payment_method': entry.$2,
            'created_at': '2026-10-11T01:13:00Z',
            'pickup_name': 'القاهرة',
            'destination_name': 'الحسينية',
            'fare': 1500,
            'customer_due': 1500,
          },
      ];
      final pages = <String, Widget>{
        'history': HistoryPage(backend: b),
        'about': AboutPage(support: action),
        'privacy': const PrivacyPage(),
        'delete_account': AccountDeletionPage(backend: b),
        'home': HomePage(
          b: b,
          book: action,
          lines: action,
          history: action,
          offers: action,
          apply: action,
          city: action,
          support: action,
        ),
        'offers': OffersPage(b: b, run: (fn) => fn(), login: action),
        'account': ProfileHub(
          b: b,
          edit: action,
          wallet: action,
          history: action,
          addresses: action,
          offers: action,
          support: action,
          settings: action,
          about: action,
          invite: action,
        ),
        'wallet': WalletPage(b: b, support: action),
        'captain': CaptainRegistrationPage(backend: b),
        'notifications': NotificationsPage(center: notices),
        'captain_trip': RideMap(
          backend: captainTrip,
          busy: false,
          run: (fn) => fn(),
          toast: (_) {},
          openAccount: action,
        ),
        'rider_trip': RideMap(
          backend: riderTrip,
          busy: false,
          run: (fn) => fn(),
          toast: (_) {},
          openAccount: action,
        ),
        'review': RideMap(
          backend: b,
          busy: false,
          run: (fn) => fn(),
          toast: (_) {},
          openAccount: action,
        ),
      };
      for (final width in [360.0, 390.0]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 880);
        for (final entry in pages.entries) {
          final key = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('ar'),
              supportedLocales: const [Locale('ar')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: appTheme(),
              home: RepaintBoundary(
                key: key,
                child: ['captain', 'notifications'].contains(entry.key)
                    ? entry.value
                    : Scaffold(
                        appBar: AppBar(
                          title: const BrandTitle(),
                          centerTitle: true,
                          toolbarHeight: 72,
                        ),
                        body: entry.value,
                      ),
              ),
            ),
          );
          if (entry.key == 'review') {
            await tester.pump();
            await tester.pump();
            final dynamic state = tester.state(find.byType(RideMap));
            state.setState(() {
              state.bookingStep = 2;
              state.quote = {
                'fare': 1500,
                'distance_m': 1200,
                'duration_s': 180,
              };
              state.pickupLabel = 'شارع القاهرة';
              state.destinationLabel = 'شارع فلسطين';
            });
          }
          await tester.runAsync(() async {
            await precacheImage(
              const AssetImage('assets/brand.png'),
              key.currentContext!,
            );
            await precacheImage(
              const AssetImage('assets/hero.png'),
              key.currentContext!,
            );
          });
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          expect(
            tester.takeException(),
            isNull,
            reason: '${entry.key} at $width',
          );
          if (entry.key == 'notifications') {
            expect(find.text('إشعارات الجهاز مفعّلة'), findsNothing);
            expect(find.text('قراءة الكل'), findsOneWidget);
            expect(find.text('عرض خصم جديد'), findsOneWidget);
          }
          if (['captain_trip', 'rider_trip'].contains(entry.key)) {
            expect(find.textContaining('رمز بدء'), findsNothing);
            expect(
              tester.getRect(find.text('إلغاء الرحلة')).bottom,
              lessThanOrEqualTo(872),
              reason: '${entry.key} cancellation visible at $width',
            );
          }
          if (entry.key == 'review') {
            expect(find.text('شارع القاهرة'), findsOneWidget);
            expect(find.text('شارع فلسطين'), findsOneWidget);
            expect(find.text('اطلب تكتوكة'), findsOneWidget);
            expect(find.byIcon(Icons.person_outline), findsNothing);
            await tester.ensureVisible(find.text('اطلب تكتوكة'));
            await tester.pump();
            expect(
              tester.getBottomRight(find.text('اطلب تكتوكة')).dy,
              lessThan(880),
            );
          }
          if (entry.key == 'wallet')
            expect(find.text('5,000 د.ع'), findsOneWidget);
          if (entry.key == 'offers')
            expect(find.text('158935792'), findsOneWidget);
          if (entry.key == 'captain') {
            expect(find.text('الاسم الكامل'), findsOneWidget);
            expect(find.text('المحافظة'), findsOneWidget);
            expect(find.text('المنطقة'), findsOneWidget);
            expect(find.text('رقم شاصي المركبة'), findsNothing);
          }
          if (width == 390) {
            await tester.runAsync(() async {
              final img =
                  await (key.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 1.75);
              final bytes = await img.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory('build/design-preview').create(recursive: true);
              await File(
                'build/design-preview/${entry.key}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              img.dispose();
            });
          }
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 9));
      notices.dispose();
      await tester.pump();
      b.dispose();
      captainTrip.dispose();
      riderTrip.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDisableShadows = oldShadows;
    },
  );
  testWidgets('Used coupon shows its ride and expired coupons show expiry', (
    tester,
  ) async {
    final b = PreviewBackend();
    const rideId = '00000000-0000-4000-8000-000000000123';
    b.extras = {
      'coupon_history': [
        {
          'code': 'USED1000',
          'amount': 1000,
          'status': 'used',
          'expires_at': '2099-01-01T12:00:00Z',
          'ride_id': rideId,
        },
        {
          'code': 'OLD1000',
          'amount': 1000,
          'status': 'expired',
          'expires_at': '2020-01-01T12:00:00Z',
        },
      ],
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: OffersPage(b: b, run: (fn) => fn(), login: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('مستخدم'), findsWidgets);
    expect(find.textContaining('تاريخ الانتهاء:'), findsWidgets);
    expect(find.text('حذف الكود'), findsNothing);
    await tester.tap(find.text('كود الخصم').first);
    await tester.pumpAndSettle();
    expect(find.textContaining(rideId), findsOneWidget);
    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('OLD1000'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('منتهي'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    b.dispose();
  });
}
