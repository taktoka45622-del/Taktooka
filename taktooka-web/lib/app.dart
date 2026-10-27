import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:taktooka/app_shell.dart';
import 'package:taktooka/core/numeric_localizations.dart';
import 'package:taktooka/core/app_preferences.dart';
import 'package:taktooka/core/app_theme.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/services/location_disclosure.dart';
import 'package:taktooka/widgets/keyboard_dismiss.dart';

class TaktookaApp extends StatelessWidget {
  const TaktookaApp({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appPreferences,
    builder: (context, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Taktooka Taxi Web App',
      navigatorKey: appNavigatorKey,
      locale: Locale(appPreferences.language),
      supportedLocales: const [Locale('ar'), Locale('en'), Locale('ku')],
      localizationsDelegates: const [
        AppMaterialLocalizationsDelegate(),
        KurdishWidgetsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: appTheme(),
      darkTheme: appDarkTheme(),
      themeMode: appPreferences.themeMode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: PreferencesScope(
          child: Directionality(
            textDirection: appPreferences.language == 'en'
                ? TextDirection.ltr
                : TextDirection.rtl,
            child: GenderScope(
              child: DismissKeyboardOnOutsideTap(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
      home: const Shell(),
    ),
  );
}
