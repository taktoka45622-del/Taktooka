import 'package:flutter/material.dart';
import 'package:taktooka/pages/commerce_page.dart';

import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/widgets/captain_application_banner.dart';
import 'package:taktooka/widgets/home_banners.dart';

class HomePage extends StatelessWidget {
  final Backend b;
  final VoidCallback book, history, lines, offers, apply, city, support;
  const HomePage({
    super.key,
    required this.b,
    required this.book,
    required this.history,
    required this.lines,
    required this.offers,
    required this.apply,
    required this.city,
    required this.support,
  });
  Widget shortcut(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback action,
    Color color,
  ) => Expanded(
    child: Card(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Theme.of(context).colorScheme.surface,
      child: InkWell(
        onTap: action,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(height: 10),
              AppText(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final scale = uiScale(context);
    return HomeBanners(
      backend: b,
      builder: (context, banners) => RefreshIndicator(
        onRefresh: b.refresh,
        child: ListView(
          padding: EdgeInsets.all(18 * scale),
          children: [
            Row(
              children: [
                AppText('هلا بيك', style: heading(32 * scale)),
                const SizedBox(width: 8),
                Icon(
                  Icons.waving_hand,
                  color: Color(0xffffca28),
                  size: 32 * scale,
                ),
              ],
            ),
            AppText(
              b.captain ? 'جاهز تستقبل الطلبات؟' : 'وين تريد تروح اليوم؟',
              style: TextStyle(fontSize: 18 * scale, color: muted),
            ),
            const SizedBox(height: 14),
            if (!b.captain) CaptainApplicationBanner(backend: b, open: apply),
            if (b.activeRide != null) ...[
              PaperCard(
                onTap: book,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CategoryIcon(Icons.electric_rickshaw),
                  title: AppText('رحلتك الحالية', style: heading(18)),
                  subtitle: AppText(
                    b.activeRide!['status'] == 'pending'
                        ? 'جاري البحث عن كابتن • اضغط لمتابعة الرحلة'
                        : 'اضغط لفتح الخريطة ومتابعة الرحلة',
                  ),
                  trailing: const Icon(Icons.chevron_left),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (b.captain && b.requests.any((r) => b.offerSeconds(r) > 0)) ...[
              PaperCard(
                onTap: book,
                child: ListTile(
                  leading: const Icon(
                    Icons.notifications_active,
                    color: scarlet,
                  ),
                  title: AppText('عندك طلب مشوار جديد', style: heading(18)),
                  subtitle: const AppText('اضغط لعرضه وقبوله قبل انتهاء العرض'),
                  trailing: const Icon(Icons.chevron_left),
                ),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 10),
            PaperCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: AspectRatio(
                      aspectRatio: 2.19,
                      child: BannerCarousel(
                        images: banners.where((x) => x['slot'] == 1).toList(),
                        borderRadius: BorderRadius.zero,
                        fallback: Image.asset(
                          'assets/hero.png',
                          cacheWidth: 1080,
                          fit: BoxFit.cover,
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    onTap: book,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    leading: const Icon(
                      Icons.location_on,
                      color: scarlet,
                      size: 32,
                    ),
                    title: AppText(
                      b.captain ? 'ابدأ باستقبال الطلبات' : 'وين تريد تروح؟',
                      style: heading(20 * scale),
                    ),
                    trailing: const Icon(Icons.chevron_left),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    child: FilledButton(
                      onPressed: book,
                      child: AppText(
                        b.activeRide != null
                            ? 'تابع رحلتك'
                            : b.captain
                            ? 'تلقي الطلبات'
                            : 'اطلب تكتوكة   ←',
                        style: heading(18).copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (!b.captain ||
                    (!b.commissionPlan && b.commerce['vehicle'] != 'bike'))
                  shortcut(context, Icons.route, 'الخطوط', lines, scarlet),
                shortcut(
                  context,
                  Icons.restaurant,
                  b.captain ? 'طلبات الطعام' : 'طعام',
                  () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => FoodPage(b: b))),
                  scarlet,
                ),
                if (!b.captain)
                  shortcut(
                    context,
                    Icons.person_add_alt_1,
                    'تسجيل',
                    apply,
                    ink,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!b.captain)
              BannerCarousel(
                images: banners.where((x) => x['slot'] == 2).toList(),
                aspectRatio:
                    MediaQuery.sizeOf(context).width < 430 ||
                        MediaQuery.textScalerOf(context).scale(16) > 20
                    ? 2.2
                    : 3.25,
                fallback: Container(
                  padding: EdgeInsets.all(16 * scale),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0xffffce31), Color(0xffff8129), scarlet],
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppText(
                              'مشوارك أسهل',
                              style: heading(28 * scale)
                                  .copyWith(color: Colors.white),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xffffdc43),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: AppText('ويا تكتوكة', style: heading(16)),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.electric_rickshaw,
                        color: Colors.white,
                        size: 80 * scale,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
