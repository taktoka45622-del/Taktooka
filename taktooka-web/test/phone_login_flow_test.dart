import 'dart:convert';
import 'package:taktooka/core/app_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:taktooka/core/app_theme.dart';
import 'package:taktooka/pages/phone_login_page.dart';
import 'package:taktooka/widgets/login_captain.dart';
import 'package:taktooka/services/backend.dart';

void main() {
  var accountExists = true;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      anonKey: 'test',
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        if (body['op'] == 'probe') {
          return http.Response(
            jsonEncode({'exists': accountExists, 'locked': false}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          '{"error":"WRONG_PASSWORD"}',
          401,
          headers: {'content-type': 'application/json'},
        );
      }),
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
  });

  setUp(() {
    accountExists = true;
    appPreferences.hasUsedAccount = true;
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(body: PhoneLoginPage(backend: Backend())),
      ),
    );
  }

  testWidgets('login asks only for phone and rejects an invalid number', (
    tester,
  ) async {
    await open(tester);
    expect(find.byType(TextFormField), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '123');
    await tester.tap(find.text('التالي'));
    await tester.pump();
    expect(find.text('اكتب رقم هاتف عراقي صحيح'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets(
    'registration asks for name and phone; system back returns to login',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('ليس لدي حساب — إنشاء حساب'));
      await tester.pump();
      expect(find.byType(TextFormField), findsNWidgets(2));
      await tester.enterText(find.byType(TextFormField).at(0), 'كرار نبيل');
      await tester.enterText(find.byType(TextFormField).at(1), '07701234567');
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('07701234567'), findsOneWidget);
      await tester.tap(find.text('ليس لدي حساب — إنشاء حساب'));
      await tester.pump();
      expect(find.text('كرار نبيل'), findsOneWidget);
    },
  );
  for (final size in [const Size(320, 568), const Size(844, 390)]) {
    testWidgets('registration scrolls with large text at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(body: PhoneLoginPage(backend: Backend())),
        ),
      );
      await tester.ensureVisible(find.text('ليس لدي حساب — إنشاء حساب'));
      await tester.tap(find.text('ليس لدي حساب — إنشاء حساب'));
      await tester.pump();
      expect(find.byType(TextFormField), findsNWidgets(2));
      await tester.scrollUntilVisible(
        find.text('لدي حساب — تسجيل الدخول'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('phone then password; back preserves phone', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextFormField), '07701234567');
    await tester.runAsync(() async {
      final dynamic state = tester.state(find.byType(PhoneLoginPage));
      await state.submit();
    });
    await tester.pumpAndSettle();
    expect(find.text('أدخل رمز حسابك'), findsOneWidget);
    expect(find.byType(LoginCaptain), findsNothing);
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pumpAndSettle();
    expect(find.byType(LoginCaptain), findsNothing);
    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pumpAndSettle();
    expect(find.byType(LoginCaptain), findsNothing);
    await tester.enterText(find.byType(TextFormField), 'wrong-password');
    await tester.runAsync(() async {
      final dynamic state = tester.state(find.byType(PhoneLoginPage));
      await state.submit();
    });
    await tester.pumpAndSettle();
    expect(
      find.text('كلمة المرور غير صحيحة، صححها وأعد المحاولة'),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('07701234567'), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
  });

  testWidgets('new account collects name and phone before password', (
    tester,
  ) async {
    accountExists = false;
    await open(tester);
    await tester.tap(find.text('ليس لدي حساب — إنشاء حساب'));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).at(0), 'كرار نبيل');
    await tester.enterText(find.byType(TextFormField).at(1), '07701234567');
    await tester.runAsync(() async {
      final dynamic state = tester.state(find.byType(PhoneLoginPage));
      await state.submit();
    });
    await tester.pumpAndSettle();
    expect(find.text('إنشاء رمز الحساب'), findsNWidgets(2));
    expect(find.byType(TextFormField), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('كرار نبيل'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'first use opens registration and remembered use opens login on $platform',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;

        SharedPreferences.setMockInitialValues({});
        await appPreferences.load();
        await open(tester);
        expect(find.text('إنشاء حساب'), findsOneWidget);
        expect(find.byType(TextFormField), findsNWidgets(2));
        await appPreferences.rememberAccountUse();
        await tester.pumpWidget(const SizedBox.shrink());
        appPreferences.hasUsedAccount = false;
        await appPreferences.load();
        await open(tester);
        expect(find.text('تسجيل الدخول'), findsOneWidget);
        expect(find.byType(TextFormField), findsOneWidget);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
