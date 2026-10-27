import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taktooka/core/app_preferences.dart';
import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/core/numeric_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('automatic amount grouping preserves the amount and caret', () {
    final result = const GroupedNumberFormatter().formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: '10000',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    expect(result.text, '10,000');
    expect(result.selection.baseOffset, 6);
    expect(int.parse(result.text.replaceAll(',', '')), 10000);
  });
  test('Kurdish dialogs keep English digits and twelve-hour clocks', () async {
    final locale = await const AppMaterialLocalizationsDelegate().load(
      const Locale('ku'),
    );
    expect(locale.cancelButtonLabel, 'هەڵوەشاندنەوە');
    expect(locale.formatDecimal(10000), '10,000');
    expect(
      locale.formatTimeOfDay(
        const TimeOfDay(hour: 19, minute: 30),
        alwaysUse24HourFormat: true,
      ),
      '7:30 ئێوارە',
    );
    expect(
      RegExp(
        '[٠-٩۰-۹]',
      ).hasMatch(locale.formatCompactDate(DateTime(2026, 10, 13))),
      false,
    );
  });
  test('language and theme preferences survive reload', () async {
    SharedPreferences.setMockInitialValues({});
    final first = AppPreferences();
    await first.setLanguage('ku');
    await first.setTheme(ThemeMode.dark);
    final restored = AppPreferences();
    await restored.load();
    expect(restored.language, 'ku');
    expect(restored.themeMode, ThemeMode.dark);
    expect(uiText('الخطوط', language: 'en'), 'Routes');
    expect(uiText('الخطوط', language: 'ku'), 'هێڵەکان');
  });
}
