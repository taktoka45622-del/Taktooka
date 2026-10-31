import 'package:flutter/material.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/display_format.dart';
import 'package:taktooka/services/backend.dart';

class CommerceAmountRow extends StatelessWidget {
  final String label;
  final num amount;
  final bool total;
  const CommerceAmountRow(
    this.label,
    this.amount, {
    super.key,
    this.total = false,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final value = Text(
          money(amount),
          textAlign: TextAlign.end,
          style: TextStyle(
            fontSize: total ? 22 : 16,
            fontWeight: total ? FontWeight.bold : FontWeight.w500,
          ),
        );
        if (constraints.maxWidth < 280 ||
            MediaQuery.textScalerOf(context).scale(16) > 21)
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Text(label), const SizedBox(height: 4), value],
          );
        return Row(
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 12),
            Flexible(child: value),
          ],
        );
      },
    ),
  );
}

class CommerceStatus extends StatelessWidget {
  final String label;
  final Color color;
  const CommerceStatus(this.label, {super.key, this.color = scarlet});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w600),
    ),
  );
}

class SettlementRecord extends StatelessWidget {
  final Json record;
  const SettlementRecord({super.key, required this.record});
  Widget detail(String label, String value, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(icon, color: Colors.grey, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final confirmed = record['status'] == 'confirmed';
    final recipient =
        record['recipient_name'] ??
        (record['kind'] == 'captain_restaurant'
            ? record['restaurant_name'] ?? 'مطعم — معلومات المستلم غير متاحة'
            : 'شركة تكتوكة');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(money(record['amount']), style: heading(22)),
                CommerceStatus(
                  confirmed
                      ? 'تم التسديد'
                      : record['status'] == 'pending'
                      ? 'بانتظار التأكيد'
                      : 'منتهي',
                  color: confirmed ? Colors.green : Colors.orange,
                ),
              ],
            ),
            const Divider(height: 24),
            detail(
              confirmed ? 'سُدّد إلى' : 'المستلم',
              recipient.toString(),
              record['kind'] == 'captain_restaurant'
                  ? Icons.storefront_outlined
                  : Icons.business_outlined,
            ),
            detail(
              confirmed ? 'سدّد بواسطة' : 'المطلوب منه التسديد',
              record['payer_name'] ?? 'معلومات الدافع غير متاحة',
              Icons.person_outline,
            ),
            if (record['payer_phone'] != null)
              Text(
                record['payer_phone'].toString(),
                textDirection: TextDirection.ltr,
              ),
            detail(
              'رقم العملية',
              record['id'].toString(),
              Icons.receipt_long_outlined,
            ),
            const Divider(),
            Text(
              displayDateTime(
                confirmed
                    ? record['confirmed_at'] ?? record['created_at']
                    : record['created_at'],
              ),
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
