import 'package:flutter/material.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/services/backend.dart';

class RoundTripSummary extends StatelessWidget {
  final Json ride;
  final DateTime? now;
  const RoundTripSummary({super.key, required this.ride, this.now});

  @override
  Widget build(BuildContext context) {
    if (ride['round_trip'] != true) return const SizedBox.shrink();
    final minutes = (ride['wait_minutes'] as num?)?.toInt() ?? 0;
    final fee = (ride['waiting_fee'] as num?)?.toInt() ?? 0;
    final stage = ride['round_trip_stage'];
    final start = DateTime.tryParse('${ride['wait_started_at']}');
    final seconds = start == null || now == null
        ? null
        : (minutes * 60 - now!.difference(start).inSeconds).clamp(
            0,
            minutes * 60,
          );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: themedSurface(context, pink),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.sync_alt_rounded, color: scarlet, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  'ذهاب وإياب · انتظار $minutes دقيقة',
                  style: heading(13).copyWith(color: scarlet),
                ),
                AppText(
                  'أجرة الانتظار ${money(fee)} مشمولة بالكروة',
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
                if (ride['status'] == 'in_progress' && stage == 'waiting') ...[
                  const SizedBox(height: 5),
                  AppText(
                    seconds == null
                        ? 'الكابتن بانتظار الرجعة'
                        : seconds == 0
                        ? 'انتهى وقت الانتظار المحدد'
                        : 'الانتظار المتبقي ${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (ride['status'] == 'in_progress' && stage == 'returning')
                  const AppText(
                    'الرجعة إلى نقطة الانطلاق',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
