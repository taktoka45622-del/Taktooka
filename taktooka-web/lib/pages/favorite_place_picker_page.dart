import 'package:taktooka/core/numeric_localizations.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:taktooka/services/device_booking.dart';
import 'package:taktooka/services/offline_roads.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/core/feature_navigation.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/models/address_choice.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/widgets/booking_map_layer.dart';
import 'package:taktooka/widgets/pickup_pin.dart';
import 'package:taktooka/widgets/destination_pin.dart';
import 'package:taktooka/pages/address_search_page.dart';
import 'package:taktooka/core/pin_policy.dart';

class FavoritePlacePicker extends StatefulWidget {
  final Backend b;
  final Json? existing;
  final String? title;
  final bool origin;
  const FavoritePlacePicker({
    super.key,
    required this.b,
    this.existing,
    this.title,
    this.origin = true,
  });
  @override
  State<FavoritePlacePicker> createState() => _FavoritePlacePickerState();
}

class _FavoritePlacePickerState extends State<FavoritePlacePicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController snapMotion;
  LatLng? snapFrom, snapTo;
  Future<bool>? pendingResolve;
  final map = MapController();
  late final TextEditingController name;
  late LatLng point;
  LatLng? gpsPoint;
  bool locating = false;
  bool ready = false;
  bool moved = false;
  String? locationError;
  String address = 'حدد الموقع على الخريطة';
  Timer? debounce;
  int sequence = 0;
  int selectionRevision = 0;
  bool pinMoving = false, resolving = false;
  LatLng? resolvedPoint;
  @override
  void initState() {
    super.initState();
    snapMotion =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 160),
        )..addListener(() {
          if (!ready || snapFrom == null || snapTo == null) return;
          final t = Curves.easeOutCubic.transform(snapMotion.value);
          map.move(
            LatLng(
              snapFrom!.latitude + (snapTo!.latitude - snapFrom!.latitude) * t,
              snapFrom!.longitude +
                  (snapTo!.longitude - snapFrom!.longitude) * t,
            ),
            map.camera.zoom,
          );
        });
    final a = widget.existing;
    name = TextEditingController(text: a?['label'] as String? ?? '');
    point = a == null
        ? LatLng(widget.b.pickupLat, widget.b.pickupLng)
        : LatLng((a['lat'] as num).toDouble(), (a['lng'] as num).toDouble());
    final known = widget.b.knownPosition;
    if (a == null && known != null) {
      point = LatLng(known.latitude, known.longitude);
      gpsPoint = point;
    }
    if (a == null)
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => locate(initial: true),
      );
  }

  Future<void> locate({bool initial = false}) async {
    if (locating) return;
    setState(() {
      locating = true;
      locationError = null;
    });
    final revision = selectionRevision;
    try {
      final gps = await widget.b.locate();
      if (!mounted) return;
      final current = LatLng(gps.latitude, gps.longitude);
      setState(() => gpsPoint = current);
      if (revision != selectionRevision || initial && moved) return;
      selected(current);
      if (ready) map.move(point, 17);
    } catch (e) {
      if (mounted) setState(() => locationError = readable(e));
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    sequence++;
    snapMotion.dispose();
    name.dispose();
    map.dispose();
    super.dispose();
  }

  void selected(LatLng next) {
    if (next == point) return;
    snapMotion.stop();
    selectionRevision++;
    sequence++;
    debounce?.cancel();
    point = next;
    address = 'حدد الموقع على الخريطة';
    resolvedPoint = null;
    if (!pinMoving || resolving || locationError != null)
      setState(() {
        pinMoving = true;
        resolving = false;
        locationError = null;
      });
    debounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() => pinMoving = false);
      unawaited(resolvePoint());
    });
  }

  void handleMapEvent(MapEvent event) {
    if (event is! MapEventWithMove) return;
    final source = event.source;
    final zoomChanged =
        (event.camera.zoom - event.oldCamera.zoom).abs() > .000001;
    if (source == MapEventSource.onMultiFinger ||
        source == MapEventSource.scrollWheel ||
        source == MapEventSource.doubleTapZoomAnimationController ||
        source == MapEventSource.doubleTapHold ||
        source == MapEventSource.keyboard && zoomChanged) {
      snapMotion.stop();
      if (ready) map.move(point, event.camera.zoom);
      return;
    }
    if (!zoomChanged &&
        (source == MapEventSource.onDrag ||
            source == MapEventSource.flingAnimationController ||
            source == MapEventSource.keyboard)) {
      moved = true;
      selected(event.camera.center);
    }
  }

  Future<Json> roadPoint(LatLng selectedPoint) async {
    if (!kIsWeb && OfflineRoads.shared.isReady) {
      try {
        return await OfflineRoads.shared
            .snap(selectedPoint.latitude, selectedPoint.longitude)
            .timeout(const Duration(milliseconds: 1200));
      } catch (_) {}
    }
    try {
      return await DeviceBooking.shared
          .snap(selectedPoint)
          .timeout(const Duration(milliseconds: 900));
    } catch (_) {}
    final response = await widget.b.db.functions
        .invoke(
          'taktooka-pin',
          body: {
            'point': [selectedPoint.latitude, selectedPoint.longitude],
            'fast': true,
          },
        )
        .timeout(const Duration(seconds: 7));
    return Json.from(response.data as Map);
  }

  Future<void> refreshName(
    LatLng selectedPoint,
    int token, {
    String street = '',
  }) async {
    void apply(Json data) {
      if (!mounted || token != sequence) return;
      final label = data['name'] as String? ?? '';
      if (label.trim().isNotEmpty) setState(() => address = label);
    }

    try {
      apply(
        await DeviceBooking.shared.address(
          selectedPoint,
          street,
          onUpdate: apply,
        ),
      );
    } catch (_) {}
  }

  Future<bool> resolvePoint() {
    if (resolving && pendingResolve != null) return pendingResolve!;
    return pendingResolve = resolveSelectedPoint();
  }

  Future<bool> resolveSelectedPoint() async {
    final token = ++sequence;
    final selectedPoint = point;
    setState(() {
      resolving = true;
      locationError = null;
    });
    unawaited(refreshName(selectedPoint, token));
    try {
      final data = await roadPoint(selectedPoint);
      if (!mounted || token != sequence) return false;
      if (data['error'] != null) throw Exception(data['error']);
      final coords = data['point'];
      if (coords is! List ||
          coords.length != 2 ||
          coords.any((v) => v is! num || !v.isFinite))
        throw Exception('INVALID_ROAD_POINT');
      final corrected = LatLng(
        (coords[0] as num).toDouble(),
        (coords[1] as num).toDouble(),
      );
      if (corrected.latitude.abs() > 90 ||
          corrected.longitude.abs() > 180 ||
          const Distance().as(LengthUnit.Meter, selectedPoint, corrected) >
              maxPinSnapMeters)
        throw Exception('NO_NEARBY_ROAD');
      setState(() {
        point = corrected;
        resolvedPoint = corrected;
        if (address == 'حدد الموقع على الخريطة') {
          address = (data['name'] as String?) ?? address;
        }
      });
      unawaited(
        refreshName(corrected, token, street: data['street'] as String? ?? ''),
      );
      if (ready) {
        if (MediaQuery.disableAnimationsOf(context)) {
          map.move(corrected, map.camera.zoom);
        } else {
          snapFrom = map.camera.center;
          snapTo = corrected;
          unawaited(snapMotion.forward(from: 0));
        }
      }
      return true;
    } catch (e) {
      if (mounted && token == sequence)
        setState(() => locationError = readable(e));
      return false;
    } finally {
      if (mounted && token == sequence) setState(() => resolving = false);
    }
  }

  Future<void> searchLocation() async {
    final choice = await Navigator.of(context).push<AddressChoice>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const AppText('البحث عن مكان')),
          body: AddressSearch(
            b: widget.b,
            title: widget.origin ? 'نقطة الانطلاق' : 'نقطة الوصول',
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    moved = true;
    selected(choice.point);
    if (widget.title == null && name.text.trim().isEmpty)
      name.text = choice.label;
    if (ready) map.move(choice.point, 17);
  }

  Future<void> confirm() async {
    debounce?.cancel();
    if (resolvedPoint != point && !await resolvePoint()) return;
    if (!mounted) return;
    snapMotion.stop();
    if (ready) map.move(point, map.camera.zoom);
    final label = name.text.trim().isEmpty ? address : name.text.trim();
    Navigator.pop(
      context,
      AddressChoice(label, point, favorite: widget.title == null),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: AppText(
        widget.title ??
            (widget.existing == null ? 'إضافة عنوان مفضل' : 'تعديل العنوان'),
      ),
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: map,
                  options: MapOptions(
                    initialCenter: point,
                    initialZoom: 17,
                    minZoom: 5,
                    cameraConstraint: CameraConstraint.containCenter(
                      bounds: LatLngBounds(
                        const LatLng(29, 38.7),
                        const LatLng(37.5, 48.7),
                      ),
                    ),
                    maxZoom: 20,
                    keepAlive: true,
                    interactionOptions: const InteractionOptions(
                      flags:
                          InteractiveFlag.all &
                          ~InteractiveFlag.rotate &
                          ~InteractiveFlag.pinchMove,
                    ),
                    onMapReady: () {
                      ready = true;
                      map.move(point, 17);
                      unawaited(resolvePoint());
                    },
                    onTap: (_, p) {
                      moved = true;
                      selected(p);
                      map.move(p, map.camera.zoom);
                    },
                    onMapEvent: handleMapEvent,
                  ),
                  children: [
                    const BookingMapLayer(),
                    if (gpsPoint != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: gpsPoint!,
                            width: 28,
                            height: 28,
                            child: IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 5,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                Align(
                  alignment: Alignment.center,
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      transform: Matrix4.translationValues(
                        0,
                        widget.origin ? -32 : -36,
                        0,
                      ),
                      width: 48,
                      height: widget.origin ? 64 : 72,
                      child: widget.origin
                          ? PickupPin(moving: pinMoving)
                          : DestinationPin(moving: pinMoving),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'favorite-location',
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    onPressed: locating ? null : () => locate(),
                    child: const Icon(Icons.my_location, color: brandRed),
                  ),
                ),
                const Positioned(
                  bottom: 6,
                  left: 8,
                  child: AppText(
                    '© تكتوكة · © OpenStreetMap',
                    style: TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  tileColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  leading: Icon(
                    Icons.location_on,
                    color: widget.origin ? const Color(0xffe56516) : brandRed,
                  ),
                  title: AppText(
                    address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.search),
                  onTap: searchLocation,
                ),
                const SizedBox(height: 12),
                AppText(
                  locating
                      ? 'جاري تحديد موقعك الحالي…'
                      : widget.title != null
                      ? 'حرّك الخريطة؛ الدبوس يتصحح إلى شارع قريب'
                      : 'حرّك الخريطة لتضع مكانك المفضل، حتى تصل إليه بكل مرة',
                  textAlign: TextAlign.center,
                ),
                if (locationError != null) ...[
                  const SizedBox(height: 8),
                  AppText(locationError!, textAlign: TextAlign.center),
                  TextButton.icon(
                    onPressed: locating ? null : () => locate(),
                    icon: const Icon(Icons.my_location),
                    label: const AppText('إعادة تحديد موقعي'),
                  ),
                ],
                const SizedBox(height: 12),
                if (widget.title == null)
                  TextField(
                    inputFormatters: const [EnglishDigitsFormatter()],
                    controller: name,
                    maxLength: 120,
                    onChanged: (_) => setState(() {}),
                    decoration: localizedInput(
                      context,
                      InputDecoration(
                        labelText: 'اسم العنوان',
                        hintText: 'مثلاً: البيت أو العمل',
                      ),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        locating ||
                            resolving ||
                            pinMoving ||
                            (widget.title == null && name.text.trim().isEmpty)
                        ? null
                        : confirm,
                    child: AppText(
                      widget.title == null
                          ? 'حفظ العنوان'
                          : widget.origin
                          ? 'تأكيد نقطة الانطلاق'
                          : 'تأكيد نقطة الوصول',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
