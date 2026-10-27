import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:taktooka/core/app_preferences.dart';
import 'package:taktooka/core/app_theme.dart';
import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/pages/account_page.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/widgets/preferences_panel.dart';

class ProfileBackend extends Backend {
  Json? saved;
  @override
  bool get loggedIn => true;
  @override
  Future<dynamic> action(String action, [Json data = const {}]) async {
    if (action == 'profile') saved = Map.of(data);
    return {'ok': true};
  }

  @override
  Future<void> refresh({
    bool lightweight = false,
    bool queueIfBusy = true,
  }) async {}
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await (FontLoader(
      'Cairo',
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await Supabase.initialize(
      url: 'https://example.test',
      anonKey: 'test',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appPreferences.language = 'ar';
    appPreferences.themeMode = ThemeMode.light;
    accountGender.value = 'male';
  });
  Widget screen(Widget child) => AnimatedBuilder(
    animation: appPreferences,
    builder: (context, _) => MaterialApp(
      theme: appTheme(),
      darkTheme: appDarkTheme(),
      themeMode: appPreferences.themeMode,
      builder: (context, child) => PreferencesScope(
        child: GenderScope(
          child: Directionality(
            textDirection: appPreferences.language == 'en'
                ? TextDirection.ltr
                : TextDirection.rtl,
            child: child!,
          ),
        ),
      ),
      home: Scaffold(body: child),
    ),
  );

  test(
    'language and theme survive loading a fresh settings instance',
    () async {
      await appPreferences.setLanguage('ku');
      await appPreferences.setTheme(ThemeMode.dark);
      final restored = AppPreferences();
      await restored.load();
      expect(restored.language, 'ku');
      expect(restored.themeMode, ThemeMode.dark);
      await restored.setLanguage('unsupported');
      expect(restored.language, 'ku');
      restored.dispose();
    },
  );
  test('gender copy preserves third parties, addresses and numeric values', () {
    expect(
      genderText('وين تريد تروح اليوم؟', gender: 'female'),
      'وين تريدين نروح اليوم؟',
    );
    expect(
      genderText('اضغط بحث لعرض النتائج', gender: 'female'),
      'اضغطي بحث لعرض النتائج',
    );
    expect(genderText('الكابتن وصل', gender: 'female'), 'الكابتن وصل');
    expect(uiText('شارع القاهرة 18', language: 'en'), 'شارع القاهرة 18');
    expect(uiText('وين تريد تروح؟', language: 'ku'), 'دەتەوێت بۆ کوێ بچیت؟');
  });
  testWidgets(
    'settings change language and theme immediately at narrow width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        screen(const SingleChildScrollView(child: PreferencesPanel())),
      );
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('App language'), findsOneWidget);
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(PreferencesPanel))).brightness,
        Brightness.dark,
      );
      await tester.tap(find.text('کوردی'));
      await tester.pumpAndSettle();
      expect(find.text('زمانی ئەپ'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'account gender saves and updates copy; fields do not overlap heading',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final b = ProfileBackend()
        ..profile = {
          'name': 'كرار',
          'phone': '+9647736578999',
          'gender': 'male',
        };

      await tester.pumpWidget(
        screen(
          AccountPage(
            backend: b,
            busy: false,
            run: (action) => action(),
            toast: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.text('بيانات حسابي')).bottom,
        lessThan(tester.getRect(find.byType(TextFormField).first).top),
      );
      await tester.ensureVisible(find.text('أنثى'));
      await tester.tap(find.text('أنثى'));
      await tester.pump();
      await tester.ensureVisible(find.text('حفظ بياناتي'));
      await tester.tap(find.text('حفظ بياناتي'));
      await tester.pumpAndSettle();
      expect(b.saved?['gender'], 'female');
      expect(accountGender.value, 'female');
      expect(find.text('وين تريدين نروح؟'), findsOneWidget);
      await tester.runAsync(() => appPreferences.setTheme(ThemeMode.dark));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      b.dispose();
    },
  );
  testWidgets('dark cards and heading text use readable theme colours', (
    tester,
  ) async {
    await tester.runAsync(() => appPreferences.setTheme(ThemeMode.dark));
    await tester.pumpWidget(
      screen(PaperCard(child: AppText('بيانات حسابي', style: heading(24)))),
    );
    final text = tester.widget<Text>(find.text('بيانات حسابي'));
    final theme = Theme.of(tester.element(find.text('بيانات حسابي')));
    expect(text.style?.color, theme.colorScheme.onSurface);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
