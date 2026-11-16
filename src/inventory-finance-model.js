export const inventoryFinanceSpecs = [
  { key: 'completed_food_orders', label: 'طلبات الطعام المكتملة', icon: '🍽️', tone: 'green', type: 'count', description: 'كل طلبات الطعام التي وصلت إلى حالة تم التسليم، مع تفاصيل الزبون والمطعم والمندوب والمبالغ.' },
  { key: 'captains_weekly', label: 'الكباتن المشتركون أسبوعيًا', icon: '✓', tone: 'blue', type: 'count', description: 'الكباتن الذين لديهم اشتراك أسبوعي فعال حاليًا.' },
  { key: 'captains_commission', label: 'الكباتن المسجلون بالنسبة', icon: '%', tone: 'amber', type: 'count', description: 'الكباتن المسجلون على نظام النسبة، مع بيانات التواصل وآخر رحلة.' },
  { key: 'captains_no_ride_2d', label: 'كباتن بلا رحلة خلال يومين', icon: '◷', tone: 'red', type: 'count', description: 'الكباتن الفعالون الذين لم يُسند إليهم أي مشوار خلال آخر 48 ساعة.' },
  { key: 'restaurant_service_due', label: 'رسوم الخدمة لدى المطاعم', icon: 'ر.خ', tone: 'rose', type: 'money', description: 'الرصيد المستحق للشركة من رسوم خدمة الطلبات، مجمّعًا لكل مطعم أو حساب مالكه مع الهاتف والعنوان.' },
  { key: 'taxi_commission_due', label: 'نسبة التكسي لدى الكباتن', icon: '🚕', tone: 'blue', type: 'money', description: 'عمولات الشركة غير المسددة على الرحلات المكتملة، مع اسم الكابتن ورقمه ومرجع الرحلة.' },
  { key: 'food_commission_due', label: 'نسبة الطعام لدى الكباتن', icon: '🍴', tone: 'amber', type: 'money', description: 'عمولات الشركة غير المسددة على طلبات الطعام المسلّمة، مع بيانات الكابتن ومرجع الطلب.' },
  { key: 'exchange_funds', label: 'الأموال المخزونة عند الصيرفات', icon: 'د.ع', tone: 'green', type: 'money', description: 'الأرصدة الموجبة المسجلة لكل صيرفة، مع هاتف الصيرفة وبيانات صاحبها وموقعها.' },
  { key: 'company_profit', label: 'مجموع أرباح الشركة', icon: 'د.ع', tone: 'red', type: 'money', description: 'الإيرادات المسجلة من الاشتراكات ورسوم الخدمة والعمولات مطروحًا منها مصاريف الشركة المسجلة. الصيرفات وذمم المطاعم لا تدخل مرتين بالحسبة.' }
];

export function inventoryFinanceValue(spec, value) {
  const amount = Number(value) || 0;
  return spec.type === 'money'
    ? new Intl.NumberFormat('en-US').format(amount) + ' د.ع'
    : new Intl.NumberFormat('en-US').format(amount);
}

export function inventoryFinanceRows(rows, category) {
  return Array.isArray(rows) ? rows.map(row => ({ ...row, category })) : [];
}
