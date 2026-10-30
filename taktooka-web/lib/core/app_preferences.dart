import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taktooka/core/backend_config.dart';

final appPreferences = AppPreferences();

class AppPreferences extends ChangeNotifier {
  String language = 'ar';
  bool hasUsedAccount = false;
  bool onboardingSeen = false;
  ThemeMode themeMode = ThemeMode.light;
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    hasUsedAccount = prefs.getBool('has_used_account_v1') ?? false;
    onboardingSeen = prefs.getBool('onboarding_seen_v1') ?? hasUsedAccount;
    final saved = prefs.getString('display_language');
    language = const {'ar', 'en', 'ku'}.contains(saved) ? saved! : 'ar';
    themeMode = prefs.getString('display_theme') == 'dark'
        ? ThemeMode.dark
        : ThemeMode.light;
    notifyListeners();
  }

  Future<void> prepareAccountEntry() async {
    final prefs = await SharedPreferences.getInstance();
    final project = Uri.parse(supabaseUrl).host.split('.').first;
    final sessionKey = 'sb-$project-auth-token';
    hasUsedAccount = hasUsedAccount || prefs.containsKey(sessionKey);
    if (hasUsedAccount) await prefs.setBool('has_used_account_v1', true);
  }

  Future<void> rememberAccountUse() async {
    hasUsedAccount = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_used_account_v1', true);
  }

  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool('onboarding_seen_v1', true)) {
      throw StateError('ONBOARDING_SAVE_FAILED');
    }
    onboardingSeen = true;
    notifyListeners();
  }

  Future<void> showOnboardingAfterLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen_v1', false);
    onboardingSeen = false;
    notifyListeners();
  }

  Future<void> setLanguage(String value) async {
    if (!const {'ar', 'en', 'ku'}.contains(value)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('display_language', value);
    language = value;
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'display_theme',
      value == ThemeMode.dark ? 'dark' : 'light',
    );
    themeMode = value;
    notifyListeners();
  }
}

class PreferencesScope extends InheritedNotifier<AppPreferences> {
  PreferencesScope({super.key, required super.child})
    : super(notifier: appPreferences);
  static AppPreferences of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PreferencesScope>()
          ?.notifier ??
      appPreferences;
}
