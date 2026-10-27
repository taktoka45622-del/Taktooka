import 'package:taktooka/core/display_format.dart';
import 'package:flutter/material.dart';

import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/services/backend.dart';

class WalletPage extends StatelessWidget {
  final Backend b;
  final VoidCallback support;
  const WalletPage({super.key, required this.b, required this.support});
  @override
  Widget build(BuildContext context) {
    final ledger = Backend.rows(b.extras['ledger'] ?? []);
    const names = {
      'topup': 'شحن من الإدارة',
      'settle': 'تسديد مستحقات الكابتن',
      'ride_payment': 'دفع رحلة',
      'refund': 'استرجاع رحلة ملغاة',
      'captain_earning': 'مستحقات رحلة',
    };
    return RefreshIndicator(
      onRefresh: b.refresh,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SectionTitle(b.captain ? 'مستحقات الكابتن' : 'محفظتي'),
          PaperCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
            child: Row(
              children: [
                const CategoryIcon(
                  Icons.account_balance_wallet_outlined,
                  circle: true,
                  size: 72,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppText(
                        'الرصيد المتاح',
                        style: TextStyle(fontSize: 16, color: muted),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: AppText(money(b.balance), style: heading(38)),
                      ),
                      AppText(
                        b.captain
                            ? 'مستحقات رحلاتك لدى الشركة.'
                            : 'استخدم رصيدك لدفع كروة الرحلة.',
                        style: const TextStyle(color: muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: themedSurface(context, const Color(0xfff3f4f5)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.info, color: muted),
                const SizedBox(width: 12),
                Expanded(
                  child: AppText(
                    b.captain
                        ? 'تسجّل هنا كروة الرحلات المدفوعة بالمحفظة وتعويض الخصومات. تُصفّر المبالغ المسددة بعد تأكيد الإدارة.'
                        : 'الإدارة تشحن محفظتك بعد استلام المبلغ. اختَر الدفع بالمحفظة عند طلب الرحلة.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: support,
            icon: const Icon(Icons.headset_mic),
            label: AppText(
              b.captain ? 'تواصل بخصوص مستحقاتك' : 'طلب شحن الرصيد',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 28),
          AppText('سجل العمليات', style: heading(22)),
          const SizedBox(height: 12),
          PaperCard(
            child: Column(
              children: [
                if (ledger.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: AppText('لا توجد عمليات بعد'),
                  ),
                for (var i = 0; i < ledger.length; i++) ...[
                  if (i > 0) const Divider(height: 22),
                  ledgerRow(ledger[i], names),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget ledgerRow(Json l, Map<String, String> names) {
    final value = num.tryParse('${l['amount']}') ?? 0;
    final color = value >= 0 ? const Color(0xff26a642) : scarlet;
    final timestamp = displayDateTime(l['created_at']);
    return Row(
      children: [
        CategoryIcon(
          l['kind'] == 'refund'
              ? Icons.undo
              : l['kind'] == 'topup'
              ? Icons.account_balance_wallet_outlined
              : Icons.north_east,
          circle: true,
          size: 44,
          color: color,
          background: value >= 0 ? const Color(0xffeaf8ed) : pink,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(names[l['kind']] ?? 'عملية محفظة', style: heading(16)),
              AppText(
                timestamp,
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AppText(
              '${value >= 0 ? '+' : '−'}${money(value.abs()).replaceAll(' د.ع', '')}',
              textDirection: TextDirection.ltr,
              style: heading(20).copyWith(color: color),
            ),
            const AppText('د.ع', style: TextStyle(color: muted, fontSize: 12)),
          ],
        ),
      ],
    );
  }
}
