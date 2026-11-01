import 'dart:async';

import 'upload_image.dart';

import 'network_failure.dart';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'backend.dart';

Future<dynamic> commerceRpc(Backend b, String action, [Json data = const {}]) {
  Future<dynamic> request() => b.db
      .rpc(
        const {
              'me',
              'orders',
              'order_details',
              'order_update',
              'offer_decline',
            }.contains(action)
            ? 'tkt_food_commerce'
            : 'tkt_commerce',
        params: {'p_action': action, 'p_data': data},
      )
      .timeout(const Duration(seconds: 15));
  const reads = {
    'me',
    'orders',
    'order_details',
    'accounts',
    'menu',
    'restaurants',
    'track',
    'courier_list',
    'catalog',
    'categories',
    'food_quote',
    'favorites',
    'category_options',
  };
  return reads.contains(action) ? retryNetworkRead(request) : request();
}

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
    'IMAGE_LIMIT': 'يمكن إضافة 10 صور فقط لكل وجبة',
    'INVALID_OPTIONS':
        'تغيّرت خيارات الوجبة أو أسعارها؛ افتح الوجبة وراجع اختياراتك',
    'INVALID_QUANTITY': 'الكمية المسموحة من 1 إلى 99 لكل اختيار',
    'BASKET_LIMIT': 'وصلت للحد الأقصى لوجبات السلة',
    'CART_RESTAURANT_CONFLICT': 'السلة خاصة بمطعم واحد فقط',
    'INVALID_PRICE': 'تحقق من السعر الحالي والسعر السابق',
    'FIELDS_REQUIRED': 'أكمل جميع المعلومات وحدد الموقع',
    'PERMISSION_DENIED': 'ما عندك صلاحية لهذه العملية',
    'REASON_REQUIRED': 'اكتب سبب الرفض',
    'ACCOUNT_EXISTS': 'هذا الرقم مسجّل بحساب؛ استخدم رقم مندوب غير مسجّل',
    'INVALID_PASSWORD': 'كلمة السر لازم تكون من 8 إلى 128 حرفًا',
    'REGISTER_UNAVAILABLE':
        'تعذر إنشاء حساب المندوب من الخدمة؛ حدّث القائمة قبل إعادة المحاولة',
    'RESET_UNAVAILABLE': 'تعذر تغيير كلمة السر؛ أعد المحاولة بعد قليل',
    'STALE_GPS':
        'إشارة الموقع قديمة أو غير دقيقة؛ فعّل الموقع الدقيق وأعد المحاولة',
    'CAPTAIN_UNAVAILABLE':
        'ماكو مندوب متاح حاليًا؛ تأكد من تفعيل استقباله وتحديث موقعه',
    'CAPTAIN_SUBSCRIPTION_REQUIRED': 'تحتاج اشتراك فعّال لاستقبال هذه الطلبات',
    'RESTAURANT_UNAVAILABLE': 'المطعم مغلق حاليًا أو غير متاح',
    'ORDER_UNAVAILABLE': 'هذا الطلب لم يعد متاحًا؛ حدّث القائمة',
    'INVALID_TRANSITION': 'حالة الطلب تغيّرت؛ حدّث القائمة قبل المتابعة',
    'FOOD_DELIVERY_OUTSIDE_RANGE': 'عنوان التوصيل خارج نطاق توصيل الطعام',
    'CATEGORY_LIMIT': 'وصلت للحد الأقصى لأقسام المطعم',
    'ROLE_CONFLICT': 'نوع الحساب لا يسمح بهذه العملية',
    'VEHICLE_MISMATCH': 'هذا الطلب مخصص لنوع مركبة مختلف',
    'OUTSIDE_SERVICE': 'الموقع خارج منطقة الخدمة',
  }.entries) {
    if (raw.contains(item.key)) return item.value;
  }
  if (raw.contains('اختر صورة JPEG'))
    return 'اختر صورة JPEG أو PNG بحجم أقل من 10 ميغابايت';
  return networkFailureMessage(e) ?? readable(e);
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
  return uploadMealImage(b, file);
}

Future<List<String>> pickMealImages(Backend b, {required int remaining}) async {
  if (remaining <= 0) return [];
  final files = await ImagePicker().pickMultiImage(
    maxWidth: 2400,
    maxHeight: 2400,
    imageQuality: 88,
    requestFullMetadata: false,
  );
  if (files.length > remaining) throw StateError('IMAGE_LIMIT');
  final paths = <String>[];
  try {
    for (var offset = 0; offset < files.length; offset += 2) {
      Object? failure;
      final batch = await Future.wait(
        files.skip(offset).take(2).map((file) async {
          try {
            return await uploadMealImage(b, file);
          } catch (e) {
            failure ??= e;
            return null;
          }
        }),
      );
      paths.addAll(batch.whereType<String>());
      if (failure != null) throw failure!;
    }

    return paths;
  } catch (_) {
    if (paths.isNotEmpty) {
      try {
        await b.db.storage.from('restaurant-images').remove(paths);
      } catch (_) {}
    }
    rethrow;
  }
}

Future<String> uploadMealImage(Backend b, XFile file) async {
  final bytes = await prepareUploadImage(await file.readAsBytes());
  final user = b.db.auth.currentUser?.id;
  if (user == null) throw StateError('AUTH_REQUIRED');
  final path = '$user/${const Uuid().v4()}.jpg';
  await b.db.storage
      .from('restaurant-images')
      .uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg'),
      )
      .timeout(const Duration(seconds: 40));
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
