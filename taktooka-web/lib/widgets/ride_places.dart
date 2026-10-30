import 'package:flutter/material.dart';
import 'package:taktooka/core/gender_copy.dart';

class RidePlaces extends StatelessWidget {
  final Map<String, dynamic> ride;
  final void Function(bool pickup)? onPlace;
  const RidePlaces({super.key, required this.ride, this.onPlace});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: Theme.of(context).dividerColor.withValues(alpha: .18),
      ),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _place(context, true),
        const Divider(height: 1),
        _place(context, false),
      ],
    ),
  );

  Widget _place(BuildContext context, bool pickup) {
    final actualPickup = ride['round_trip_stage'] == 'returning'
        ? !pickup
        : pickup;
    final raw = ride[actualPickup ? 'pickup_name' : 'destination_name'];
    final name = raw is String && raw.trim().isNotEmpty
        ? raw
        : 'الموقع محدد على الخريطة';
    final color = pickup ? const Color(0xffe56516) : const Color(0xffe01828);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onPlace == null ? null : () => onPlace!(actualPickup),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                pickup ? Icons.person_pin_circle_outlined : Icons.flag_outlined,
                color: color,
                size: 23,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    pickup ? 'الانطلاق' : 'الوصول',
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  AppText(
                    name,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
            if (onPlace != null) ...[
              const SizedBox(width: 8),
              Icon(Icons.map_outlined, size: 21, color: color),
            ],
          ],
        ),
      ),
    );
  }
}
