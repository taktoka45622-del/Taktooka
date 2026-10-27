import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:taktooka/core/display_format.dart';

class EnglishDigitsFormatter extends TextInputFormatter {
  const EnglishDigitsFormatter();
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: englishDigits(newValue.text));
}

DateFormat _date(String pattern, String locale) {
  final format = switch (pattern) {
    'yMd' => DateFormat.yMd(locale),
    'yMMMd' => DateFormat.yMMMd(locale),
    _ => DateFormat(pattern, locale),
  };
  return format..useNativeDigits = false;
}

mixin AppNumericFormat on GlobalMaterialLocalizations {
  @override
  String formatDecimal(int number) =>
      NumberFormat('#,##0', 'en').format(number);
  @override
  String formatHour(TimeOfDay t, {bool alwaysUse24HourFormat = false}) =>
      '${t.hour % 12 == 0 ? 12 : t.hour % 12}';
  @override
  String formatMinute(TimeOfDay t) => t.minute.toString().padLeft(2, '0');
  @override
  String get anteMeridiemAbbreviation => 'صباحًا';
  @override
  String get postMeridiemAbbreviation => 'مساءً';
  @override
  TimeOfDayFormat timeOfDayFormat({bool alwaysUse24HourFormat = false}) =>
      TimeOfDayFormat.h_colon_mm_space_a;
  @override
  String formatTimeOfDay(TimeOfDay t, {bool alwaysUse24HourFormat = false}) =>
      clock12(t.hour, t.minute);
}

class _ArabicNumericLocalizations extends MaterialLocalizationAr
    with AppNumericFormat {
  _ArabicNumericLocalizations()
    : super(
        fullYearFormat: _date('y', 'ar'),
        compactDateFormat: _date('yMd', 'ar'),
        shortDateFormat: _date('yMMMd', 'ar'),
        mediumDateFormat: _date('EEE, MMM d', 'ar'),
        longDateFormat: _date('EEEE, MMMM d, y', 'ar'),
        yearMonthFormat: _date('MMMM y', 'ar'),
        shortMonthDayFormat: _date('MMM d', 'ar'),
        decimalFormat: NumberFormat('0', 'en'),
        twoDigitZeroPaddedFormat: NumberFormat('00', 'en'),
      );
}

class _EnglishNumericLocalizations extends MaterialLocalizationEn
    with AppNumericFormat {
  _EnglishNumericLocalizations()
    : super(
        fullYearFormat: _date('y', 'en'),
        compactDateFormat: _date('yMd', 'en'),
        shortDateFormat: _date('yMMMd', 'en'),
        mediumDateFormat: _date('EEE, MMM d', 'en'),
        longDateFormat: _date('EEEE, MMMM d, y', 'en'),
        yearMonthFormat: _date('MMMM y', 'en'),
        shortMonthDayFormat: _date('MMM d', 'en'),
        decimalFormat: NumberFormat('0', 'en'),
        twoDigitZeroPaddedFormat: NumberFormat('00', 'en'),
      );
  @override
  String get anteMeridiemAbbreviation => 'AM';
  @override
  String get postMeridiemAbbreviation => 'PM';
  @override
  String formatTimeOfDay(TimeOfDay t, {bool alwaysUse24HourFormat = false}) =>
      '${t.hour % 12 == 0 ? 12 : t.hour % 12}:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

class AppMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const AppMaterialLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) =>
      ['ar', 'en', 'ku'].contains(locale.languageCode);
  @override
  Future<MaterialLocalizations> load(Locale locale) async {
    await initializeDateFormatting(
      locale.languageCode == 'ku' ? 'ar' : locale.languageCode,
    );
    if (locale.languageCode == 'ku') return _KurdishNumericLocalizations();
    return locale.languageCode == 'ar'
        ? _ArabicNumericLocalizations()
        : _EnglishNumericLocalizations();
  }

  @override
  bool shouldReload(AppMaterialLocalizationsDelegate old) => false;
}

