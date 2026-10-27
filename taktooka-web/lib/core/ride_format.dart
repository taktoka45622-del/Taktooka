import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;

import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/services/backend.dart';

const red = Color(0xffe01828), yellow = Color(0xffffca28);
const labels = {
  'pending': 'جاري البحث عن كابتن قريب',
  'accepted': 'الكابتن بالطريق',
  'arrived': 'الكابتن وصل',
  'in_progress': 'الرحلة جارية',
  'completed': 'مكتملة',
  'cancelled': 'ملغية',
};
String amount(dynamic n) => money(n);
Widget fareBreakdown(Json value) => value['base_fare'] == null
    ? const SizedBox.shrink()
    : AppText(
        '${value['round_trip'] == true ? 'كروة الذهاب والإياب' : 'كروة الطريق'}: ${amount(value['base_fare'])}'
        '${(value['night_surcharge'] as num? ?? 0) > 0 ? ' + إضافة الليل: ${amount(value['night_surcharge'])}' : ' · تسعيرة نهار'}'
        '${(value['waiting_fee'] as num? ?? 0) > 0 ? ' + الانتظار: ${amount(value['waiting_fee'])}' : ''}',
        style: const TextStyle(fontSize: 12),
      );
LatLng point(dynamic value) =>
    LatLng((value[0] as num).toDouble(), (value[1] as num).toDouble());
