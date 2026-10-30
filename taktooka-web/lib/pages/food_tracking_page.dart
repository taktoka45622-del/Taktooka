import 'dart:async';
import 'package:taktooka/core/display_format.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/commerce.dart';
import 'package:taktooka/services/offline_roads.dart';
import 'package:taktooka/services/device_booking.dart';
import 'package:taktooka/services/map_navigation.dart';
import 'package:taktooka/widgets/booking_map_layer.dart';

class FoodTrackingPage extends StatefulWidget {
  final Backend b;
  final String orderId;
  const FoodTrackingPage({super.key, required this.b, required this.orderId});
  @override
  State<FoodTrackingPage> createState() => _FoodTrackingPageState();
}

class _FoodTrackingPageState extends State<FoodTrackingPage>
    with WidgetsBindingObserver {
  final map = MapController();
  Timer? timer;
  Json? data;
  String? error;
  bool fetching = false,
      foreground = true,
      ready = false,
      follow = true,
      routeBusy = false;
  List<LatLng> route = [];
  LatLng? lastRouteOrigin;
  String? routeStage;
  DateTime routeAt = DateTime(2000);
  Json get order => Json.from(data?['order'] as Map? ?? {});
  bool get mine => order['captain_id'] == widget.b.db.auth.currentUser?.id;
  LatLng? point(dynamic raw) {
    if (raw is! List || raw.length != 2 || raw[0] is! num || raw[1] is! num)
      return null;
    final p = LatLng((raw[0] as num).toDouble(), (raw[1] as num).toDouble());
    return p.latitude.isFinite && p.longitude.isFinite ? p : null;
  }

  LatLng? get captain {
    final local = widget.b.position;
    if (mine &&
        local != null &&
        DateTime.now().difference(local.timestamp).inSeconds < 25)
      return LatLng(local.latitude, local.longitude);
    return point(data?['captain']?['location']);
  }

  LatLng? get shop => point(data?['restaurant']?['location']);
  LatLng? get customer => point(order['customer_location']);
  LatLng? get target =>
      ['accepted', 'heading'].contains(order['status']) ? shop : customer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.b.addListener(localMoved);
    load();
    timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (foreground) load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) load();
  }

  void localMoved() {
    if (mounted && mine) setState(() {});
  }

  @override
  void dispose() {
    widget.b.removeListener(localMoved);
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    map.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (fetching) return;
    fetching = true;
    try {
      final result = Json.from(
        await commerceRpc(widget.b, 'track', {'id': widget.orderId}) as Map,
      );
      if (!mounted) return;
      final first = data == null;
      setState(() {
        data = result;
        error = null;
      });
      if (ready && first) fit();
      unawaited(updateRoute());
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    } finally {
      fetching = false;
    }
  }

  Future<void> updateRoute() async {
    final origin = captain,
        destination = target,
        stage = order['status']?.toString();
    if (origin == null || destination == null || routeBusy) return;
    final elapsed = DateTime.now().difference(routeAt).inSeconds;
    if (stage == routeStage && elapsed < 20) return;
    if (stage == routeStage &&
        lastRouteOrigin != null &&
        const Distance()(lastRouteOrigin!, origin) < 40 &&
        route.isNotEmpty)
      return;
    routeBusy = true;
    try {
      Json result;
      try {
        await OfflineRoads.shared.warmUp();
        result = await OfflineRoads.shared
            .route(
              origin.latitude,
              origin.longitude,
              destination.latitude,
              destination.longitude,
            )
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        result = await DeviceBooking.shared
            .route(origin, destination)
            .timeout(const Duration(seconds: 8));
      }
      final geometry = result['geometry'];
      final coords = geometry is Map ? geometry['coordinates'] : null;
      if (coords is List && mounted && order['status'] == stage) {
        setState(
          () => route = [
            for (final p in coords)
              if (p is List && p.length >= 2)
                LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()),
          ],
        );
        lastRouteOrigin = origin;
        routeStage = stage;
        routeAt = DateTime.now();
      }
    } catch (_) {
      if (mounted && routeStage != stage) setState(() => route = []);
    } finally {
      routeBusy = false;
    }
  }

  void fit() {
    final points = [
      if (captain != null) captain!,
      if (shop != null) shop!,
      if (customer != null) customer!,
    ];
    if (points.isEmpty) return;
    if (points.length == 1)
      map.move(points.first, 16);
    else
      map.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(64),
          maxZoom: 17,
        ),
      );
  }

  Marker marker(LatLng p, IconData icon, String label, Color color) => Marker(
    point: p,
    width: 112,
    height: 76,
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ),
        Icon(icon, color: color, size: 38),
      ],
    ),
  );
  Future<void> next() async {
    final stage = order['status'];
    final status = switch (stage) {
      'accepted' => 'heading',
      'heading' => 'picked_up',
      'picked_up' => 'delivered',
      _ => null,
    };
    if (status == null) return;
    if (status == 'delivered') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('تأكيد تسليم الطلب واستلام الكاش'),
          content: Text(
            'المجموع المطلوب من الزبون: ${(order['food_total'] as num) + (order['delivery_fee'] as num) + (order['service_fee'] as num)} دينار',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('تم التسليم واستلام المبلغ'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await commerceRpc(widget.b, 'order_update', {
        'id': widget.orderId,
        'status': status,
      });
      await load();
      await widget.b.refresh();
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p =
        shop ?? customer ?? LatLng(widget.b.pickupLat, widget.b.pickupLng);
    final active = [
      'accepted',
      'heading',
      'picked_up',
    ].contains(order['status']);
    final atRestaurant =
        active &&
        captain != null &&
        shop != null &&
        const Distance()(captain!, shop!) < 30;
    return Scaffold(
      appBar: AppBar(title: Text(mine ? 'خريطة توصيل الطلب' : 'تتبّع مندوبك')),
      body: Column(
        children: [
          if (error != null)
            Material(
              color: Colors.amber.shade100,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text('$error — سيتم إعادة المحاولة تلقائياً'),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: map,
                  options: MapOptions(
                    initialCenter: p,
                    initialZoom: 15,
                    onMapReady: () {
                      ready = true;
                      fit();
                    },
                    onPositionChanged: (_, gesture) {
                      if (gesture && mounted) setState(() => follow = false);
                    },
                  ),
                  children: [
                    const BookingMapLayer(),
                    if (route.isNotEmpty && captain != null && active)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: route,
                            color: const Color(0xffe7132c),
                            strokeWidth: 5,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        if (shop != null && !atRestaurant)
                          marker(
                            shop!,
                            Icons.restaurant,
                            'المطعم',
                            Colors.orange.shade800,
                          ),
                        if (customer != null)
                          marker(
                            customer!,
                            Icons.location_on,
                            mine ? 'الزبون' : 'عنوانك',
                            Colors.blue,
                          ),
                      ],
                    ),
                    if (captain != null && active)
                      AnimatedFoodCaptain(
                        point: captain!,
                        bike: order['vehicle'] == 'bike',
                        label: atRestaurant
                            ? 'الكابتن عند المطعم'
                            : mine
                            ? 'موقعك'
                            : 'الكابتن',
                      ),
                  ],
                ),
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'food-map-follow',
                    onPressed: () {
                      setState(() => follow = true);
                      fit();
                    },
                    child: const Icon(Icons.my_location),
                  ),
                ),
                const Positioned(
                  bottom: 8,
                  left: 8,
                  child: Text(
                    '© OpenStreetMap',
                    style: TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    foodStates[order['status']] ?? 'جار تحميل الطلب',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (data?['captain'] != null)
                    Text(
                      '${data!['captain']['name']} · ${data!['captain']['phone']}',
                    ),
                  if (active && captain == null)
                    const Text(
                      'موقع الكابتن غير محدث حالياً؛ ننتظر إشارة جديدة',
                      style: TextStyle(color: Colors.orange),
                    ),
                  if (active && captain != null)
                    Text(
                      'آخر تحديث: ${displayDateTime(data?['captain']?['location_at'])}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  if (order['status'] == 'delivered' && mine)
                    const Text('يجب التوجه للمطعم وتسليمه الأموال'),
                  if (mine && active) ...[
                    FilledButton(
                      onPressed: fetching ? null : next,
                      child: Text(switch (order['status']) {
                        'accepted' => 'التوجه للمطعم',
                        'heading' => 'استلمت الطلب — التوجه للزبون',
                        _ => 'تم التوصيل',
                      }),
                    ),
                    OutlinedButton(
                      onPressed: target == null
                          ? null
                          : () => MapNavigation.open(
                              context,
                              target!.latitude,
                              target!.longitude,
                            ),
                      child: const Text('فتح بتطبيق الخرائط'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AnimatedFoodCaptain extends StatefulWidget {
  final LatLng point;
  final bool bike;
  final String label;
  const AnimatedFoodCaptain({
    super.key,
    required this.point,
    this.bike = false,
    this.label = 'الكابتن',
  });
  @override
  State<AnimatedFoodCaptain> createState() => _AnimatedFoodCaptainState();
}

class _AnimatedFoodCaptainState extends State<AnimatedFoodCaptain> {
  late LatLng shown, origin;
  @override
  void initState() {
    super.initState();
    shown = origin = widget.point;
  }

  @override
  void didUpdateWidget(covariant AnimatedFoodCaptain oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.point != widget.point) origin = shown;
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey('${widget.point.latitude}:${widget.point.longitude}'),
    tween: Tween(begin: 0, end: 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 1600),
    curve: Curves.easeInOut,
    builder: (context, value, _) {
      final p = LatLng(
        origin.latitude + (widget.point.latitude - origin.latitude) * value,
        origin.longitude + (widget.point.longitude - origin.longitude) * value,
      );
      shown = p;
      return MarkerLayer(
        markers: [
          Marker(
            point: p,
            width: 145,
            height: 90,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .15),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Icon(
                      widget.bike
                          ? Icons.delivery_dining
                          : Icons.electric_rickshaw,
                      color: const Color(0xffe7132c),
                      size: 38,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
