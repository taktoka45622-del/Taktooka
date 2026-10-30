import 'package:flutter/material.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/widgets/pickup_pin.dart';
import 'package:taktooka/widgets/destination_pin.dart';

class RideEndpointMarker extends StatelessWidget {
  final bool pickup;
  final VoidCallback onTap;
  const RideEndpointMarker({
    super.key,
    required this.pickup,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: pickup ? const Color(0xffe56516) : const Color(0xffe01828),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x18000000),
                blurRadius: 5,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: AppText(
            pickup ? 'الانطلاق' : 'الوصول',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          width: 48,
          height: pickup ? 64 : 72,
          child: pickup ? const PickupPin() : const DestinationPin(),
        ),
      ],
    ),
  );
}
