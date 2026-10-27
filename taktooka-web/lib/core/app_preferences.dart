import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final appPreferences = AppPreferences();

class AppPreferences extends ChangeNotifier {
  String language = 'ar';
  ThemeMode themeMode = ThemeMode.light;
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('display_language');
    language = const {'ar', 'en', 'ku'}.contains(saved) ? saved! : 'ar';
    themeMode = prefs.getString('display_theme') == 'dark'
        ? ThemeMode.dark
        : ThemeMode.light;
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
