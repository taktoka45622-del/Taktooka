import 'package:flutter/material.dart';
import 'package:taktooka/core/display_format.dart';

class FoodRestaurantPayment extends StatelessWidget {
  final dynamic paidAt;
  final bool showUnpaid;
  const FoodRestaurantPayment({
    super.key,
    this.paidAt,
    this.showUnpaid = false,
  });

  @override
  Widget build(BuildContext context) {
    final paid = DateTime.tryParse('${paidAt ?? ''}') != null;
    if (!paid && !showUnpaid) return const SizedBox.shrink();
    final color = paid
        ? Colors.green.shade700
        : Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                paid ? Icons.verified_outlined : Icons.payments_outlined,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  paid
                      ? 'تم تسديد الأموال'
                      : 'يجب التوجه للمطعم وتسليمه الأموال',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (paid)
            Text(
              'تاريخ التسديد: ${displayDateTime(paidAt)}',
              style: TextStyle(color: color),
            ),
        ],
      ),
    );
  }
}
