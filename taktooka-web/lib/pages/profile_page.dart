import 'package:flutter/material.dart';

import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/pages/prize_wheel_page.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/widgets/profile_photo.dart';

class ProfileHub extends StatelessWidget {
  final Backend b;
  final VoidCallback edit,
      wallet,
      history,
      addresses,
      offers,
      support,
      settings,
      about,
      invite;
  const ProfileHub({
    super.key,
    required this.b,
    required this.edit,
    required this.wallet,
    required this.history,
    required this.addresses,
    required this.offers,
    required this.support,
    required this.settings,
    required this.about,
    required this.invite,
  });
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      const SectionTitle('حسابي'),
      PaperCard(
        onTap: edit,
        child: Row(
          children: [
            ProfilePhoto(path: b.profile?['avatar_path'], size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    b.loggedIn ? (b.profile?['name'] ?? 'حسابي') : 'أهلًا بيك',
                    style: heading(20),
                  ),
                  AppText(
                    b.loggedIn
                        ? (b.profile?['phone'] ?? '')
                        : 'سجّل دخولك حتى تطلب مشوار',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(color: muted, fontSize: 14),
                  ),
                ],
              ),
            ),
            const CategoryIcon(
              Icons.edit_outlined,
              circle: true,
              size: 42,
              color: Color(0xff555555),
              background: Color(0xfff3f4f5),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      PaperCard(
        onTap: wallet,
        child: Row(
          children: [
            const CategoryIcon(Icons.account_balance_wallet, size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    b.captain ? 'مستحقاتك لدى الشركة' : 'الرصيد',
                    style: const TextStyle(color: muted, fontSize: 16),
                  ),
                  AppText(money(b.balance), style: heading(25)),
                ],
              ),
            ),
            const Icon(Icons.chevron_left),
          ],
        ),
      ),
      const SizedBox(height: 14),
      PaperCard(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            menu(Icons.history, 'رحلاتي', history),
            const Divider(height: 1),
            if (!b.captain) ...[
              menu(Icons.location_on_outlined, 'العناوين المفضلة', addresses),
              const Divider(height: 1),
              menu(Icons.confirmation_number_outlined, 'قسائم الخصم', offers),
              const Divider(height: 1),
            ],
            if (b.captain)
              menu(Icons.casino_outlined, 'عجلة الجوائز', () {
                if (!b.loggedIn) {
                  edit();
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PrizeWheelPage(backend: b),
                  ),
                );
              }),
            menu(Icons.share_outlined, 'دعوة أصدقائك', invite),
            const Divider(height: 1),
            menu(Icons.settings_outlined, 'الإعدادات', settings),
            const Divider(height: 1),
            menu(Icons.info_outline, 'حول تكتوكة', about),
          ],
        ),
      ),
      const SizedBox(height: 14),
      PaperCard(
        onTap: support,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CategoryIcon(Icons.headset_mic_outlined),
          title: const AppText(
            'تواصل مع الدعم',
            style: TextStyle(fontSize: 18),
          ),
          subtitle: const AppText(
            'نحن هنا لمساعدتك دائمًا',
            style: TextStyle(color: muted),
          ),
          trailing: const Icon(Icons.chevron_left),
        ),
      ),
    ],
  );
  Widget menu(IconData icon, String title, VoidCallback action) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    onTap: action,
    leading: CategoryIcon(
      icon,
      size: 40,
      color: const Color(0xff555555),
      background: const Color(0xfff3f4f5),
    ),
    title: AppText(title, style: const TextStyle(fontSize: 17)),
    trailing: const Icon(Icons.chevron_left),
  );
}
