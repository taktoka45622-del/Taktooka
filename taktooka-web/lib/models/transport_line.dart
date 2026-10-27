const lineKinds = {
  'school': 'خط مدرسة',
  'work': 'خط عمل',
  'daily': 'خط التزام يومي',
};
const lineStatuses = {
  'pending': 'بانتظار موافقة كابتن',
  'accepted': 'تم قبول الخط من قبل الكابتن',
  'completed': 'انتهت مدة الخط',
  'cancelled': 'الخط ملغي',
};
const lineRunStates = {
  'scheduled': 'بانتظار الموعد',
  'heading': 'الكابتن متوجه لاستلام الركاب',
  'arrived': 'وصل الكابتن — بانتظار ركوب الراكب',
  'picked_up': 'الركاب مع الكابتن',
  'completed': 'وصل الركاب',
  'missed': 'لم يُنفّذ',
};
const linePaymentStates = {
  'not_due': 'الدفع بنهاية مدة الخط',
  'due': 'أجور الخط مستحقة',
  'customer_confirmed': 'الزبون أكد الدفع؛ بانتظار تأكيد الكابتن',
  'paid': 'تم دفع واستلام أجور الخط',
};
const weekDays = [
  'الأحد',
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
];
List<DateTime> lineServiceDates(DateTime start, int days, Set<int> excluded) {
  if (days < 1 ||
      days > 365 ||
      excluded.length >= 7 ||
      excluded.any((d) => d < 0 || d > 6))
    throw ArgumentError('جدول غير صالح');
  final dates = <DateTime>[];
  var day = DateTime(start.year, start.month, start.day);
  while (dates.length < days) {
    if (!excluded.contains(day.weekday % 7)) dates.add(day);
    day = DateTime(day.year, day.month, day.day + 1);
  }
  return dates;
}

String lineError(Object e) {
  final text = '$e';
  const errors = {
    'MUST_BE_AT_DESTINATION': 'حدّث موقعك قرب الوجهة قبل تأكيد وصول الراكب',
    'LINE_TOO_FAR': 'الخط المقترح لازم يكون ضمن 1 كم من أحد خطوطك',
    'NEXT_LINE_NOT_DUE': 'ماكو خط قريب حان موعده؛ توجّه إلى الوجهة',
    'MAX_THREE_LINES': 'أقصى التزام للكابتن 3 خطوط',
    'LINE_UNAVAILABLE': 'الخط غير متاح للقبول؛ حدّث القائمة',
    'FULL_NAME_REQUIRED': 'اكتب اسم الراكب الثلاثي',
    'DOCUMENTS_REQUIRED': 'ارفع وجه الجنسية وخلفها',
    'START_IN_PAST': 'اختر موعد بداية قادم',
    'INVALID_SCHEDULE': 'راجع الأيام وأوقات الانطلاق والوصول والرجوع للمنزل',
    'CAPTAIN_SUBSCRIPTION_REQUIRED': 'يلزم حساب كابتن واشتراك فعال',
    'OUTSIDE_LINE_TIME': 'متابعة المشوار متاحة قرب موعده',
    'MUST_BE_AT_PICKUP': 'حدّث موقعك قرب نقطة الانطلاق قبل تأكيد استلام الركاب',
    'PERMISSION_DENIED': 'ما عندك صلاحية لهذا الإجراء',
    'PAYMENT_NOT_DUE': 'الدفع عند انتهاء مدة الخط',
  };
  for (final entry in errors.entries) {
    if (text.contains(entry.key)) return entry.value;
  }
  return 'تعذّر تنفيذ العملية؛ حاول مرة ثانية';
}
