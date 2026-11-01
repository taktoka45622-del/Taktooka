import 'package:taktooka/core/design.dart';
import 'package:url_launcher/url_launcher.dart';

import 'backend.dart';

String foodOrderNumber(Map order) =>
    '${order['order_number'] ?? order['display_number'] ?? (BigInt.tryParse('${order['id'] ?? ''}'.replaceAll('-', ''), radix: 16)?.toString() ?? '—')}';
String normalizeFoodPhone(dynamic raw) {
  var phone = westernDigits('$raw').replaceAll(RegExp(r'[^0-9]'), '');
  if (phone.startsWith('00')) phone = phone.substring(2);
  if (phone.startsWith('0')) phone = '964${phone.substring(1)}';
  if (phone.length == 10 && phone.startsWith('7')) phone = '964$phone';
  return phone;
}

String foodOrderMessage(Map order) => [
  'تكتوكة — طلب #${foodOrderNumber(order)}',
  if (order['status'] != null)
    'الحالة: ${const {'pending': 'بانتظار المطعم', 'preparing': 'قيد التحضير', 'searching': 'جار البحث عن كابتن', 'accepted': 'وافق الكابتن', 'heading': 'بالطريق للمطعم', 'picked_up': 'بالطريق للزبون', 'delivered': 'تم التوصيل', 'rejected': 'مرفوض'}[order['status']] ?? order['status']}',
  for (final p in [
    ('المطعم', 'restaurant'),
    ('الزبون', 'customer'),
    ('الكابتن', 'captain'),
  ]) ...[
    if (order['${p.$2}_name'] != null) '${p.$1}: ${order['${p.$2}_name']}',
    if (order['${p.$2}_phone'] != null) 'الهاتف: ${order['${p.$2}_phone']}',
    if (order['${p.$2}_address'] != null)
      'العنوان: ${order['${p.$2}_address']}',
  ],
  for (final item in order['items'] as List? ?? [])
    '${item['name']} × ${item['quantity']} — ${money(item['price'])}',
  if (order['food_total'] != null) 'حساب المطعم: ${money(order['food_total'])}',
  if (order['delivery_fee'] != null)
    'أجرة التوصيل: ${money(order['delivery_fee'])}',
  if (order['service_fee'] != null) 'الخدمة: ${money(order['service_fee'])}',
  for (final p in [
    ('موقع المطعم', 'restaurant_location'),
    ('موقع الزبون', 'customer_location'),
  ])
    if (order[p.$2] is List && (order[p.$2] as List).length == 2)
      '${p.$1}: https://www.google.com/maps/search/?api=1&query=${order[p.$2][0]},${order[p.$2][1]}',
].join('\n');
Uri foodWhatsAppUri(dynamic phone, {Map? order, String? message}) =>
    Uri.https('wa.me', '/${normalizeFoodPhone(phone)}', {
      'text':
          message ??
          (order == null
              ? 'مرحبا، وياك من تطبيق تكتوكة'
              : foodOrderMessage(order)),
    });
Future<bool> openFoodWhatsApp(
  dynamic phone, {
  Map? order,
  String? message,
}) async {
  if (normalizeFoodPhone(phone).length < 10) return false;
  return launchUrl(
    foodWhatsAppUri(phone, order: order, message: message),
    mode: LaunchMode.externalApplication,
  );
}

List<String> foodPhoneNumbers(String text) {
  final source = westernDigits(text), digits = RegExp(r'[0-9]');
  final values = <String>{};
  for (final match in RegExp(
    r'(?:\+?964|00964|0)[ -]*7(?:[ -]*[0-9]){9}',
  ).allMatches(source)) {
    if (match.start > 0 && digits.hasMatch(source[match.start - 1]) ||
        match.end < source.length && digits.hasMatch(source[match.end]))
      continue;
    values.add(match.group(0)!);
  }
  return values.toList();
}
