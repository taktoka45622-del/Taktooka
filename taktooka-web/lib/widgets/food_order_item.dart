import 'package:flutter/material.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/services/backend.dart';
import 'food_item_choices.dart';

class FoodOrderItem extends StatelessWidget {
  final Json item;
  final Widget Function(dynamic, {double height}) photo;
  const FoodOrderItem({super.key, required this.item, required this.photo});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 72, child: photo(item['image_path'], height: 72)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item['name']} × ${item['quantity']}',
                    style: heading(17),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    money((item['price'] as num) * (item['quantity'] as num)),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: scarlet,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        FoodItemChoices(item: item, photo: photo),
      ],
    ),
  );
}
