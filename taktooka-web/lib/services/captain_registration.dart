import 'dart:async';

import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/services/backend.dart';

const iraqProvinces = [
  'بغداد',
  'البصرة',
  'نينوى',
  'أربيل',
  'السليمانية',
  'دهوك',
  'حلبجة',
  'كركوك',
  'ديالى',
  'الأنبار',
  'صلاح الدين',
  'بابل',
  'كربلاء',
  'النجف',
  'واسط',
  'ميسان',
  'ذي قار',
  'المثنى',
  'القادسية',
];

const captainDocumentLabels = {
  'id_front': 'صورة الوجه الأمامي للجنسية',
  'id_back': 'صورة الوجه الخلفي للجنسية',
};

Future<Json?> captainRegistration(
  Backend b,
  String action, [
  Json data = const {},
]) async {
  final result = await b.db
      .rpc(
        'tkt_captain_registration',
        params: {'p_action': action, 'p_data': data},
      )
      .timeout(const Duration(seconds: 25));
  return result is Map ? Json.from(result) : null;
}

String captainRegistrationError(Object e) {
  final value = e.toString();
  for (final entry in {
    'FULL_NAME_REQUIRED': uiText('اكتب اسمك الكامل'),
    'AREA_REQUIRED': 'اختر المحافظة واكتب المنطقة',
    'ACCOUNT_PHONE_REQUIRED': uiText('اكتب رقم الهاتف المسجل بحسابك'),
    'VEHICLE_REQUIRED': 'أكمل رقم الشاصي ولون المركبة وموديلها',
    'DOCUMENTS_REQUIRED': 'أضف صورتي الوجه الأمامي والخلفي للجنسية',
    'APPLICATION_LOCKED': 'طلبك قيد المراجعة؛ لا يمكن تعديله حاليًا',
    'ALREADY_CAPTAIN': 'حسابك مفعّل ككابتن',
    'INVALID_DOCUMENT': 'تعذّر حفظ الصورة؛ أعد التقاطها',
    'camera_access_denied': 'اسمح باستخدام الكاميرا من إعدادات الجهاز',
    'photo_access_denied': 'اسمح باختيار الصور من إعدادات الجهاز',
  }.entries) {
    if (value.contains(entry.key)) return entry.value;
  }
  if (value.contains('FACE_REQUIRED'))
    return 'الصورة لازم بيها وجه شخص واحد واضح';
  if (value.contains('VERIFICATION_REQUIRED'))
    return 'أكمل فحص الوجه وصورة البروفايل';
  return 'تعذّر إكمال العملية. تحقق من الاتصال وأعد المحاولة';
}
