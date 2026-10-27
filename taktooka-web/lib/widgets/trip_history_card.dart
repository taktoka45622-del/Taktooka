import 'package:taktooka/core/display_format.dart';
import 'package:flutter/material.dart';

import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/widgets/round_trip_summary.dart';

class TripHistoryCard extends StatelessWidget {
  final Json ride;
  final bool captain;
  const TripHistoryCard({super.key, required this.ride, this.captain = false});

  String get reference {
    final number = ride['ride_number'];
    if (number != null) return '$number'.padLeft(6, '0');
    final id = '${ride['id'] ?? ''}';
    return id.length > 8 ? id.substring(0, 8).toUpperCase() : id;
  }

  String get date {
    final parsed = DateTime.tryParse('${ride['created_at']}');
    if (parsed == null) return 'التاريخ غير متوفر';
    final time = parsed.toUtc().add(const Duration(hours: 3));
    const months = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    return '${time.day} ${uiText(months[time.month - 1])} ${time.year} • ${clock12(time.hour, time.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final state = '${ride['status']}';
    final color = state == 'completed'
        ? const Color(0xff198936)
        : state == 'cancelled'
        ? muted
        : scarlet;
    const states = {
      'pending': 'جاري البحث',
      'accepted': 'الكابتن بالطريق',
      'arrived': 'الكابتن وصل',
      'in_progress': 'الرحلة جارية',
      'completed': 'مكتملة',
      'cancelled': 'ملغية',
    };
    final wallet = ride['payment_method'] == 'wallet';
    Widget place(String prefix, dynamic name, Color pinColor) => Expanded(
      child: Row(
        children: [
          Icon(Icons.location_on, color: pinColor, size: 26),
          const SizedBox(width: 4),
          Expanded(
            child: AppText(
              '$prefix: ${name ?? 'الموقع المحدد'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: const Color(0xffeeeeee)),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0d000000),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RoundTripSummary(ride: ride),
          Row(
            children: [
              Expanded(
                child: AppText(
                  'رحلة \u2066#$reference\u2069',
                  style: heading(17),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: AppText(
                    states[state] ?? 'غير معروفة',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppText(date, style: const TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 20),
          Row(
            children: [
              place('من', ride['pickup_name'], scarlet),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: AppText('···', style: TextStyle(color: muted)),
              ),
              place('إلى', ride['destination_name'], Colors.blue),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: themedSurface(context, const Color(0xfff4f5f7)),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        wallet
                            ? Icons.account_balance_wallet_outlined
                            : Icons.payments_outlined,
                        size: 19,
                        color: muted,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: AppText(
                          wallet ? 'دفع من المحفظة' : 'دفع كاش',
                          style: const TextStyle(
                            fontSize: 12,
                            color: muted,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppText(
                  money(
                    captain
                        ? ride['fare']
                        : ride['customer_due'] ?? ride['fare'],
                  ),
                  textAlign: TextAlign.end,
                  style: heading(21),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
