import 'package:taktooka/widgets/booking_map_layer.dart';
import 'package:taktooka/core/numeric_localizations.dart';
import 'package:taktooka/core/display_format.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:taktooka/core/app_preferences.dart';
import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/place_label.dart';
import 'package:taktooka/core/pin_policy.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/core/ride_format.dart';
import 'package:taktooka/core/ride_emergency.dart';
import 'package:taktooka/models/address_choice.dart';
import 'package:taktooka/pages/address_search_page.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/refresh_gate.dart';
import 'package:taktooka/widgets/active_ride_card.dart';
import 'package:taktooka/widgets/ride_details_panel.dart';
import 'package:taktooka/widgets/round_trip_selector.dart';
import 'package:taktooka/widgets/round_trip_summary.dart';
import 'package:taktooka/widgets/ride_places.dart';
import 'package:taktooka/widgets/ride_endpoint_marker.dart';
import 'package:taktooka/widgets/brand_title.dart';
import 'package:taktooka/widgets/destination_pin.dart';
import 'package:taktooka/widgets/pickup_pin.dart';
import 'package:taktooka/widgets/tuktuk_loader.dart';

class RideMap extends StatefulWidget {
  final AddressChoice? favoriteDestination;
  final Backend backend;
  final bool busy;
  final Future<void> Function(Future<void> Function()) run;
  final void Function(String) toast;
  final VoidCallback openAccount;
  const RideMap({
    super.key,
    this.favoriteDestination,
    required this.backend,
    required this.busy,
    required this.run,
    required this.toast,
    required this.openAccount,
  });
  @override
  State<RideMap> createState() => _RideMapState();
}

