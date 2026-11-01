import 'package:taktooka/services/media_url.dart';
import 'package:taktooka/widgets/food_order_item.dart';
import 'chat_page.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/commerce.dart';
import 'package:taktooka/services/map_navigation.dart';
import 'package:taktooka/widgets/booking_map_layer.dart';
import 'package:taktooka/widgets/commerce_ui.dart';

import 'food_tracking_page.dart';

class FoodOrderDetailsPage extends StatefulWidget {
  final Backend b;
  final Json initial;
  const FoodOrderDetailsPage({
    super.key,
    required this.b,
    required this.initial,
  });
  @override
  State<FoodOrderDetailsPage> createState() => _FoodOrderDetailsPageState();
}

class _FoodOrderDetailsPageState extends State<FoodOrderDetailsPage> {
  late Json order;
  bool loading = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    order = widget.initial;
    load();
  }

  Future<void> load() async {
    try {
      final value = Json.from(
        await commerceRpc(widget.b, 'order_details', {'id': order['id']})
            as Map,
      );
      if (mounted)
        setState(() {
          order = value;
          error = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget photo(dynamic path, {double height = 80}) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image.network(
      mediaUrl(supabaseUrl, 'restaurant-images', '${path ?? ''}'),
      height: height,
      width: height,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => SizedBox(
        height: height,
        width: height,
        child: const Icon(Icons.restaurant, color: scarlet),
      ),
    ),
  );
  LatLng? point(dynamic raw) =>
      raw is List && raw.length == 2 && raw[0] is num && raw[1] is num
      ? LatLng((raw[0] as num).toDouble(), (raw[1] as num).toDouble())
      : null;
  Future<void> call(dynamic phone) async {
    if (phone == null || '$phone'.isEmpty) return;
    try {
      if (!await launchUrl(Uri(scheme: 'tel', path: '$phone')) && mounted)
        setState(() => error = 'تعذر فتح تطبيق الاتصال');
    } catch (_) {
      if (mounted) setState(() => error = 'تعذر فتح تطبيق الاتصال');
    }
  }

  Future<void> accept() async {
    if (busy || loading) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await commerceRpc(widget.b, 'order_update', {
        'id': order['id'],
        'status': 'accepted',
      });
      if (order['request_offer_id'] != null)
        await widget.b.silenceOffer?.call(order['request_offer_id']);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget party(
    String title,
    String name,
    dynamic phone,
    String address,
    LatLng? location,
    Color color,
    IconData icon,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: const TextStyle(color: muted)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(name, style: heading(18)),
          if (address.isNotEmpty) Text(address),
          if (phone != null) Text('$phone', textDirection: TextDirection.ltr),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              if (phone != null)
                OutlinedButton.icon(
                  onPressed: () => call(phone),
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('اتصال'),
                ),
              if (location != null)
                OutlinedButton.icon(
                  onPressed: () => MapNavigation.open(
                    context,
                    location.latitude,
                    location.longitude,
                  ),
                  icon: const Icon(Icons.near_me_outlined),
                  label: Text(
                    title == 'المطعم — نقطة الاستلام'
                        ? 'موقع المطعم'
                        : 'موقع الزبون',
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  Widget customerTimeline() {
    final status = order['status'];
    if (status == 'rejected')
      return const ListTile(
        leading: Icon(Icons.cancel_outlined, color: Colors.red),
        title: Text('تم إلغاء أو رفض الطلب'),
      );
    final current = switch (status) {
      'pending' => 2,
      'preparing' || 'searching' => 3,
      'accepted' || 'heading' => 3,
      'picked_up' => 4,
      'delivered' => 5,
      _ => 1,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final e in [
              (1, 'تم إرسال الطلب'),
              (2, 'موافقة المطعم'),
              (3, 'جاري التحضير واستلام المندوب'),
              (4, 'في الطريق إليك'),
              (5, 'تم التوصيل'),
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  e.$1 < current
                      ? Icons.check_circle
                      : e.$1 == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: e.$1 <= current ? scarlet : Colors.grey,
                ),
                title: Text(
                  e.$2,
                  style: TextStyle(
                    color: e.$1 <= current ? Colors.black : Colors.grey,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shop = point(order['restaurant_location']),
        customer = point(order['customer_location']);
    final active = [
      'accepted',
      'heading',
      'picked_up',
    ].contains(order['status']);
    final isCourier =
        widget.b.captain || widget.b.commerce['self_courier'] is Map;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          isCourier || widget.b.restaurantOwner
              ? 'تفاصيل طلب التوصيل'
              : 'متابعة الطلب',
        ),
        actions: [
          IconButton(
            onPressed: busy
                ? null
                : () {
                    setState(() => loading = true);
                    load();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (loading || busy) const LinearProgressIndicator(),
          if (!isCourier && !widget.b.restaurantOwner) customerTimeline(),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CommerceStatus(
                    foodStates[order['status']] ?? '${order['status']}',
                  ),
                  const SizedBox(height: 12),
                  if (isCourier)
                    const Text('أجرة التوصيل', style: TextStyle(color: muted)),
                  if (isCourier)
                    Text(
                      money(order['delivery_fee']),
                      style: const TextStyle(
                        fontSize: 30,
                        color: scarlet,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  Text(
                    'رقم الطلب: #${order['id'].toString().split('-').first.toUpperCase()}',
                  ),
                  const SizedBox(height: 8),
                  if (isCourier || widget.b.restaurantOwner)
                    Text(
                      order['delivery_mode'] == 'private'
                          ? 'مندوب خاص بالمطعم'
                          : 'مندوب تكتوكة عام',
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (shop != null &&
              customer != null &&
              (active || isCourier || widget.b.restaurantOwner))
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 240,
                child: FlutterMap(
                  options: MapOptions(
                    initialCameraFit: CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints([shop, customer]),
                      padding: const EdgeInsets.all(48),
                    ),
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
                    ),
                  ),
                  children: [
                    const BookingMapLayer(),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: shop,
                          width: 48,
                          height: 48,
                          child: const Icon(
                            Icons.storefront,
                            color: scarlet,
                            size: 36,
                          ),
                        ),
                        Marker(
                          point: customer,
                          width: 48,
                          height: 48,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.blue,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                    const Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: ColoredBox(
                          color: Color(0xDFFFFFFF),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Text(
                              '© OpenStreetMap',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (active)
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      FoodTrackingPage(b: widget.b, orderId: order['id']),
                ),
              ),
              icon: const Icon(Icons.route_outlined),
              label: const Text('فتح التتبع المباشر'),
            ),
          const SizedBox(height: 12),
          party(
            'المطعم — نقطة الاستلام',
            order['restaurant_name'] ?? '',
            order['restaurant_phone'],
            order['restaurant_address'] ?? '',
            shop,
            scarlet,
            Icons.storefront_outlined,
          ),
          const SizedBox(height: 12),
          if (isCourier || widget.b.restaurantOwner)
            party(
              'الزبون — نقطة التسليم',
              order['customer_name'] ?? 'الزبون',
              order['customer_phone'],
              order['customer_address'] ?? '',
              customer,
              Colors.blue,
              Icons.person_outline,
            ),
          if (order['captain_id'] != null)
            party(
              'الكابتن',
              order['captain_name'] ?? 'الكابتن',
              order['captain_phone'],
              '',
              null,
              Colors.blue,
              Icons.delivery_dining,
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('تفاصيل الحساب', style: heading(18)),
                  for (final item in order['items'] as List? ?? [])
                    FoodOrderItem(item: Json.from(item), photo: photo),
                  const Divider(),
                  CommerceAmountRow('الطعام', order['food_total'] as num),
                  CommerceAmountRow(
                    'أجرة التوصيل',
                    order['delivery_fee'] as num,
                  ),
                  CommerceAmountRow('رسوم الخدمة', order['service_fee'] as num),
                  CommerceAmountRow(
                    isCourier
                        ? 'الكاش المطلوب من الزبون'
                        : 'المبلغ المطلوب مع التوصيل',
                    (order['food_total'] as num) +
                        (order['delivery_fee'] as num) +
                        (order['service_fee'] as num),
                    total: true,
                  ),
                ],
              ),
            ),
          ),
          if (!isCourier && !widget.b.restaurantOwner)
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('دعم تكتوكة')),
                    body: ChatPage(b: widget.b),
                  ),
                ),
              ),
              icon: const Icon(Icons.headset_mic_outlined),
              label: const Text('تواصل مع دعم تكتوكة'),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          if (isCourier && order['status'] == 'searching') ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy || loading || error != null ? null : accept,
              child: Text(busy ? 'جار قبول الطلب…' : 'قبول توصيل الطلب'),
            ),
          ],
        ],
      ),
    );
  }
}
