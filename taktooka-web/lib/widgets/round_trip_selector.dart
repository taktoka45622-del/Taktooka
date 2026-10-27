import 'package:flutter/material.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/gender_copy.dart';

class RoundTripSelector extends StatelessWidget {
  final bool roundTrip, enabled;
  final int? waitMinutes;
  final ValueChanged<bool> onMode;
  final ValueChanged<int> onWait;
  final ValueChanged<int> onWaitEnd;
  const RoundTripSelector({super.key, required this.roundTrip,
    required this.waitMinutes, required this.enabled, required this.onMode,
    required this.onWait, required this.onWaitEnd});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: themedSurface(context, roundTrip ? pink : const Color(0xfff7f8fa)),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: roundTrip ? scarlet.withValues(alpha: .25) : Theme.of(context).dividerColor.withValues(alpha: .12)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(Icons.sync_alt_rounded, color: roundTrip ? scarlet : muted),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppText('ذهاب وإياب', style: heading(16)),
          const AppText('نرجعك إلى نقطة الانطلاق', style: TextStyle(fontSize: 11, color: muted)),
        ])),
        Switch(value: roundTrip, onChanged: enabled ? onMode : null, activeThumbColor: scarlet),
      ]),
      if (roundTrip) ...[
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: AppText('وقت الانتظار · إلزامي', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          AppText(waitMinutes == null ? 'حدد الوقت' : '$waitMinutes دقيقة', style: heading(16).copyWith(color: scarlet)),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18)),
          child: Slider(min: 1, max: 15, divisions: 14,
            value: (waitMinutes ?? 1).toDouble(),
            activeColor: scarlet,
            label: '${waitMinutes ?? 1} دقيقة',
            onChanged: enabled ? (value) => onWait(value.round()) : null,
            onChangeEnd: enabled ? (value) => onWaitEnd(value.round()) : null),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
          AppText('1 دقيقة', style: TextStyle(fontSize: 11, color: muted)),
          AppText('15 دقيقة', style: TextStyle(fontSize: 11, color: muted)),
        ]),
        const SizedBox(height: 10),
        AppText(waitMinutes == null ? 'حرك الشريط لتحديد وقت الانتظار قبل الحجز'
            : 'أجرة الانتظار: ${waitMinutes! <= 10 ? '250' : '500'} د.ع',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scarlet)),
        const SizedBox(height: 4),
        const AppText('كروة الذهاب × 2 + الانتظار · لحد 10 دقائق 250، ولحد 15 دقيقة 500 د.ع',
          style: TextStyle(fontSize: 11, color: muted, height: 1.6)),
      ],
    ]),
  );
}