class _RideMapState extends State<RideMap>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final controller = MapController();
  late final AnimationController _captainMotion;
  LatLng? _captainFrom, _captainTarget;
  final _captainPosition = ValueNotifier<LatLng?>(null);
  LatLng? get _captainDisplay => _captainPosition.value;
  set _captainDisplay(LatLng? point) => _captainPosition.value = point;
  bool _reduceMotion = false;
  bool _lastCaptainFresh = false, _lastEmergencyReady = false;
  final _motionClock = Stopwatch()..start();
  int _lastMotionFrame = -32;
  DateTime? _captainGpsAt;
  String? _captainRideId;
  bool _followCaptain = true;

  bool get _captainFresh {
    final at = _captainGpsAt;
    return !b.captain &&
        b.activeRide != null &&
        at != null &&
        b.serverNow.difference(at).inSeconds < 15;
  }

  void _syncCaptain() {
    final rideId = b.activeRide?['id'] as String?;
    if (rideId != _captainRideId) {
      _captainMotion.stop();
      _captainRideId = rideId;
      _captainFrom = _captainTarget = _captainDisplay = null;
      _captainGpsAt = null;
      _followCaptain = true;
    }
    final c = b.contact;
    if (b.captain || rideId == null || c?['lat'] == null || c?['lng'] == null)
      return;
    final at = DateTime.tryParse('${c!['location_at']}');
    if (at == null || (_captainGpsAt != null && !at.isAfter(_captainGpsAt!)))
      return;
    final next = LatLng(
      (c['lat'] as num).toDouble(),
      (c['lng'] as num).toDouble(),
    );
    final wasFresh = _captainFresh;
    _captainGpsAt = at;
    if (!_captainFresh) {
      _captainMotion.stop();
      return;
    }
    final previous = _captainDisplay;
    _captainFrom = previous ?? next;
    _captainTarget = next;
    if (_reduceMotion ||
        previous == null ||
        !wasFresh ||
        const Distance().as(LengthUnit.Meter, previous, next) > 150) {
      _captainMotion.stop();
      _captainDisplay = next;
      if (mapReady && _followCaptain)
        controller.move(next, controller.camera.zoom);
    } else {
      _captainMotion.forward(from: 0);
    }
  }

  void _animateCaptain() {
    if (!mounted ||
        !_captainFresh ||
        _captainFrom == null ||
        _captainTarget == null)
      return;
    final t = _captainMotion.value;
    final frame = _motionClock.elapsedMilliseconds;
    if (t < 1 && frame - _lastMotionFrame < 32) return;
    _lastMotionFrame = frame;
    final from = _captainFrom!, to = _captainTarget!;
    final next = LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
    _captainDisplay = next;
    if (mapReady &&
        _followCaptain &&
        const Distance().as(LengthUnit.Meter, controller.camera.center, next) >=
            .8)
      controller.move(next, controller.camera.zoom);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion && _captainMotion.isAnimating) {
      _captainMotion.stop();
      _captainDisplay = _captainTarget;
    }
  }

  bool _operationBusy = false;
  bool _statusBusy = false;
  List<LatLng> _routePoints = [];
  Object? _routeGeometry;
  final Map<LatLng, String> _selectedLabels = {};
  bool get operationBusy => _operationBusy || widget.busy;
  Future<void> _run(Future<void> Function() action) async {
    if (operationBusy) return;
    setState(() => _operationBusy = true);
    try {
      await widget.run(action);
    } finally {
      if (mounted) setState(() => _operationBusy = false);
    }
  }

  LatLng pickup = const LatLng(33.54844, 44.41179);
  LatLng? destination;
  Json? quote;
  int bookingStep = 0;
  Timer? _pinDebounce;
  int pinSeq = 0;
  bool snapping = false;
  bool _pinMoving = false;
  String? pinError;
  LatLng? _snappedPoint;
  int? _snappedStep;
  bool expanded = false,
      selectPickup = false,
      quoting = false,
      mapReady = false;
  String pickupLabel = 'موقع الانطلاق', destinationLabel = 'وين تريد تروح؟';
  String paymentMethod = 'cash';
  bool roundTrip = false;
  int? waitMinutes;
  LatLng? myLocation;
  bool _initialLocationPending = false;
  String? _initialLocationError;
  LocationAccessIssue? _locationAccessIssue;
  bool _waitingForLocationSettings = false;
  int quoteSeq = 0;
  Timer? countdown;
  final _countdownTick = ValueNotifier<int>(0);
  String? retriedRide;
  String? _watchedRideId;
  String? lastRide;
  final places = {
    'الحسينية — القائمقامية': const LatLng(33.54844, 44.41179),
    'الحسينية — الطابو': const LatLng(33.53091, 44.38583),
  };
  Backend get b => widget.backend;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _captainMotion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(_animateCaptain);
    _syncCaptain();
    countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          (b.requests.isNotEmpty ||
              b.activeRide?['round_trip_stage'] == 'waiting'))
        _countdownTick.value++;
      if (!mounted) return;
      final fresh = _captainFresh;
      final ride = b.activeRide;
      final ready = ride != null && rideEmergencyReady(ride, b.serverNow);
      if (fresh != _lastCaptainFresh || ready != _lastEmergencyReady) {
        _lastCaptainFresh = fresh;
        _lastEmergencyReady = ready;
        _countdownTick.value++;
        setState(() {});
      }
    });
    pickup = LatLng(b.pickupLat, b.pickupLng);
    final r = b.activeRide;
    if (r != null) {
      pickup = point(r['pickup']);
      destination = point(r['destination']);
      pickupLabel = r['pickup_name'] as String? ?? 'مكان الزبون';
      destinationLabel = r['destination_name'] as String? ?? 'وجهة الزبون';
      expanded = true;
      lastRide = '${r['id']}:${r['status']}';
      _watchedRideId = r['id'] as String;
    } else if (!b.captain) {
      _initialLocationPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (widget.favoriteDestination != null) {
            unawaited(useFavorite(widget.favoriteDestination!));
          } else {
            unawaited(_locateInitial());
          }
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    quoteSeq++;
    quoting = false;
    countdown?.cancel();
    _countdownTick.dispose();
    _pinDebounce?.cancel();
    pinSeq++;
    _captainMotion.dispose();
    _captainPosition.dispose();
    _motionClock.stop();
    controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RideMap old) {
    super.didUpdateWidget(old);
    _syncCaptain();
    final r = b.activeRide;
    if (r != null) {
      _watchedRideId = r['id'] as String;
      pinSeq++;
      _pinDebounce?.cancel();
      snapping = false;
    }
    final placesChanged =
        r != null &&
        (pickup != point(r['pickup']) ||
            destination != point(r['destination']));
    if (r != null) {
      pickupLabel = r['pickup_name'] as String? ?? 'مكان الزبون';
      destinationLabel = r['destination_name'] as String? ?? 'وجهة الزبون';
    }
    final id = r == null ? null : '${r['id']}:${r['status']}';
    if (id != lastRide || placesChanged) {
      lastRide = id;
      if (r != null) {
        quote = null;
        expanded = true;
        pickup = point(r['pickup']);
        destination = point(r['destination']);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !(_captainFresh && _followCaptain)) fit(r['geometry']);
        });
      } else {
        roundTrip = false;
        waitMinutes = null;
        quote = null;
        destination = null;
        bookingStep = 0;
        expanded = false;
        pinSeq++;
        quoteSeq++;
        snapping = false;
        quoting = false;
        _pinMoving = false;
        pinError = null;
        _snappedPoint = null;
        _snappedStep = null;
        _pendingSnap = null;
        _pendingSnapPoint = null;
        _pendingSnapStep = null;
        if (myLocation != null) pickup = myLocation!;
        pickupLabel = 'موقع الانطلاق';
        _pinDebounce?.cancel();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && b.activeRide == null && !b.captain) {
            if (mapReady) controller.move(pickup, 17);
            unawaited(snapPin());
          }
        });
      }
    }
  }

  List<LatLng> geometry(dynamic raw) {
    if (raw == null) return [];
    return (raw['coordinates'] as List)
        .map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()))
        .toList();
  }

  void fit(dynamic raw) {
    if (!mapReady) return;
    final points = <LatLng>[
      ...geometry(raw),
      if (b.activeRide != null || bookingStep == 2) pickup,
      if (destination != null && (b.activeRide != null || bookingStep == 2))
        destination!,
    ];
    if (points.length > 1)
      controller.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.fromLTRB(72, 112, 72, 48),
        ),
      );
  }

  final Map<String, Json> _quoteCache = {};
  String quoteKey() =>
      '${pickup.latitude},${pickup.longitude}:${destination?.latitude},${destination?.longitude}:$roundTrip:$waitMinutes';
  Future<void> calculate() async {
    if (destination == null || quoting || (roundTrip && waitMinutes == null))
      return;
    if (quote != null) {
      if (bookingStep == 2) fit(quote!['geometry']);
      return;
    }
    if (!b.loggedIn) {
      widget.openAccount();
      widget.toast('سجّل دخولك وأكمل بياناتك أولًا');
      return;
    }
    final key = quoteKey();
    final cached = _quoteCache[key];
    final expires = DateTime.tryParse('${cached?['expires_at']}');
    final created = DateTime.tryParse('${cached?['created_at']}');
    if (cached != null &&
        expires != null &&
        created != null &&
        expires.isAfter(
          DateTime.now().toUtc().add(const Duration(seconds: 15)),
        ) &&
        DateTime.now().toUtc().difference(created).inSeconds < 45) {
      setState(() => quote = cached);
      if (bookingStep == 2) fit(cached['geometry']);
      return;
    }
    final seq = ++quoteSeq;
    setState(() {
      quoting = true;
      quote = null;
    });
    try {
      final response = await b.db.functions
          .invoke(
            'taktooka-quote',
            body: {
              'round_trip': roundTrip,
              'wait_minutes': roundTrip ? waitMinutes : 0,
              'pickup': [pickup.latitude, pickup.longitude],
              'destination': [destination!.latitude, destination!.longitude],
            },
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted || seq != quoteSeq) return;
      final data = Json.from(response.data as Map);
      if (data['error'] != null) throw Exception(data['error']);
      if (_quoteCache.length >= 20) _quoteCache.remove(_quoteCache.keys.first);
      _quoteCache[key] = data;
      setState(() => quote = data);
      if (bookingStep == 2) fit(data['geometry']);
    } on FunctionException catch (e) {
      if (!mounted || seq != quoteSeq) return;
      widget.toast(
        readable(
          Exception(
            e.details is Map ? (e.details as Map)['error'] : e.reasonPhrase,
          ),
        ),
      );
    } catch (e) {
      if (!mounted || seq != quoteSeq) return;
      widget.toast(readable(e));
    } finally {
      if (mounted && seq == quoteSeq) setState(() => quoting = false);
    }
  }

  void selected(LatLng p) {
    if (b.activeRide != null || b.captain || bookingStep == 2) return;
    final current = bookingStep == 0 ? pickup : destination;
    if (current != null &&
        const Distance().as(LengthUnit.Meter, current, p) < .5) {
      return;
    }
    final redraw = !_pinMoving || snapping || quote != null || pinError != null;
    pinSeq++;
    quoteSeq++;
    quoting = false;
    quote = null;
    if (bookingStep == 0) {
      pickup = p;
      pickupLabel = 'الموقع المحدد على الخريطة';
    } else {
      destination = p;
      destinationLabel = 'الوجهة المحددة على الخريطة';
    }
    snapping = false;
    _pinMoving = true;
    pinError = null;
    if (redraw) setState(() {});
    _pinDebounce?.cancel();
    _pinDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _pinMoving = false);
      unawaited(snapPin());
    });
  }

  Future<bool>? _pendingSnap;
  LatLng? _pendingSnapPoint;
  int? _pendingSnapStep;
  final Map<LatLng, Json> _pinCache = {};

  Future<bool> snapPin() {
    final p = bookingStep == 0 ? pickup : destination;
    if (_pendingSnap != null &&
        _pendingSnapPoint == p &&
        _pendingSnapStep == bookingStep) {
      return _pendingSnap!;
    }
    _pendingSnapPoint = p;
    _pendingSnapStep = bookingStep;
    final future = _snapPin();
    _pendingSnap = future;
    unawaited(
      future.then((_) {
        if (identical(_pendingSnap, future)) _pendingSnap = null;
      }),
    );
    return future;
  }

  Future<bool> _snapPin() async {
    final seq = ++pinSeq;
    final step = bookingStep;
    final p = step == 0 ? pickup : destination;
    if (p == null || step == 2 || b.activeRide != null || b.captain)
      return false;
    if (_snappedStep == step && _snappedPoint == p && b.loggedIn) {
      setState(() {
        snapping = false;
        pinError = null;
      });
      if (_pinCache[p]?['address_ready'] != true) {
        unawaited(_refreshPinName(p, seq, step));
      }
      return true;
    }
    if (!b.loggedIn) {
      if (mounted)
        setState(() {
          snapping = false;
          pinError = null;
        });
      return false;
    }
    setState(() {
      snapping = true;
      pinError = null;
    });
    try {
      Json? data = _pinCache[p];
      final cached = data != null;
      if (data == null) {
        final response = await b.db.functions
            .invoke(
              'taktooka-pin',
              body: {
                'point': [p.latitude, p.longitude],
                'fast': true,
              },
            )
            .timeout(const Duration(seconds: 7));
        if (!mounted || seq != pinSeq || step != bookingStep) return false;
        data = Json.from(response.data as Map);
        if (data['error'] != null) throw Exception(data['error']);
        if (_pinCache.length >= 40) _pinCache.remove(_pinCache.keys.first);
        _pinCache[p] = data;
      }
      if (!mounted || seq != pinSeq || step != bookingStep) return false;
      final Json resolved = data;
      final roadPoint = resolved['point'];
      if (roadPoint is! List ||
          roadPoint.length != 2 ||
          roadPoint.any((v) => v is! num || !v.isFinite)) {
        throw Exception('INVALID_ROAD_POINT');
      }
      final corrected = LatLng(
        (roadPoint[0] as num).toDouble(),
        (roadPoint[1] as num).toDouble(),
      );
      if (corrected.latitude.abs() > 90 ||
          corrected.longitude.abs() > 180 ||
          const Distance().as(LengthUnit.Meter, p, corrected) >
              maxPinSnapMeters) {
        throw Exception('NO_NEARBY_ROAD');
      }
      final selectedLabel = _selectedLabels[p];
      if (selectedLabel != null) _selectedLabels[corrected] = selectedLabel;
      resolved['name'] = mergePlaceLabel(
        selectedLabel,
        resolved['name'] as String? ?? '',
      );
      _pinCache[corrected] = data;
      _snappedPoint = corrected;
      _snappedStep = step;
      setState(() {
        if (step == 0) {
          pickup = corrected;
          b.pickupLat = corrected.latitude;
          b.pickupLng = corrected.longitude;
          pickupLabel = (resolved['name'] as String? ?? '').isNotEmpty
              ? resolved['name'] as String
              : 'نقطة الانطلاق المحددة';
        } else {
          destination = corrected;
          destinationLabel = (resolved['name'] as String? ?? '').isNotEmpty
              ? resolved['name'] as String
              : 'نقطة الوصول المحددة';
        }
      });
      if (mapReady && corrected != p) {
        controller.move(corrected, controller.camera.zoom);
      }
      if (!cached || data['address_ready'] != true)
        unawaited(_refreshPinName(corrected, seq, step));
      return true;
    } catch (error) {
      final details = error is FunctionException ? error.details : null;
      final code = details is Map ? '${details['error']}' : '$error';
      final message = code.contains('NO_NEARBY_ROAD')
          ? 'ماكو نقطة وصول بالشارع ضمن 150 متر؛ قرّب الدبوس من مدخل المكان'
          : code.contains('RATE_LIMIT')
          ? 'انتظر لحظات وأعد تحديد النقطة'
          : code.contains('AUTH_REQUIRED')
          ? 'انتهت جلسة الدخول؛ سجّل دخولك مرة ثانية'
          : 'تعذّر الاتصال بخدمة الشوارع؛ أعد المحاولة';
      if (mounted && seq == pinSeq) setState(() => pinError = message);
      return false;
    } finally {
      if (mounted && seq == pinSeq) setState(() => snapping = false);
    }
  }

  Future<void> _refreshPinName(LatLng p, int seq, int step) async {
    try {
      final response = await b.db.functions
          .invoke(
            'taktooka-pin',
            body: {
              'point': [p.latitude, p.longitude],
              'address_only': true,
              'street': _pinCache[p]?['street'] ?? '',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (!mounted ||
          seq != pinSeq ||
          step != bookingStep ||
          (step == 0 ? pickup : destination) != p ||
          b.activeRide != null)
        return;
      final data = Json.from(response.data as Map);
      final name = mergePlaceLabel(
        _selectedLabels[p],
        data['name'] as String? ?? '',
      );
      if (data['address_complete'] != true &&
          _selectedLabels[p] == null &&
          (data['street'] as String? ?? '').isEmpty &&
          (_pinCache[p]?['street'] as String? ?? '').trim().isNotEmpty)
        return;
      if (name.trim().isEmpty) return;
      final cached = _pinCache[p];
      if (cached != null) {
        cached['name'] = name;
        cached['address_ready'] = data['address_complete'] == true;
      }
      setState(() {
        if (step == 0)
          pickupLabel = name;
        else
          destinationLabel = name;
      });
    } catch (_) {}
  }

  Future<void> confirmPoint() async {
    if (!b.loggedIn) {
      widget.openAccount();
      return;
    }
    if (bookingStep == 1 && destination == null) {
      await searchLocation(false);
      return;
    }
    _pinDebounce?.cancel();
    final step = bookingStep;
    final snapped = await snapPin();
    if (!snapped ||
        !mounted ||
        pinError != null ||
        snapping ||
        bookingStep != step ||
        b.activeRide != null)
      return;
    if (bookingStep == 0) {
      setState(() {
        bookingStep = 1;
        expanded = true;
        selectPickup = false;
      });
      await searchLocation(false);
    } else {
      setState(() => bookingStep = 2);
      await calculate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _waitingForLocationSettings &&
        !_initialLocationPending &&
        mounted) {
      _waitingForLocationSettings = false;
      unawaited(_locateInitial());
    }
  }

  Future<void> _openLocationSettings() async {
    _waitingForLocationSettings = true;
    final opened = _locationAccessIssue == LocationAccessIssue.serviceDisabled
        ? await Geolocator.openLocationSettings()
        : await Geolocator.openAppSettings();
    if (!opened && mounted) {
      _waitingForLocationSettings = false;
      widget.toast('افتح إعدادات الموبايل وفعّل الموقع وإذن التطبيق');
    }
  }

  int _locationRevision = 0;
  Future<void> _locateInitial() async {
    if (!mounted) return;
    final revision = ++_locationRevision;
    setState(() {
      _locationAccessIssue = null;
      _initialLocationPending = true;
      _initialLocationError = null;
    });
    try {
      final p = await b.locate();
      if (!mounted ||
          revision != _locationRevision ||
          b.activeRide != null ||
          b.captain)
        return;
      final current = LatLng(p.latitude, p.longitude);
      setState(() {
        myLocation = current;
        pickup = current;
        b.pickupLat = current.latitude;
        b.pickupLng = current.longitude;
        pickupLabel = 'موقعك الحالي';
        _initialLocationPending = false;
      });
      if (mapReady) controller.move(current, 17);
      unawaited(snapPin());
    } catch (error) {
      if (mounted && revision == _locationRevision)
        setState(() {
          _initialLocationError = readable(error);
          _locationAccessIssue = error is LocationAccessException
              ? error.issue
              : null;
        });
    } finally {
      if (mounted && revision == _locationRevision)
        setState(() => _initialLocationPending = false);
    }
  }

  Future<void> locate() async {
    await _run(() async {
      final p = await b.locate();
      if (!mounted) return;
      setState(() {
        myLocation = LatLng(p.latitude, p.longitude);
      });
      if (mapReady) controller.move(myLocation!, 17);
      if (b.activeRide == null && !b.captain && bookingStep != 2)
        selected(myLocation!);
    });
  }

  Future<bool> confirm(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: AppText(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          content: const AppText('تأكد من اختيارك قبل المتابعة.'),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const AppText('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: AppText(title.contains('تلغي') ? 'إلغاء الرحلة' : 'تأكيد'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> status(String status) async {
    if (_statusBusy) return;
    final rideId = b.activeRide?['id'] as String?;
    if (rideId == null) return;
    setState(() => _statusBusy = true);
    try {
      if (status == 'round_trip_wait' || status == 'round_trip_return') {
        final result = await b.db.rpc(
          'tkt_round_trip_phase',
          params: {
            'p_ride': rideId,
            'p_phase': status == 'round_trip_wait' ? 'waiting' : 'returning',
          },
        );
        b.confirmRideUpdated(Json.from(result as Map));
        unawaited(b.refresh(lightweight: true));
        return;
      }
      if (status == 'completed' &&
          !await confirm(
            b.activeRide?['coupon_reward_type'] == 'free_ride'
                ? 'انتهت الرحلة المجانية؟ راح ينضاف يوم لاشتراكك.'
                : b.activeRide?['payment_method'] == 'wallet'
                ? 'انتهت الرحلة؟ مدفوعة بالمحفظة وراح تنضاف مستحقاتك.'
                : 'انتهت الرحلة واستلمت ${b.activeRide?['customer_due'] ?? b.activeRide?['fare']} دينار كاش؟',
          ))
        return;
      if (status == 'cancelled' && !await confirm('تريد تلغي الرحلة؟')) return;
      await b.action('ride_status', {'ride_id': rideId, 'status': status});
      b.confirmRideStatus(rideId, status);
      unawaited(b.refresh(lightweight: true));
      if (status == 'cancelled') widget.toast('تم إلغاء الرحلة');
    } catch (e) {
      widget.toast(readable(e));
    } finally {
      if (mounted) setState(() => _statusBusy = false);
    }
  }

  bool _emergencyBusy = false;
  Future<void> sendEmergency(Json ride) async {
    if (_emergencyBusy || !rideEmergencyReady(ride, b.serverNow)) return;
    setState(() => _emergencyBusy = true);
    try {
      Json data = {'ride_id': ride['id']};
      final cached = b.position;
      if (cached != null &&
          DateTime.now()
                  .toUtc()
                  .difference(cached.timestamp.toUtc())
                  .inSeconds <
              60) {
        data.addAll({
          'lat': cached.latitude,
          'lng': cached.longitude,
          'location_at': cached.timestamp.toUtc().toIso8601String(),
        });
      }
      await b.db
          .rpc('tkt_emergency', params: {'p_action': 'send', 'p_data': data})
          .timeout(const Duration(seconds: 15));
      if (mounted)
        widget.toast('وصل بلاغ الطوارئ للدعم. للاتصال بالطوارئ اتصل بـ911');
      if (mounted && !b.captain)
        unawaited(b.refreshEmergencyLocation(ride['id']));
    } catch (e) {
      if (mounted)
        widget.toast('تعذر إرسال البلاغ. أعد المحاولة أو اتصل بـ911');
    } finally {
      if (mounted) setState(() => _emergencyBusy = false);
    }
  }

  Future<void> contact(String scheme) async {
    if (b.activeRide?['status'] == 'in_progress') return;
    final phone = b.contact?['phone'] as String?;
    if (phone == null) return;
    final uri = scheme == 'tel'
        ? Uri(scheme: 'tel', path: phone)
        : Uri.parse(
            'https://wa.me/${phone.replaceFirst(RegExp('^0'), '964').replaceAll('+', '')}',
          );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication))
      widget.toast('تعذر فتح وسيلة التواصل');
  }

  Widget button(String text, VoidCallback? onPressed) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: operationBusy ? null : onPressed,
      child: AppText(text),
    ),
  );
  Widget note(String text) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: themedSurface(context, const Color(0xfffff5da)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: AppText(text, style: const TextStyle(fontSize: 12, height: 1.6)),
  );
  Widget rideCard(Json r) => ActiveRideCard(
    ride: r,
    contact: b.contact,
    captain: b.captain,
    busy: _statusBusy,
    showCancellation: false,
    now: b.serverNow,
    onStatus: (value) => status(value),
    onContact: (value) => contact(value),
    onEmergency: () => sendEmergency(r),
    emergencyBusy: _emergencyBusy,
    onPlace: (origin) => showRidePlace(r, origin),
  );
  void showRidePlace(Json ride, bool origin) {
    if (!mapReady) return;
    final target = point(ride[origin ? 'pickup' : 'destination']);
    setState(() => _followCaptain = false);
    controller.move(target, 17);
  }

  Widget captainCard() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      AppText(
        'هلا ${b.profile?['name'] ?? 'كابتن'}',
        style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
      ),
      note(
        b.subscribed
            ? 'الاشتراك فعّال لغاية ${displayDateTime(b.profile!['expires_at'])}\nالكروة كلها إلك، بدون عمولة.'
            : 'جدّد اشتراكك: ٥٬٠٠٠ دينار مقابل ٧ أيام.',
      ),
      button(
        !b.subscribed
            ? 'يرجى الاشتراك بالتطبيق'
            : b.tracking
            ? 'إيقاف استلام الطلبات'
            : 'تفعيل لاستقبال الطلبات',
        b.subscribed
            ? () => _run(() async {
                if (b.tracking) {
                  await b.stopTracking();
                } else {
                  await b.enableOrderNotifications?.call();
                  await b.startTracking();
                }
              })
            : null,
      ),
      if (b.tracking) ...[
        const SizedBox(height: 12),
        AppText(
          b.requests.isEmpty ? 'ننتظر طلب قريب…' : 'عرض رحلة إلك وحدك',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final r in b.requests.where((offer) => b.offerSeconds(offer) > 0))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppText(
                    r['coupon_reward_type'] == 'free_ride'
                        ? 'رحلة مجانية للزبون؛ تحصل على يوم اشتراك إضافي بعد إكمالها'
                        : 'الوصول حوالي ${((r['eta_s'] as num) / 60).ceil()} دقيقة · ${amount(r['fare'])}',
                  ),
                  const SizedBox(height: 8),
                  RoundTripSummary(ride: r),
                  RidePlaces(ride: r),
                  const SizedBox(height: 8),
                  fareBreakdown(r),
                  AppText('باقي ${b.offerSeconds(r)} ثانية للقبول'),
                  LinearProgressIndicator(
                    value: (b.offerSeconds(r) / 30).clamp(0.0, 1.0),
                  ),
                  const SizedBox(height: 8),
                  button(
                    'قبول الرحلة',
                    b.offerSeconds(r) <= 0
                        ? null
                        : () => _run(() async {
                            if (b.offerSeconds(r) <= 0)
                              throw Exception('انتهت مهلة العرض');
                            await (b.silenceOffer?.call('${r['offer_id']}') ??
                                Future<void>.value());
                            await b.action('claim', {
                              'ride_id': r['id'],
                              'offer_id': r['offer_id'],
                            });
                            await b.refresh();
                          }),
                  ),
                  TextButton(
                    onPressed: operationBusy
                        ? null
                        : () => _run(() async {
                            await (b.silenceOffer?.call('${r['offer_id']}') ??
                                Future<void>.value());
                            await b.action('reject', {
                              'ride_id': r['id'],
                              'offer_id': r['offer_id'],
                            });
                            await b.refresh();
                            unawaited(b.kickDispatch());
                          }),
                    child: const AppText('رفض العرض'),
                  ),
                ],
              ),
            ),
          ),
      ],
      const SizedBox(height: 10),
      const AppText(
        'احرص على أن يكون جهازك متصلًا بالإنترنت دائمًا',
        style: TextStyle(fontSize: 11, color: Colors.grey),
      ),
    ],
  );
  Future<void> changeDestination(Json ride) async {
    final choice = await Navigator.of(context).push<AddressChoice>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const BrandTitle(), centerTitle: true),
          body: AddressSearch(b: b, title: 'اختيار الوجهة الجديدة'),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final response = await b.db.functions.invoke(
      'taktooka-quote',
      body: {
        'ride_id': ride['id'],
        'destination': [choice.point.latitude, choice.point.longitude],
      },
    );
    final proposed = Json.from(response.data as Map);
    if (proposed['error'] != null) throw Exception(proposed['error']);
    if (!mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const AppText('موافقة على تغيير الوجهة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(choice.label),
            AppText('السعر السابق: ${amount(ride['fare'])}'),
            AppText('السعر الجديد للرحلة كاملة: ${amount(proposed['fare'])}'),
            fareBreakdown(proposed),
            const AppText('إضافة الليل تبقى حسب وقت تأكيد الحجز الأصلي.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const AppText('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const AppText('أوافق على السعر والوجهة'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    final result = await b.dispatch('change_destination', {
      'ride_id': ride['id'],
      'quote_id': proposed['id'],
      'expected_fare': proposed['fare'],
      'destination_name': choice.label,
    });
    if (result['price_changed'] == true)
      throw Exception('تغيّر السعر؛ راجع الوجهة والسعر مرة ثانية');
    await b.refresh();
    widget.toast('تم اعتماد الوجهة والسعر الجديد');
  }

  Future<void> useFavorite(AddressChoice choice) async {
    if (b.activeRide != null) {
      widget.toast('أكمل الرحلة الحالية أولًا');
      return;
    }
    final revision = ++_locationRevision;
    _pinDebounce?.cancel();
    setState(() {
      _initialLocationPending = true;
      quote = null;
      quoting = false;
      quoteSeq++;
      pinSeq++;
    });
    try {
      final gps = await b.locate();
      if (!mounted || revision != _locationRevision || b.activeRide != null)
        return;
      setState(() {
        myLocation = LatLng(gps.latitude, gps.longitude);
        pickup = myLocation!;
        pickupLabel = 'موقعك الحالي';
        b.pickupLat = pickup.latitude;
        b.pickupLng = pickup.longitude;
        destination = choice.point;
        destinationLabel = choice.label;
        bookingStep = 2;
        selectPickup = false;
        expanded = true;
        snapping = false;
        pinError = null;
        _initialLocationError = null;
        _locationAccessIssue = null;
        _initialLocationPending = false;
      });
      await calculate();
    } catch (e) {
      if (mounted && revision == _locationRevision) {
        setState(() => _initialLocationError = readable(e));
        widget.toast(readable(e));
      }
    } finally {
      if (mounted && revision == _locationRevision)
        setState(() => _initialLocationPending = false);
    }
  }

  Future<void> searchLocation(bool origin) async {
    final choice = await Navigator.of(context).push<AddressChoice>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const BrandTitle(), centerTitle: true),
          body: AddressSearch(
            b: b,
            title: origin ? 'نقطة الانطلاق' : 'وين تريد تروح؟',
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice.favorite) {
      await useFavorite(choice);
      return;
    }
    setState(() {
      quoteSeq++;
      quoting = false;
      quote = null;
      if (origin) {
        pickup = choice.point;
        pickupLabel = choice.label;
        b.pickupLat = pickup.latitude;
        b.pickupLng = pickup.longitude;
      } else {
        destination = choice.point;
        destinationLabel = choice.label;
        expanded = true;
        selectPickup = false;
      }
    });
    if (mapReady) controller.move(choice.point, 16);
    setState(() {
      bookingStep = origin ? 0 : 1;
      expanded = !origin;
    });
    selected(choice.point);
    if (_selectedLabels.length >= 40)
      _selectedLabels.remove(_selectedLabels.keys.first);
    _selectedLabels[choice.point] = choice.label;
    setState(() {
      if (origin)
        pickupLabel = choice.label;
      else
        destinationLabel = choice.label;
    });
  }

  Future<void> savePickup() async {
    if (!b.loggedIn) {
      widget.openAccount();
      return;
    }
    final name = TextEditingController(
      text: pickupLabel == 'موقع الانطلاق' ? 'المنزل' : pickupLabel,
    );
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const AppText('إضافة عنوان'),
        content: TextField(
          inputFormatters: const [EnglishDigitsFormatter()],
          controller: name,
          maxLength: 120,
          decoration: localizedInput(
            context,
            InputDecoration(labelText: 'اسم العنوان'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const AppText('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, name.text.trim()),
            child: const AppText('حفظ'),
          ),
        ],
      ),
    );
    name.dispose();
    if (value == null || value.isEmpty) return;
    await _run(() async {
      await b.db.from('tkt_saved_places').insert({
        'user_id': b.db.auth.currentUser!.id,
        'label': value,
        'lat': pickup.latitude,
        'lng': pickup.longitude,
      });
      widget.toast('تم حفظ العنوان');
    });
  }

  int customerFare(int fare) =>
      b.coupon?['reward_type'] == 'free_ride' ? 0 : fare -
      ((b.coupon?['amount'] as num?)?.toInt() ?? 0).clamp(0, fare).toInt();

  Future<void> retrySearch() async {
    final failed = b.failedRide;
    if (failed == null) return;
    await _run(() async {
      final result = Json.from(
        await b.dispatch('retry', {'ride_id': failed['id']}) as Map,
      );
      if (!mounted) return;
      setState(() {
        bookingStep = 2;
        retriedRide = failed['id'];
        roundTrip = failed['round_trip'] == true;
        waitMinutes = roundTrip
            ? (failed['wait_minutes'] as num?)?.toInt()
            : null;
        pickup = point(result['pickup']);
        destination = point(result['destination']);
        pickupLabel = result['pickup_name'] ?? 'موقع الانطلاق';
        destinationLabel = result['destination_name'] ?? 'الوجهة';
        expanded = true;
        quote = null;
      });
      await calculate();
    });
  }

  Widget failedSearchCard() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.search_off, size: 40, color: red),
      const AppText(
        'حاليًا ماكو كابتن متاح، حاول مرة ثانية',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      button('إعادة المحاولة', retrySearch),
      TextButton(
        onPressed: () => setState(() => retriedRide = b.failedRide?['id']),
        child: const AppText('طلب جديد'),
      ),
    ],
  );
  Widget bookingCard() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (bookingStep != 2) ...[
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          leading: Icon(
            Icons.location_on,
            color: bookingStep == 0 ? const Color(0xffe56516) : red,
            size: 20,
          ),
          title: AppText(
            bookingStep == 0 ? pickupLabel : destinationLabel,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.search),
          onTap: () => searchLocation(bookingStep == 0),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: snapping ? const TuktukLoader() : const SizedBox.shrink(),
        ),
        if (pinError != null)
          TextButton(
            onPressed: snapPin,
            child: AppText(pinError!, textAlign: TextAlign.center),
          ),
        button(
          bookingStep == 0 ? 'تأكيد نقطة الانطلاق' : 'تأكيد نقطة الوصول',
          confirmPoint,
        ),
        const SizedBox(height: 6),
        const AppText(
          'حرّك الخريطة؛ الدبوس يتصحح إلى شارع قريب',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 11),
        ),
      ] else ...[
        AppText('مراجعة المشوار', style: heading(26)),
        const SizedBox(height: 12),
        reviewPlace(pickupLabel, true),
        SizedBox(
          height: 22,
          width: 16,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(
              3,
              (_) => Container(
                width: 3,
                height: 3,
                decoration: const BoxDecoration(
                  color: Color(0xffaaaaaa),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
        reviewPlace(destinationLabel, false),
        const Divider(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Image.asset('assets/brand.png', height: 36, width: 40),
                      const SizedBox(width: 8),
                      AppText('تكتوكة', style: heading(20)),
                    ],
                  ),
                  if (quote != null)
                    AppText(
                      '${((quote!['distance_m'] as num) / 1000).toStringAsFixed(1)} كم · ${((quote!['duration_s'] as num) / 60).ceil()} دقيقة',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const AppText(
                  'الكروة',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                if (quote != null)
                  AppText(
                    amount(customerFare((quote!['fare'] as num).toInt())),
                    style: heading(24),
                  ),
              ],
            ),
          ],
        ),
        if (quoting) const LinearProgressIndicator(),
        if (!quoting && quote == null)
          TextButton.icon(
            onPressed: calculate,
            icon: const Icon(Icons.refresh),
            label: const AppText('حساب الكروة'),
          ),
        const Divider(height: 20),
        if (quote != null && b.coupon != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: themedSurface(context, const Color(0xffe9f8ee)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.discount_outlined,
                  color: Color(0xff29994b),
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        b.coupon?['reward_type'] == 'free_ride'
                            ? 'رحلة مجانية واحدة'
                            : 'خصم ${money(((b.coupon!['amount'] as num).toInt()).clamp(0, (quote!['fare'] as num).toInt()))}',
                        style: heading(
                          16,
                        ).copyWith(color: const Color(0xff29994b)),
                      ),
                      AppText(
                        'رمز الخصم: ${b.coupon!['code']}',
                        formatNumbers: false,
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.check_circle,
                  color: Color(0xff29994b),
                  size: 24,
                ),
              ],
            ),
          ),
        RoundTripSelector(
          roundTrip: roundTrip,
          waitMinutes: waitMinutes,
          enabled: !operationBusy,
          onMode: (value) {
            setState(() {
              roundTrip = value;
              waitMinutes = null;
              quoteSeq++;
              quote = null;
              quoting = false;
            });
            if (!value) unawaited(calculate());
          },
          onWait: (value) => setState(() {
            waitMinutes = value;
            quoteSeq++;
            quote = null;
            quoting = false;
          }),
          onWaitEnd: (value) {
            setState(() => waitMinutes = value);
            unawaited(calculate());
          },
        ),
        if (quote != null) RoundTripSummary(ride: quote!),
        if (b.loggedIn) ...[
          const SizedBox(height: 12),
          AppText('طريقة الدفع', style: heading(16)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: paymentChoice('cash', 'كاش', Icons.payments_outlined),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: paymentChoice(
                  'wallet',
                  'محفظة',
                  Icons.account_balance_wallet_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        Row(
          children: [
            Expanded(
              child: !b.loggedIn
                  ? button('سجّل دخولك للحجز', widget.openAccount)
                  : (b.profile?['name'] ?? '').isEmpty ||
                        (b.profile?['phone'] ?? '').isEmpty
                  ? button('أكمل بياناتك للحجز', widget.openAccount)
                  : button(
                      'اطلب تكتوكة',
                      quote != null &&
                              !quoting &&
                              (!roundTrip || waitMinutes != null)
                          ? () => _run(() async {
                              final result = await b.dispatch('book', {
                                'quote_id': quote!['id'],
                                'expected_fare': quote!['fare'],
                                'payment_method': paymentMethod,
                                'pickup_name': pickupLabel,
                                'destination_name': destinationLabel,
                              });
                              if (result['price_changed'] == true) {
                                if (mounted)
                                  setState(
                                    () => quote = Json.from(result['quote']),
                                  );
                                widget.toast(
                                  'تغيّرت تسعيرة النهار أو الليل؛ راجع السعر الجديد واضغط الحجز لتأكيده',
                                );
                                return;
                              }
                              b.confirmRideCreated(Json.from(result as Map));
                              unawaited(b.refresh(lightweight: true));
                              unawaited(b.kickDispatch());
                            })
                          : null,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  pinSeq++;
                  quoteSeq++;
                  _pinDebounce?.cancel();
                  setState(() {
                    bookingStep = 1;
                    expanded = true;
                    quote = null;
                    quoting = false;
                    snapping = false;
                    pinError = null;
                  });
                  if (mapReady && destination != null)
                    controller.move(destination!, 16);
                  unawaited(snapPin());
                },
                child: const AppText('تعديل الوصول'),
              ),
            ),
          ],
        ),
      ],
    ],
  );
  Widget reviewPlace(String label, bool origin) => Row(
    children: [
      Icon(
        Icons.location_on,
        color: origin ? const Color(0xffe56516) : red,
        size: 24,
      ),
      const SizedBox(width: 14),
      Expanded(
        child: AppText(
          label,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
      ),
      const SizedBox(width: 10),
      SizedBox(
        width: 34,
        height: 34,
        child: PaperCard(
          padding: EdgeInsets.zero,
          onTap: () => searchLocation(origin),
          child: const Icon(Icons.edit_outlined, size: 20),
        ),
      ),
    ],
  );
  Widget paymentChoice(String value, String label, IconData icon) {
    final selected = paymentMethod == value;
    return InkWell(
      onTap: value == 'wallet' && !b.featuresEnabled
          ? null
          : () => setState(() => paymentMethod = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 58,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? (Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xff44212a)
                    : pink)
              : Theme.of(context).colorScheme.surface,
          border: Border.all(color: selected ? red : const Color(0xffbbbbbb)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : icon,
              color: selected ? red : ink,
              size: 24,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(label, style: heading(16)),
                  if (value == 'wallet')
                    AppText(
                      'الرصيد: ${money(b.balance)}',
                      style: const TextStyle(color: muted, fontSize: 10),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    PreferencesScope.of(context);
    final r = b.activeRide;
    if (!b.captain &&
        r == null &&
        (_initialLocationError != null && myLocation == null)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_initialLocationPending) ...[
                const SizedBox(width: 180, child: TuktukLoader()),
                const AppText('جاري تحديد موقعك الحالي'),
              ] else ...[
                const Icon(Icons.location_off_outlined, size: 36, color: red),
                AppText(_initialLocationError!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                if (_locationAccessIssue == LocationAccessIssue.serviceDisabled)
                  FilledButton(
                    onPressed: _openLocationSettings,
                    child: const AppText('تشغيل الموقع'),
                  )
                else if (_locationAccessIssue ==
                    LocationAccessIssue.permissionDeniedForever)
                  FilledButton(
                    onPressed: _openLocationSettings,
                    child: const AppText('فتح إعدادات الإذن'),
                  )
                else if (_locationAccessIssue ==
                    LocationAccessIssue.permissionDenied)
                  FilledButton(
                    onPressed: _locateInitial,
                    child: const AppText('السماح بالموقع'),
                  ),
                TextButton(
                  onPressed: _locateInitial,
                  child: const AppText('إعادة تحديد موقعي'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final rawGeometry = r?['geometry'] ?? quote?['geometry'];
    if (!sameSnapshot(_routeGeometry, rawGeometry)) {
      _routeGeometry = rawGeometry;
      _routePoints = geometry(rawGeometry);
    }
    final route = _routePoints;
    final markers = <Marker>[
      if (myLocation != null || (b.captain && b.position != null))
        Marker(
          point:
              myLocation ?? LatLng(b.position!.latitude, b.position!.longitude),
          width: 28,
          height: 28,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: .18),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(5),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ),
      if (bookingStep != 0 || r != null)
        Marker(
          point: pickup,
          width: r != null ? 150 : 48,
          height: r != null ? 100 : 64,
          alignment: Alignment.topCenter,
          child: r != null
              ? RideEndpointMarker(
                  pickup: r['round_trip_stage'] != 'returning',
                  onTap: () => showRidePlace(r, true),
                )
              : const PickupPin(),
        ),
      if (destination != null && (bookingStep == 2 || r != null))
        Marker(
          point: destination!,
          width: r != null ? 150 : 48,
          height: r != null ? 108 : 72,
          alignment: Alignment.topCenter,
          child: r != null
              ? RideEndpointMarker(
                  pickup: r['round_trip_stage'] == 'returning',
                  onTap: () => showRidePlace(r, false),
                )
              : const DestinationPin(),
        ),
      for (final p in b.nearby)
        Marker(
          point: LatLng(
            (p['lat'] as num).toDouble(),
            (p['lng'] as num).toDouble(),
          ),
          width: 36,
          height: 36,
          child: Image.asset(
            'assets/brand.png',
            cacheWidth: 144,
            fit: BoxFit.contain,
          ),
        ),
    ];
    final height = MediaQuery.sizeOf(context).height;
    final panelMax = bookingStep == 2 && r == null && !b.captain
        ? (height * .58).clamp(300.0, 640.0)
        : (height * .48).clamp(190.0, 430.0);
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: controller,
                options: MapOptions(
                  initialCenter: pickup,
                  initialZoom: 17,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                  maxZoom: 20,
                  keepAlive: true,
                  onMapReady: () {
                    mapReady = true;
                    if (r != null) {
                      if (_captainFresh && _captainDisplay != null) {
                        controller.move(_captainDisplay!, 16);
                      } else {
                        fit(r['geometry']);
                      }
                    } else if (myLocation != null) {
                      controller.move(pickup, 17);
                    }
                  },
                  onTap: (_, p) {
                    if (bookingStep != 2 && r == null && !b.captain) {
                      controller.move(p, controller.camera.zoom);
                      selected(p);
                    }
                  },
                  onPositionChanged: (camera, gesture) {
                    if (gesture && r != null && !b.captain && _followCaptain) {
                      setState(() => _followCaptain = false);
                    }
                    if (gesture && bookingStep != 2 && !b.captain && r == null)
                      selected(camera.center);
                  },
                ),
                children: [
                  const BookingMapLayer(),
                  if (route.length > 1)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: route,
                          color: red,
                          strokeWidth: 4,
                          borderColor: Colors.white,
                          borderStrokeWidth: 2,
                        ),
                      ],
                    ),
                  ValueListenableBuilder<LatLng?>(
                    valueListenable: _captainPosition,
                    builder: (_, captainPoint, child) => MarkerLayer(
                      markers: [
                        ...markers,
                        if (_captainFresh && captainPoint != null)
                          Marker(
                            point: captainPoint,
                            width: 40,
                            height: 40,
                            child: Image.asset(
                              'assets/brand.png',
                              cacheWidth: 144,
                              fit: BoxFit.contain,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (r != null)
                Positioned(
                  top: 12,
                  right: 12,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: () {
                      setState(() => _followCaptain = false);
                      fit(r['geometry']);
                    },
                    icon: const Icon(Icons.route_outlined, size: 18),
                    label: const AppText('عرض المسار'),
                  ),
                ),
              if (bookingStep != 2 && !b.captain && r == null)
                Align(
                  alignment: Alignment.center,
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      transform: Matrix4.translationValues(
                        0,
                        bookingStep == 0 ? -32 : -36,
                        0,
                      ),
                      width: 48,
                      height: bookingStep == 0 ? 64 : 72,
                      child: bookingStep == 0
                          ? PickupPin(moving: _pinMoving)
                          : DestinationPin(moving: _pinMoving),
                    ),
                  ),
                ),
              if (_initialLocationPending)
                const Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: LinearProgressIndicator(),
                ),
              Positioned(
                bottom: 16,
                right: 16,
                child: FloatingActionButton.small(
                  heroTag: 'location',
                  onPressed: () {
                    if (_captainFresh && _captainDisplay != null) {
                      setState(() => _followCaptain = true);
                      controller.move(_captainDisplay!, controller.camera.zoom);
                    } else {
                      unawaited(locate());
                    }
                  },
                  tooltip: _captainFresh ? 'متابعة الكابتن' : 'موقعي الحالي',
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  child: const Icon(Icons.my_location),
                ),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surface.withValues(alpha: .85),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const AppText(
                                  '© تكتوكة',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xff444444),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => launchUrl(
                                    Uri.parse(
                                      'https://www.openstreetmap.org/copyright',
                                    ),
                                  ),
                                  child: const AppText(
                                    '© OpenStreetMap',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Color(0xff444444),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (r != null)
          RideDetailsPanel(
            rideId: '${r['id']}',
            footer: ['pending', 'accepted', 'arrived'].contains(r['status'])
                ? TextButton(
                    onPressed: _statusBusy ? null : () => status('cancelled'),
                    child: const AppText(
                      'إلغاء الرحلة',
                      style: TextStyle(color: scarlet, fontSize: 16),
                    ),
                  )
                : null,
            maxHeight: (height * .55).clamp(240.0, 520.0),
            child: ValueListenableBuilder<int>(
              valueListenable: _countdownTick,
              builder: (_, tick, child) => rideCard(r),
            ),
          )
        else
          Container(
            width: double.infinity,
            constraints: BoxConstraints(maxHeight: panelMax),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
            ),
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: SingleChildScrollView(
                child: ValueListenableBuilder<int>(
                  valueListenable: _countdownTick,
                  builder: (_, tick, child) => b.captain
                      ? captainCard()
                      : b.failedRide != null &&
                            b.failedRide!['id'] == _watchedRideId &&
                            retriedRide != b.failedRide!['id']
                      ? failedSearchCard()
                      : bookingCard(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
