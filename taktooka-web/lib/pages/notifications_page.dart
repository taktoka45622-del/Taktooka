import 'package:flutter/material.dart';

import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/notifications.dart';

class NotificationsPage extends StatelessWidget {
  final NotificationCenter center;
  const NotificationsPage({super.key, required this.center});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 80,
      title: AppText('الإشعارات', style: heading(25)),
      actions: [
        TextButton(
          onPressed: center.readAll,
          child: const AppText(
            'قراءة الكل',
            style: TextStyle(color: scarlet, fontSize: 16),
          ),
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: center,
      builder: (_, __) => RefreshIndicator(
        onRefresh: center.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            if (center.inboxError != null)
              ListTile(title: AppText(center.inboxError!)),
            if (center.inbox.where((n) => n['kind'] != 'offer_end').isEmpty)
              const Padding(
                padding: EdgeInsets.all(30),
                child: AppText(
                  'ما عندك إشعارات بعد',
                  textAlign: TextAlign.center,
                ),
              ),
            for (final n in center.inbox.where((n) => n['kind'] != 'offer_end'))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PaperCard(
                  onTap: () {
                    Navigator.pop(context);
                    center.tap(n);
                  },
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: CategoryIcon(
                          noticeIcon(n),
                          circle: true,
                          size: 52,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppText(
                              '${n['title']}',
                              style: heading(18).copyWith(height: 1.3),
                            ),
                            const SizedBox(height: 3),
                            AppText(
                              '${n['body']}',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 15,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SizedBox(
                          width: 10,
                          height: 10,
                          child: n['read_at'] == null
                              ? const DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: scarlet,
                                    shape: BoxShape.circle,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  IconData noticeIcon(Json n) {
    final screen = n['screen'] ?? (n['target'] as Map?)?['screen'];
    final kind = '${n['kind']}';
    if (screen == 'wallet' || kind.contains('wallet'))
      return Icons.account_balance_wallet_outlined;
    if (screen == 'offers' || kind.contains('coupon'))
      return Icons.confirmation_number_outlined;
    if (screen == 'ride' || kind.contains('ride') || kind.contains('offer'))
      return Icons.electric_rickshaw_outlined;
    if (screen == 'application') return Icons.assignment_ind_outlined;
    if (screen == 'support') return Icons.headset_mic_outlined;
    return Icons.notifications_outlined;
  }
}
