import 'package:taktooka/widgets/food_order_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/models/address_choice.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/widgets/booking_map_layer.dart';
import 'package:taktooka/widgets/commerce_ui.dart';

class FoodCheckoutPage extends StatefulWidget {
  final void Function(int, int)? onQuantityChanged;
  final Json restaurant;
  final List<Json> items;
  final AddressChoice place;
  final num delivery, serviceFee;
  final Widget Function(dynamic, {double height}) photo;
  const FoodCheckoutPage({
    super.key,
    required this.restaurant,
    this.onQuantityChanged,
    required this.items,
    required this.place,
    required this.delivery,
    required this.serviceFee,
    required this.photo,
  });
  @override
  State<FoodCheckoutPage> createState() => _FoodCheckoutPageState();
}

class _FoodCheckoutPageState extends State<FoodCheckoutPage> {
  late final List<Json> items = [for (final i in widget.items) Json.from(i)];
  Json get restaurant => widget.restaurant;
  AddressChoice get place => widget.place;
  num get delivery => widget.delivery;
  num get serviceFee => widget.serviceFee;
  Widget photo(dynamic path, {double height = 100}) =>
      widget.photo(path, height: height);
  void quantity(int index, int value) {
    widget.onQuantityChanged?.call(index, value);
    setState(() {
      if (value == 0) {
        items.removeAt(index);
      } else {
        items[index] = {...items[index], 'quantity': value};
      }
    });
  }

  num get subtotal => items.fold<num>(
    0,
    (s, i) => s + (i['price'] as num) * (i['quantity'] as num),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تأكيد الطلب')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(restaurant['name'] ?? '', style: heading(21)),
                      Text(
                        restaurant['address'] ?? '',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: photo(restaurant['image_path'], height: 85),
                ),
              ],
            ),
          ),
        ),
        for (var index = 0; index < items.length; index++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  FoodOrderItem(item: items[index], photo: photo),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'حذف الوجبة من السلة',
                        onPressed: () => quantity(index, 0),
                        icon: const Icon(Icons.delete_outline),
                      ),
                      IconButton(
                        tooltip: 'تقليل الكمية',
                        onPressed: () => quantity(
                          index,
                          (items[index]['quantity'] as int) - 1,
                        ),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('${items[index]['quantity']}'),
                      IconButton(
                        tooltip: 'زيادة الكمية',
                        onPressed: (items[index]['quantity'] as int) < 99
                            ? () => quantity(
                                index,
                                (items[index]['quantity'] as int) + 1,
                              )
                            : null,
                        icon: const Icon(
                          Icons.add_circle_outline,
                          color: scarlet,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('سلتك فارغة، ارجع واختر وجبتك'),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined),
                    const SizedBox(width: 8),
                    Expanded(child: Text('عنوان التوصيل', style: heading(18))),
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('تغيير'),
                    ),
                  ],
                ),
                Text(place.label),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 135,
                    child: IgnorePointer(
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: place.point,
                          initialZoom: 15,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.none,
                          ),
                        ),
                        children: [
                          const BookingMapLayer(),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: place.point,
                                child: const Icon(
                                  Icons.location_on,
                                  color: scarlet,
                                  size: 38,
                                ),
                              ),
                            ],
                          ),
                          const Align(
                            alignment: Alignment.bottomLeft,
                            child: ColoredBox(
                              color: Colors.white,
                              child: Text(
                                '© OpenStreetMap',
                                style: TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('طريقة الدفع', style: heading(19)),
                const SizedBox(height: 12),
                const ListTile(
                  leading: Icon(Icons.payments_outlined),
                  title: Text('كاش عند الاستلام'),
                  trailing: Icon(Icons.radio_button_checked, color: scarlet),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                CommerceAmountRow('سعر الطعام', subtotal),
                CommerceAmountRow('التوصيل', delivery),
                CommerceAmountRow('رسوم الخدمة', serviceFee),
                const Divider(),
                CommerceAmountRow(
                  'المجموع',
                  subtotal + delivery + serviceFee,
                  total: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: items.isEmpty ? null : () => Navigator.pop(context, true),
          child: const Text('تأكيد الطلب'),
        ),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'الدفع عند استلام طلبك',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ],
    ),
  );
}
