import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'backend.dart';

Future<dynamic> commerceRpc(Backend b, String action, [Json data = const {}]) =>
    b.db
        .rpc('tkt_commerce', params: {'p_action': action, 'p_data': data})
        .timeout(const Duration(seconds: 25));

String commerceError(Object e) {
  final raw = e.toString();
  for (final item in {
    'CAPTAIN_DEBT_LIMIT':
        'وصلت ذمة الشركة للحد المسموح؛ سدّد الشركة حتى تستقبل طلبات جديدة',
    'RESTAURANT_DEBT_LIMIT':
        'المطعم يحتاج تسديد حساب الشركة قبل استقبال طلبات جديدة',
    'SETTLEMENT_PENDING': 'عندك طلب تسديد بانتظار التأكيد',
    'NOTHING_DUE': 'ماكو مبلغ مستحق للتسديد',
    'INVALID_CODE': 'كود التسديد غير صحيح',
    'CODE_EXPIRED': 'انتهت صلاحية الكود؛ اطلب كود جديد من المطعم',
    'QUOTE_EXPIRED': 'انتهت صلاحية التسعيرة؛ أعد حساب التوصيل',
    'ITEM_UNAVAILABLE': 'أحد الأصناف غير متوفر؛ حدّث السلة',
    'OFFER_EXPIRED': 'الطلب لم يعد متاحاً',
    'CAPTAIN_BUSY': 'عندك طلب جارٍ؛ أكمله أولاً',
    'FIELDS_REQUIRED': 'أكمل جميع المعلومات وحدد الموقع',
    'PERMISSION_DENIED': 'ما عندك صلاحية لهذه العملية',
    'REASON_REQUIRED': 'اكتب سبب الرفض',
    'OUTSIDE_SERVICE': 'الموقع خارج منطقة الخدمة',
  }.entries) {
    if (raw.contains(item.key)) return item.value;
  }
  return 'تعذر إكمال العملية؛ تحقق من الاتصال وحاول مجدداً';
}

Future<String?> pickRestaurantImage(Backend b) async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 2400,
    maxHeight: 2400,
    imageQuality: 88,
    requestFullMetadata: false,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  final png = bytes.length > 3 && bytes[0] == 0x89 && bytes[1] == 0x50;
  final jpg = bytes.length > 2 && bytes[0] == 0xff && bytes[1] == 0xd8;
  if ((!png && !jpg) || bytes.length > 10 * 1024 * 1024) {
    throw StateError('اختر صورة JPEG أو PNG بحجم أقل من 10 ميغابايت');
  }
  final path =
      '${b.db.auth.currentUser!.id}/${const Uuid().v4()}.${png ? 'png' : 'jpg'}';
  await b.db.storage
      .from('restaurant-images')
      .uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: png ? 'image/png' : 'image/jpeg'),
      );
  return path;
}

const foodStates = {
  'pending': 'بانتظار موافقة المطعم',
  'preparing': 'قيد التحضير',
  'searching': 'جار البحث عن مندوب',
  'accepted': 'وافق المندوب',
  'heading': 'المندوب متوجه للمطعم',
  'picked_up': 'بالطريق للزبون',
  'delivered': 'تم التوصيل',
  'rejected': 'مرفوض',
};
