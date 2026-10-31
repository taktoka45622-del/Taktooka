import 'package:flutter/material.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/services/backend.dart';

class FoodItemChoices extends StatelessWidget {
  final Json item;
  final Widget Function(dynamic, {double height})? photo;
  const FoodItemChoices({super.key, required this.item, this.photo});
  @override
  Widget build(BuildContext context) {
    final size = item['size'] as Map?;
    final addons = item['addons'] as List? ?? [];
    final notes = (item['notes'] ?? '').toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (size != null)
          Text(
            'الحجم: ${size['name']}',
            style: const TextStyle(color: Colors.grey),
          ),
        for (final extra in addons)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              children: [
                if (photo != null && extra['image_path'] != null)
                  SizedBox(
                    width: 36,
                    child: photo!(extra['image_path'], height: 36),
                  ),
                Text('+ ${extra['name']}'),
                Text(
                  '${money(extra['price'])} لكل وجبة',
                  style: const TextStyle(color: scarlet, fontSize: 13),
                ),
              ],
            ),
          ),
        if (notes.isNotEmpty)
          Text('ملاحظات: $notes', style: const TextStyle(color: Colors.grey)),
      ],
    );
  }
}
