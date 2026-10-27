import 'package:flutter/material.dart';

import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/pages/privacy_page.dart';

class AboutPage extends StatelessWidget {
  final VoidCallback support;
  const AboutPage({super.key, required this.support});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      const SectionTitle('حول تكتوكة'),
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Colors.white, pink],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          border: Border.all(color: const Color(0xfff3dfe2)),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          children: [
            Image.asset('assets/brand.png', height: 82, fit: BoxFit.contain),
            const SizedBox(height: 12),
            AppText(
              'مشوارك أقرب ويا تكتوكة',
              textAlign: TextAlign.center,
              style: heading(24),
            ),
            const SizedBox(height: 8),
            const AppText(
              'من بابك لوجهتك، اطلب تكتك وحدد مشوارك بخطوات بسيطة. تكتوكة تجمع الزبون والكابتن بتطبيق واحد.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: muted, height: 1.8),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      AppText('ليش تختار تكتوكة؟', style: heading(21)),
      const SizedBox(height: 12),
      feature(
        Icons.map_outlined,
        'حدد مشوارك على الخريطة',
        'اختار نقطة الانطلاق والوجهة، وشوف الطريق وأسماء الأماكن حسب بيانات الخريطة.',
      ),
      feature(
        Icons.payments_outlined,
        'الكروة واضحة قبل الطلب',
        'تعرف سعر المشوار قبل تثبيت الطلب، حسب مسافة الطريق وتسعيرة التطبيق.',
      ),
      feature(
        Icons.location_on_outlined,
        'تابع الكابتن مباشرة',
        'شوف موقع الكابتن وحالة الرحلة. التتبع يتحدث حسب اتصال الكابتن وتوفر موقعه.',
      ),
      feature(
        Icons.account_balance_wallet_outlined,
        'كاش أو محفظة',
        'اختار طريقة الدفع اللي تناسبك، وتابع رصيدك وحركات المحفظة من حسابك.',
      ),
      feature(
        Icons.local_offer_outlined,
        'عروض تخلي مشوارك أخف',
        'فعّل كود الخصم وشوف قيمته وتاريخ انتهائه، وتابع الأكواد اللي استخدمتها برحلاتك.',
      ),
      feature(
        Icons.headset_mic_outlined,
        'الدعم قريب منك',
        'تواصل مع الدعم من داخل التطبيق، أو اتصل بالكابتن أثناء الرحلة.',
      ),
      const SizedBox(height: 10),
      AppText('مشوارك بثلاث خطوات', style: heading(21)),
      const SizedBox(height: 12),
      PaperCard(
        child: Column(
          children: [
            step(
              '1',
              'حدد الانطلاق والوجهة',
              'اختار المكان من الخريطة أو البحث.',
            ),
            const Divider(height: 24),
            step(
              '2',
              'راجع الكروة واطلب تكتوكة',
              'اختار الدفع، وخلّي التطبيق يبحث عن كابتن.',
            ),
            const Divider(height: 24),
            step(
              '3',
              'تابع مشوارك',
              'تابع وصول الكابتن وحالة الرحلة من التطبيق.',
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: themedSurface(context, pink),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CategoryIcon(Icons.electric_rickshaw, size: 46),
                const SizedBox(width: 10),
                Expanded(
                  child: AppText(
                    'للكابتن: الكروة كاملة إلك',
                    style: heading(19),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const AppText(
              'اشتراك 5,000 د.ع لمدة 7 أيام، بدون عمولة على كروة الرحلة. سجّل طلبك من التطبيق، وبعد موافقة الإدارة تقدر تستقبل طلبات المشاوير.',
              style: TextStyle(fontSize: 14, height: 1.8),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: support,
        icon: const Icon(Icons.headset_mic_outlined),
        label: const AppText('عندك سؤال؟ تواصل ويانا'),
      ),
      TextButton.icon(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const PrivacyPage())),
        icon: const Icon(Icons.privacy_tip_outlined),
        label: const AppText('سياسة الخصوصية وشروط الاستخدام'),
      ),
      const SizedBox(height: 18),
      const AppText(
        'تكتوكة • مشاوير التكتك بطريقتك',
        textAlign: TextAlign.center,
        style: TextStyle(color: muted, fontSize: 12),
      ),
      const SizedBox(height: 12),
    ],
  );

  Widget feature(IconData icon, String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: PaperCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CategoryIcon(icon, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(title, style: heading(16)),
                const SizedBox(height: 4),
                AppText(
                  body,
                  style: const TextStyle(
                    fontSize: 13,
                    color: muted,
                    height: 1.7,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget step(String number, String title, String body) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CircleAvatar(
        radius: 17,
        backgroundColor: pink,
        child: AppText(
          number,
          style: const TextStyle(color: scarlet, fontWeight: FontWeight.bold),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(title, style: heading(15)),
            AppText(
              body,
              style: const TextStyle(color: muted, fontSize: 13, height: 1.6),
            ),
          ],
        ),
      ),
    ],
  );
}
