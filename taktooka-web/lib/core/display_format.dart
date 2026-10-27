String englishDigits(String value) => String.fromCharCodes(
  value.runes.map(
    (c) => c >= 0x660 && c <= 0x669
        ? c - 0x660 + 48
        : c >= 0x6f0 && c <= 0x6f9
        ? c - 0x6f0 + 48
        : c == 0x66c
        ? 44
        : c == 0x66b
        ? 46
        : c,
  ),
);
String clock12(int hour, int minute) =>
    '${hour % 12 == 0 ? 12 : hour % 12}:${minute.toString().padLeft(2, '0')} ${hour < 12 ? 'صباحًا' : 'مساءً'}';
String displayClock(dynamic value) {
  final parts = englishDigits('$value').split(':');
  final hour = parts.isEmpty ? null : int.tryParse(parts[0]);
  final minute = parts.length < 2 ? null : int.tryParse(parts[1]);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59)
    return '—';
  return clock12(hour, minute);
}

DateTime? baghdadTime(dynamic value) => DateTime.tryParse(
  englishDigits('$value'),
)?.toUtc().add(const Duration(hours: 3));
String displayTime(dynamic value) {
  final d = baghdadTime(value);
  return d == null ? '—' : clock12(d.hour, d.minute);
}

String displayDateTime(dynamic value) {
  final d = baghdadTime(value);
  return d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} • ${clock12(d.hour, d.minute)}';
}

String groupNumberInput(String value) {
  final normalized = englishDigits(value).replaceAll(',', '');
  if (!RegExp(r'^-?\d*(\.\d*)?$').hasMatch(normalized))
    return englishDigits(value);
  final parts = normalized.split('.');
  final integer = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return parts.length == 1 ? integer : '$integer.${parts[1]}';
}

String formatDisplayNumbers(String value) {
  final text = englishDigits(value);
  final identifiers = [
    'هاتف',
    'موبايل',
    'واتساب',
    'Phone',
    'phone',
    'WhatsApp',
    'رقم الرحلة',
    'رقم الطلب',
    'Trip number',
    'ژمارەی گەشت',
    'ژمارەی کاپتن',
  ];
  if (identifiers.any(text.contains)) return text;
  final months = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final hasDate = months.any(text.contains);
  return text.replaceAllMapped(
    RegExp(r'(^|[\s(])([1-9][0-9]{3,})(?=$|[\s)•؛،%])'),
    (m) {
      final n = int.tryParse(m[2]!);
      if (hasDate && n != null && n >= 1900 && n <= 2200) return m[0]!;
      return '${m[1]}${groupNumberInput(m[2]!)}';
    },
  );
}
