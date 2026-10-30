import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taktooka/core/app_theme.dart';
import 'package:taktooka/core/app_preferences.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/commerce.dart';
import 'package:taktooka/pages/registration_choice_page.dart';
import 'package:taktooka/pages/captain_registration_page.dart';
import 'package:taktooka/pages/commerce_page.dart';
import 'package:taktooka/pages/food_tracking_page.dart';
import 'package:taktooka/widgets/street_map_layer.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vector;
import 'map_test_support.dart';

class QaHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = HttpClient.findProxyFromEnvironment
        ..idleTimeout = Duration.zero;
}

void main() {
  final path = Platform.environment['TAKTOOKA_QA_ACCOUNTS'];
  if (path == null) {
    test(
      'Live UI suite requires explicit test-account fixture',
      () {},
      skip: true,
    );
    return;
  }
  LiveTestWidgetsFlutterBinding().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  late Map<String, dynamic> accounts;
  late IOClient client;
  final frame = GlobalKey();
  setUpAll(() async {
    accounts =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    SharedPreferences.setMockInitialValues({});
    await mockMapCacheDirectories();
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
    HttpOverrides.global = QaHttpOverrides();
    client = IOClient(
      HttpClient()..findProxy = HttpClient.findProxyFromEnvironment,
    );
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: publishableKey,
      debug: false,
      httpClient: client,
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
  });
  tearDownAll(() async {
    await Supabase.instance.dispose();
    client.close();
  });
  Future<Backend> login(WidgetTester tester, String role) async {
    final b = Backend();
    await tester.runAsync(() async {
      final auth = await b.db.auth.setSession(
        accounts[role]['refresh_token'] as String,
      );
      if (auth.session != null) {
        accounts[role]['refresh_token'] = auth.session!.refreshToken;
        File(path).writeAsStringSync(jsonEncode(accounts));
      }
      b.profile = Json.from(await b.action('me') as Map);
      b.commerce = Json.from(await commerceRpc(b, 'me') as Map);
    });
    return b;
  }

  Future<void> show(WidgetTester tester, Widget page) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: frame,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => PreferencesScope(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: GenderScope(child: child!),
            ),
          ),
          home: page,
        ),
      ),
    );
  }

  Future<void> waitText(WidgetTester tester, String text) async {
    for (var n = 0; n < 90; n++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text(text).evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
    }
    fail('Expected visible text: $text');
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      final boundary =
          frame.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('verification/ui').createSync(recursive: true);
      File(
        'verification/ui/$name.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('live registration choices and commission plan screen', (
    tester,
  ) async {
    final b = await login(tester, 'customer');
    await show(tester, RegistrationChoicePage(b: b));
    expect(find.text('تسجيل كابتن تكتك'), findsOneWidget);
    expect(find.text('تسجيل كابتن دراجة'), findsOneWidget);
    expect(find.text('لدي مطعم — تسجيل'), findsOneWidget);
    await capture(tester, 'registration-choices');
    await show(tester, CaptainRegistrationPage(backend: b));
    await waitText(tester, 'نظام النسبة');
    expect(find.text('الاشتراك الأسبوعي — 5,000 دينار'), findsOneWidget);
    await capture(tester, 'work-plans');
    await tester.pumpWidget(const SizedBox.shrink());
    b.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
  testWidgets('live restaurant dashboard, menu and settlement screen', (
    tester,
  ) async {
    final b = await login(tester, 'restaurant');
    await show(tester, FoodPage(b: b));
    await waitText(tester, 'إضافة صنف');
    expect(find.text('صنف تجريبي — ليس للبيع'), findsOneWidget);
    await capture(tester, 'restaurant-dashboard');
    await tester.tap(find.text('الحسابات والتسديد'));
    await tester.pump();
    await waitText(tester, 'نسبة التطبيق المأخوذة من الزبائن والمخزونة لديك');
    await capture(tester, 'restaurant-company-account');
    await tester.pumpWidget(const SizedBox.shrink());
    b.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
  testWidgets('live captain orders and company debt section', (tester) async {
    final b = await login(tester, 'commission');
    await show(tester, FoodPage(b: b));
    await waitText(tester, 'استقبال طلبات التوصيل');
    await tester.tap(find.text('الحسابات والتسديد'));
    await tester.pump();
    await waitText(tester, 'أموال الشركة — يجب تسديدها');
    await capture(tester, 'captain-company-account');
    await tester.pumpWidget(const SizedBox.shrink());
    b.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
  testWidgets('live customer history and closed restaurant reorder', (
    tester,
  ) async {
    final b = await login(tester, 'customer');
    await show(tester, FoodPage(b: b));
    await waitText(tester, 'الطلبات السابقة والحالية');
    await tester.tap(find.text('الطلبات السابقة والحالية'));
    await tester.pump();
    await waitText(tester, 'إعادة الطلب — مراجعة الأسعار الحالية');
    await capture(tester, 'customer-order-history');
    await tester.tap(find.text('إعادة الطلب — مراجعة الأسعار الحالية').first);
    await waitText(tester, 'المطعم مغلق حالياً أو غير متاح؛ جرّب لاحقاً');
    await capture(tester, 'customer-reorder-unavailable');
    await tester.pumpWidget(const SizedBox.shrink());
    b.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
  final statePath = Platform.environment['TAKTOOKA_QA_STATE'];
  if (statePath != null && File(statePath).existsSync()) {
    final state =
        jsonDecode(File(statePath).readAsStringSync()) as Map<String, dynamic>;
    if (state['active_order'] != null)
      testWidgets('live customer tracking map', (tester) async {
        final b = await login(tester, 'customer');
        await tester.runAsync(
          () => StreetMapLayer.loadStyle().timeout(const Duration(seconds: 60)),
        );
        await show(
          tester,
          FoodTrackingPage(
            b: b,
            orderId: state['active_order']['id'] as String,
          ),
        );
        await waitText(
          tester,
          foodStates[state['active_order']['status']] ?? 'وافق المندوب',
        );
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 250));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(seconds: 1)),
          );
        }
        expect(find.byType(vector.VectorTileLayer), findsOneWidget);
        await capture(tester, 'customer-live-tracking');
        await tester.pumpWidget(const SizedBox.shrink());
        b.dispose();
      }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