class GroupedNumberFormatter extends TextInputFormatter {
  const GroupedNumberFormatter();
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    final formatted = groupNumberInput(newValue.text);
    int offset(int oldOffset) {
      if (oldOffset < 0) return formatted.length;
      final count = englishDigits(
        newValue.text.substring(0, oldOffset.clamp(0, newValue.text.length)),
      ).replaceAll(',', '').length;
      if (count == 0) return 0;
      var seen = 0;
      for (var i = 0; i < formatted.length; i++) {
        if (formatted[i] != ',') seen++;
        if (seen == count) return i + 1;
      }
      return formatted.length;
    }

    return newValue.copyWith(
      text: formatted,
      selection: TextSelection(
        baseOffset: offset(newValue.selection.baseOffset),
        extentOffset: offset(newValue.selection.extentOffset),
      ),
      composing: TextRange.empty,
    );
  }
}

class _KurdishNumericLocalizations extends _ArabicNumericLocalizations {
  static const months = [
    'کانوونی دووەم',
    'شوبات',
    'ئازار',
    'نیسان',
    'ئایار',
    'حوزەیران',
    'تەممووز',
    'ئاب',
    'ئەیلوول',
    'تشرینی یەکەم',
    'تشرینی دووەم',
    'کانوونی یەکەم',
  ];
  @override
  String get anteMeridiemAbbreviation => 'بەیانی';
  @override
  String get postMeridiemAbbreviation => 'ئێوارە';
  @override
  String get cancelButtonLabel => 'هەڵوەشاندنەوە';
  @override
  String get okButtonLabel => 'باشە';
  @override
  String get closeButtonLabel => 'داخستن';
  @override
  String get backButtonTooltip => 'گەڕانەوە';
  @override
  String get closeButtonTooltip => 'داخستن';
  @override
  String get continueButtonLabel => 'بەردەوامبوون';
  @override
  String get copyButtonLabel => 'کۆپی';
  @override
  String get cutButtonLabel => 'بڕین';
  @override
  String get pasteButtonLabel => 'لکاندن';
  @override
  String get selectAllButtonLabel => 'هەڵبژاردنی هەموو';
  @override
  String get datePickerHelpText => 'هەڵبژاردنی ڕێکەوت';
  @override
  String get dateInputLabel => 'ڕێکەوت بنووسە';
  @override
  String get timePickerHourLabel => 'کاتژمێر';
  @override
  String get timePickerMinuteLabel => 'خولەک';
  @override
  String get timePickerInputHelpText => 'کات هەڵبژێرە';
  @override
  String get invalidTimeLabel => 'کاتێکی دروست بنووسە';
  @override
  String get invalidDateFormatLabel => 'ڕێکەوتێکی دروست بنووسە';
  @override
  String get dateOutOfRangeLabel => 'ڕێکەوت لە سنوور دەرەوەیە';
  @override
  String get nextMonthTooltip => 'مانگی دواتر';
  @override
  String get previousMonthTooltip => 'مانگی پێشوو';
  @override
  String get inputTimeModeButtonLabel => 'نووسینی کات';
  @override
  String get dialModeButtonLabel => 'هەڵبژاردنی کات';
  @override
  String get inputDateModeButtonLabel => 'نووسینی ڕێکەوت';
  @override
  String get calendarModeButtonLabel => 'تەقویم';
  @override
  List<String> get narrowWeekdays => ['ی', 'د', 'س', 'چ', 'پ', 'ه', 'ش'];
  @override
  String formatMonthYear(DateTime date) =>
      '${months[date.month - 1]} ${date.year}';
  @override
  String formatMediumDate(DateTime date) =>
      '${date.day} ${months[date.month - 1]}';
  @override
  String formatFullDate(DateTime date) =>
      '${date.day} ${months[date.month - 1]} ${date.year}';
  @override
  String formatTimeOfDay(TimeOfDay t, {bool alwaysUse24HourFormat = false}) =>
      '${t.hour % 12 == 0 ? 12 : t.hour % 12}:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'بەیانی' : 'ئێوارە'}';
}

class _KurdishWidgets extends DefaultWidgetsLocalizations {
  const _KurdishWidgets();
  @override
  TextDirection get textDirection => TextDirection.rtl;
}

class KurdishWidgetsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const KurdishWidgetsDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ku';
  @override
  Future<WidgetsLocalizations> load(Locale locale) async =>
      const _KurdishWidgets();
  @override
  bool shouldReload(KurdishWidgetsDelegate old) => false;
}
