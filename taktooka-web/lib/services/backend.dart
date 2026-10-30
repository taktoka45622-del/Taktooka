import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:taktooka/core/trip_navigation.dart';
import 'package:taktooka/services/offline_roads.dart';
import 'package:taktooka/services/device_booking.dart';
import 'package:taktooka/core/app_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:taktooka/core/gender_copy.dart';
export 'package:taktooka/core/backend_config.dart';
import 'package:taktooka/services/location_disclosure.dart';
import 'package:taktooka/services/booking_pricing.dart';
import 'package:taktooka/services/refresh_gate.dart';
import 'package:taktooka/core/location_fix_quality.dart';

enum LocationAccessIssue {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  accuracyInsufficient,
}

class LocationAccessException implements Exception {
  final LocationAccessIssue issue;
  const LocationAccessException(this.issue);
  @override
  String toString() => switch (issue) {
    LocationAccessIssue.serviceDisabled => 'شغّل الموقع حتى نحدد نقطة الانطلاق',
    LocationAccessIssue.permissionDenied =>
      'اسمح لتكتوكة باستخدام موقعك حتى نحدد نقطة الانطلاق',
    LocationAccessIssue.accuracyInsufficient => 'الموقع الدقيق بعده مو جاهز؛ فعّل الموقع الدقيق وقرّب من مكان مفتوح ثم أعد المحاولة',
    LocationAccessIssue.permissionDeniedForever =>
      'فعّل إذن الموقع لتكتوكة من إعدادات التطبيق',
  };
}

typedef Json = Map<String, dynamic>;
String westernDigits(String value) => String.fromCharCodes(
  value.trim().runes.map(
    (c) => c >= 0x660 && c <= 0x669
        ? c - 0x660 + 48
        : c >= 0x6f0 && c <= 0x6f9
        ? c - 0x6f0 + 48
        : c,
  ),
);

class Backend extends ChangeNotifier {
  final db = Supabase.instance.client;
  Future<void> Function()? beforeSignOut;
  Future<void> Function()? enableOrderNotifications;
  Future<void> Function(String)? silenceOffer;
  final _refreshGate = RefreshGate();
  Timer? _eventTimer;
  String? _channelKey;
  String? _locationUploadError;
  int _authEpoch = 0;
  bool _foreground = true, _heartbeatRunning = false;
  DateTime _nextPoll = DateTime(2000), _extrasAt = DateTime(2000);
  Object? _publishedSnapshot;

  void setForeground(bool foreground) {
    _foreground = foreground;
    if (foreground) {
      unawaited(refresh());
      unawaited(warmRiderLocation());
      if (tracking) unawaited(_heartbeat());
    } else {
      stopRiderWarmup();
    }
  }

  void _scheduleRefresh() {
    if (_disposed || !_foreground || _eventTimer != null) return;
    _eventTimer = Timer(const Duration(milliseconds: 180), () {
      _eventTimer = null;
      unawaited(refresh(lightweight: true));
    });
  }

  void _bindRealtime() {
    final uid = db.auth.currentUser?.id;
    final key = uid == null ? null : '$uid:$captain:$admin';
    if (key == _channelKey) return;
    _channelKey = key;
    if (channel != null) unawaited(db.removeChannel(channel!));
    channel = null;
    if (uid == null || _disposed) return;
    final next = db.channel('taktooka-mobile-$uid-$captain-$admin');
    next
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tkt_rides',
          filter: admin
              ? null
              : PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: captain ? 'captain_id' : 'rider_id',
                  value: uid,
                ),
          callback: (_) => _scheduleRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tkt_profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) => _scheduleRefresh(),
        );
    if (captain) {
      next.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'tkt_offers',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'captain_id',
          value: uid,
        ),
        callback: (_) => _scheduleRefresh(),
      );
    }
    channel = next..subscribe();
  }

  Future<void> _heartbeat() async {
    if (tracking &&
        gps == null &&
        !_restartingGps &&
        DateTime.now().isAfter(_gpsRetryAt)) {
      _gpsRetryAt = DateTime.now().add(const Duration(seconds: 3));
      try {
        await _listenCaptainGps();
      } catch (_) {}
    }
    if (_heartbeatRunning ||
        !tracking ||
        position == null ||
        DateTime.now().difference(lastPresence).inSeconds < 10)
      return;
    _heartbeatRunning = true;
    try {
      if (DateTime.now()
              .toUtc()
              .difference(position!.timestamp.toUtc())
              .inSeconds >=
          25) {
        final fix = await locate(fresh: true);
        acceptCaptainFix(fix);
      }
      if (tracking && !_disposed) {
        await presence(true);
        _locationSendRecovered();
      }
    } catch (e) {
      _locationUploadError = readable(e);
      error = _locationUploadError;
      _notifyIfChanged();
    } finally {
      _heartbeatRunning = false;
    }
  }

  void _notifyIfChanged() {
    final value = [
      profile,
      commerce,
      rides,
      activeRide,
      contact,
      requests,
      nearby,
      dispatchInfo,
      extras,
      failedRide,
      error,
      tracking,
      city,
      position?.latitude,
      position?.longitude,
      position?.timestamp,
    ];
    if (!sameSnapshot(_publishedSnapshot, value)) {
      _publishedSnapshot = value;
      _notify();
    }
  }

  Json? profile;
  Json extras = {};
  String city = 'بغداد';
  int get balance => (extras['balance'] as num?)?.toInt() ?? 0;
  Json? get coupon {
    if (extras['coupon'] is! Map) return null;
    final value = Json.from(extras['coupon']);
    final expiry = DateTime.tryParse('${value['expires_at']}');
    if (expiry != null && !expiry.isAfter(DateTime.now())) return null;
    return value;
  }

  Future<dynamic> wheel(String action, [Json data = const {}]) => db
      .rpc('tkt_wheel', params: {'p_action': action, 'p_data': data})
      .timeout(const Duration(seconds: 15));

  Future<dynamic> extra(String action, [Json data = const {}]) => db
      .rpc('tkt_extra', params: {'p_action': action, 'p_data': data})
      .timeout(const Duration(seconds: 20));
  Json dispatchInfo = {};
  Json? failedRide;
  DateTime? _serverAnchor;
  final Stopwatch _serverElapsed = Stopwatch();
  bool get featuresEnabled => dispatchInfo['features_enabled'] == true;
  DateTime get serverNow => _serverAnchor == null
      ? DateTime.now().toUtc()
      : _serverAnchor!.add(_serverElapsed.elapsed);
  int offerSeconds(Json offer) =>
      (DateTime.parse(offer['offer_expires_at'])
                  .difference(serverNow)
                  .inMilliseconds /
              1000)
          .ceil()
          .clamp(0, 30);
  void _anchor(dynamic value) {
    if (value is String) {
      _serverAnchor = DateTime.parse(value);
      _serverElapsed.reset();
      _serverElapsed.start();
    }
  }

  Future<dynamic> dispatch(String op, [Json data = const {}]) => db
      .rpc('tkt_dispatch', params: {'p_action': op, 'p_data': data})
      .timeout(const Duration(seconds: 20));
  Future<void> adminLogin(String phone, String pin) async {
    final response = await db.functions.invoke(
      'taktooka-admin-login',
      body: {'phone': westernDigits(phone), 'pin': westernDigits(pin)},
    );
    if (response.data is! Map || response.data['refresh_token'] is! String)
      throw Exception('ADMIN_LOGIN_UNAVAILABLE');
    await db.auth.setSession(response.data['refresh_token']);
    await refresh();
    if (profile?['admin'] != true) {
      await signOut();
      throw Exception('ADMIN_REQUIRED');
    }
  }

  Future<void> kickDispatch() async {
    try {
      await db.functions.invoke('taktooka-dispatch', body: {'op': 'tick'});
    } catch (_) {}
  }

  Timer? _nearbyTimer;
  bool _nearbyReading = false;
  int _nearbyWatchers = 0;
  void watchNearby() {
    _nearbyWatchers++;
    _nearbyTimer ??= Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(refreshNearby());
    });
    unawaited(refreshNearby());
  }

  void unwatchNearby() {
    if (_nearbyWatchers > 0) _nearbyWatchers--;
    if (_nearbyWatchers == 0) {
      _nearbyTimer?.cancel();
      _nearbyTimer = null;
    }
  }

  Future<void> refreshNearby() async {
    if (_disposed ||
        !_foreground ||
        !loggedIn ||
        captain ||
        activeRide != null ||
        _nearbyReading ||
        _nearbyWatchers == 0)
      return;
    _nearbyReading = true;
    final uid = db.auth.currentUser?.id;
    try {
      final result = await action('nearby', {
        'lat': pickupLat,
        'lng': pickupLng,
      }).timeout(const Duration(seconds: 5));
      if (_disposed ||
          !_foreground ||
          db.auth.currentUser?.id != uid ||
          activeRide != null ||
          captain)
        return;
      nearby = rows(result);
      _notifyIfChanged();
    } catch (_) {
      final fresh = nearby.where((p) {
        final at = DateTime.tryParse('${p['location_at']}');
        return at != null && serverNow.difference(at).inSeconds < 30;
      }).toList();
      if (fresh.length != nearby.length) {
        nearby = fresh;
        _notifyIfChanged();
      }
    } finally {
      _nearbyReading = false;
    }
  }

  Json? activeRide;
  Json? contact;
  List<Json> rides = [], requests = [], nearby = [];
  String? error;
  bool syncing = false, tracking = false;
  Timer? timer;
  RealtimeChannel? channel;
  StreamSubscription<AuthState>? authListener;
  StreamSubscription<Position>? gps;
  DateTime lastPresence = DateTime(2000);
  Position? position;
  Position? get knownPosition {
    final rider = _lastRiderPosition;
    final captainPosition = position;
    if (rider == null) return captainPosition;
    if (captainPosition == null) return rider;
    return rider.timestamp.isAfter(captainPosition.timestamp)
        ? rider
        : captainPosition;
  }

  double pickupLat = 33.54844, pickupLng = 44.41179;
  bool _disposed = false;
  bool _presenceSending = false;
  Future<void> _presenceQueue = Future<void>.value();
  bool get loggedIn => db.auth.currentSession != null;
  Json commerce = {};
  bool get restaurantOwner => commerce['restaurant'] is Map;
  bool get commissionPlan => commerce['plan'] == 'commission';
  bool get canReceiveOrders =>
      (commissionPlan || subscribed) && commerce['debt_blocked'] != true;
  bool get captain => profile?['captain'] == true;
  bool get admin => profile?['admin'] == true;
  bool get subscribed =>
      DateTime.tryParse(profile?['expires_at'] ?? '')
          ?.isAfter(DateTime.now()) ??
      false;

  Future<dynamic> action(String action, [Json data = const {}]) async => db
      .rpc('tkt_action', params: {'p_action': action, 'p_data': data})
      .timeout(const Duration(seconds: 20));

  final Map<String, DateTime> _tripStarts = {};
  Future<void> _saveTripStart(String id, DateTime at) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'taktooka_trip_start_$id',
        at.toUtc().toIso8601String(),
      );
    } catch (_) {}
  }

  Future<void> _restoreTripStart(Json ride) async {
    final id = ride['id'] as String;
    DateTime? at = _tripStarts[id];
    if (at == null) {
      try {
        final preferences = await SharedPreferences.getInstance();
        at = DateTime.tryParse(
          preferences.getString('taktooka_trip_start_$id') ?? '',
        );
      } catch (_) {}
      at ??=
          DateTime.tryParse('${ride['started_at'] ?? ride['updated_at']}') ??
          serverNow;
      _tripStarts[id] = at;
      unawaited(_saveTripStart(id, at));
    }
    ride['started_at'] = at.toUtc().toIso8601String();
  }

  int _rideRevision = 0;
  void confirmRideCreated(Json ride) {
    if (ride['id'] == null) throw StateError('RIDE_UNAVAILABLE');
    _rideRevision++;
    rides = [ride, ...rides.where((r) => r['id'] != ride['id'])];
    activeRide = ride;
    failedRide = contact = null;
    _notifyIfChanged();
  }

  void confirmRideUpdated(Json ride) {
    if (ride['id'] == null) throw StateError('RIDE_UNAVAILABLE');
    _rideRevision++;
    rides = [ride, ...rides.where((r) => r['id'] != ride['id'])];
    if (activeRide?['id'] == ride['id']) activeRide = ride;
    _notifyIfChanged();
  }

  void confirmRideStatus(String rideId, String status) {
    _rideRevision++;
    final start = status == 'in_progress' ? serverNow : null;
    if (start != null) {
      _tripStarts[rideId] = start;
      unawaited(_saveTripStart(rideId, start));
    }
    for (final ride in rides) {
      if (ride['id'] == rideId) {
        ride['status'] = status;
        if (start != null) ride['started_at'] = start.toUtc().toIso8601String();
      }
    }
    if (activeRide?['id'] == rideId) {
      if (['cancelled', 'completed'].contains(status)) {
        activeRide = null;
        contact = null;
        failedRide = null;
      } else {
        activeRide = {
          ...activeRide!,
          'status': status,
          if (start != null) 'started_at': start.toUtc().toIso8601String(),
        };
      }
    }
    _notifyIfChanged();
  }

  static List<Json> rows(dynamic value) =>
      (value as List).map((e) => Json.from(e as Map)).toList();

  Future<void> start() async {
    unawaited(warmRiderLocation());
    if (loggedIn) unawaited(appPreferences.rememberAccountUse());
    authListener = db.auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.signedOut) {
          _clearSignedOutState();
          unawaited(stopTracking());
        } else if (state.event == AuthChangeEvent.signedIn) {
          unawaited(appPreferences.rememberAccountUse());
          _authEpoch++;
          _extrasAt = DateTime(2000);
          _bindRealtime();
          unawaited(refresh());
          unawaited(
            BookingPricing.syncOnce(() => db.rpc('tkt_booking_pricing')),
          );
        }
      },
      onError: (Object e) {
        error = readable(e);
        _notifyIfChanged();
      },
    );
    _bindRealtime();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_heartbeat());
      if (_foreground && DateTime.now().isAfter(_nextPoll)) {
        unawaited(refresh(lightweight: true, queueIfBusy: false));
      }
    });
    await refresh();
    if (loggedIn)
      unawaited(BookingPricing.syncOnce(() => db.rpc('tkt_booking_pricing')));
    await restoreTracking();
  }

  Future<void> refresh({bool lightweight = false, bool queueIfBusy = true}) {
    if (!loggedIn || _disposed) return Future<void>.value();
    return _refreshGate.run(
      _refreshOnce,
      full: !lightweight,
      queue: queueIfBusy,
    );
  }

  Future<(dynamic, Object?)> _read(Future<dynamic> request) async {
    try {
      return (await request, null);
    } catch (e) {
      return (null, e);
    }
  }

  Future<void> _refreshOnce(bool full) async {
    if (!loggedIn || _disposed) return;
    syncing = true;
    final uid = db.auth.currentUser!.id;
    final epoch = _authEpoch;
    final rideRevision = _rideRevision;
    bool current() =>
        !_disposed &&
        db.auth.currentUser?.id == uid &&
        _authEpoch == epoch &&
        _rideRevision == rideRevision;
    final loadExtras =
        featuresEnabled &&
        (full || DateTime.now().difference(_extrasAt).inSeconds >= 30);
    final extrasRequest = loadExtras
        ? _read(extra('snapshot'))
        : Future.value((extras, null));
    try {
      final primary = await Future.wait([
        _read(action('me')),
        _read(action('snapshot')),
        _read(dispatch('snapshot')),
        _read(db.rpc('tkt_commerce', params: {'p_action': 'me', 'p_data': {}})),
      ]);
      if (!current()) return;
      final oldCaptain = captain;
      if (primary[0].$2 != null) throw primary[0].$2!;
      profile = Json.from(primary[0].$1 as Map);
      commerce = primary[3].$1 is Map ? Json.from(primary[3].$1 as Map) : {};
      if (captain && tracking) {
        stopRiderWarmup();
      } else {
        unawaited(warmRiderLocation());
      }
      accountGender.value = profile?['gender'] == 'female' ? 'female' : 'male';
      _bindRealtime();
      if (profile!['blocked'] == true) {
        rides = [];
        activeRide = contact = failedRide = null;
        requests = [];
        nearby = [];
        extras = {};
        await stopTracking();
        error = 'حسابك محظور؛ تواصل مع الإدارة';
        return;
      }
      if (tracking && (!captain || (oldCaptain && oldCaptain != captain))) {
        await stopTracking();
        if (!current()) return;
      }
      if (primary[1].$2 != null) throw primary[1].$2!;
      if (primary[2].$2 != null) throw primary[2].$2!;
      rides = rows(primary[1].$1);
      activeRide = null;
      for (final ride in rides) {
        if ([
          'pending',
          'accepted',
          'arrived',
          'in_progress',
        ].contains(ride['status'])) {
          if (ride['status'] == 'in_progress') {
            await _restoreTripStart(ride);
            if (!current()) return;
          }
          activeRide = ride;
          break;
        }
      }
      dispatchInfo = Json.from(primary[2].$1 as Map);
      _anchor(dispatchInfo['server_now']);
      failedRide =
          activeRide == null &&
              rides.isNotEmpty &&
              rides.first['dispatch_state'] == 'no_captain'
          ? rides.first
          : null;
      if (tracking &&
          ((!canReceiveOrders &&
                  activeRide == null &&
                  commerce['food_active'] != true) ||
              !captain ||
              oldCaptain != captain)) {
        await stopTracking();
        if (!current()) return;
      }
      error = null;
      if (activeRide == null || activeRide!['status'] == 'pending')
        contact = null;
      if (!captain || !tracking || activeRide != null) requests = [];
      if (captain || activeRide != null) nearby = [];
      _notifyIfChanged();
      final details = await Future.wait<dynamic>([
        captain && tracking && activeRide == null
            ? action('requests')
            : Future.value([]),
        activeRide != null && activeRide!['status'] != 'pending'
            ? action('contact', {'ride_id': activeRide!['id']})
            : Future.value(null),
        Future.value(<dynamic>[]),
        extrasRequest,
        activeRide != null && activeRide!['status'] != 'pending'
            ? _read(
                db
                    .rpc(
                      'tkt_navigation',
                      params: {
                        'p_action': 'read',
                        'p_data': {
                          'ride_id': activeRide!['id'],
                          if (_sharedNavigation?['ride_id'] ==
                                  activeRide!['id'] &&
                              _sharedNavigation?['phase'] ==
                                  TripNavigation.phase(activeRide!))
                            'known_updated_at':
                                _sharedNavigation?['updated_at'],
                        },
                      },
                    )
                    .timeout(const Duration(seconds: 5)),
              )
            : Future.value((<String, dynamic>{}, null)),
      ]);
      if (!current()) return;
      requests = rows(details[0]);
      if (requests.isNotEmpty) _anchor(requests.first['server_now']);
      contact = details[1] is Map ? Json.from(details[1] as Map) : null;
      final navigation = details[4] as (dynamic, Object?);
      if (navigation.$2 == null && navigation.$1 is Map && activeRide != null) {
        final result = Json.from(navigation.$1 as Map);
        final value = result['unchanged'] == true ? _sharedNavigation : result;
        if (value != null &&
            value['ride_id'] == activeRide!['id'] &&
            value['phase'] == TripNavigation.phase(activeRide!)) {
          _sharedNavigation = value;
          activeRide = {...activeRide!, 'navigation': value};
        } else {
          _sharedNavigation = null;
        }
      }
      _syncNavigation();
      if (activeRide?['status'] == 'in_progress') {
        contact?.remove('phone');
        if (!captain) unawaited(refreshEmergencyLocation(activeRide!['id']));
      }
      if (captain || activeRide != null) nearby = [];
      final extraResult = details[3] as (dynamic, Object?);
      if (extraResult.$2 == null) {
        extras = featuresEnabled ? Json.from(extraResult.$1 as Map) : {};
        if (loadExtras) _extrasAt = DateTime.now();
      }
      error = null;
    } catch (e) {
      if (current()) error = readable(e);
    } finally {
      syncing = false;
      final seconds = error != null
          ? 10
          : (tracking || activeRide != null ? 1 : 10);
      _nextPoll = DateTime.now().add(Duration(seconds: seconds));
      if (current()) _notifyIfChanged();
    }
  }

  StreamSubscription<Position>? _riderGps;
  Future<void>? _warmingRider;
  Future<Position>? _preciseRequest;
  final _riderFixes = StreamController<Position>.broadcast();
  Stream<Position> get riderLocationFixes => _riderFixes.stream;
  int _riderGpsEpoch = 0;
  bool _goodFix(Position fix) => LocationFixQuality.usable(
    latitude: fix.latitude,
    longitude: fix.longitude,
    accuracy: fix.accuracy,
    timestamp: fix.timestamp,
  );
  bool _displayFix(Position fix) => LocationFixQuality.usable(
    latitude: fix.latitude,
    longitude: fix.longitude,
    accuracy: fix.accuracy,
    timestamp: fix.timestamp,
    accuracyLimit: 50,
    ageLimit: const Duration(seconds: 30),
  );
  Future<void> warmRiderLocation() {
    if (_disposed || !_foreground || (captain && tracking) || _riderGps != null)
      return Future.value();
    return _warmingRider ??= _warmRider().whenComplete(() {
      _warmingRider = null;
    });
  }

  Future<void> _warmRider() async {
    final epoch = _riderGpsEpoch;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always)
        return;
      if (!await Geolocator.isLocationServiceEnabled()) return;
      if (_disposed ||
          !_foreground ||
          (captain && tracking) ||
          epoch != _riderGpsEpoch)
        return;
      _riderGps =
          Geolocator.getPositionStream(
            locationSettings: defaultTargetPlatform == TargetPlatform.android
                ? AndroidSettings(
                    accuracy: LocationAccuracy.bestForNavigation,
                    distanceFilter: 0,
                    intervalDuration: const Duration(seconds: 1),
                  )
                : defaultTargetPlatform == TargetPlatform.iOS
                ? AppleSettings(
                    accuracy: LocationAccuracy.bestForNavigation,
                    distanceFilter: 0,
                    allowBackgroundLocationUpdates: false,
                  )
                : const LocationSettings(
                    accuracy: LocationAccuracy.bestForNavigation,
                    distanceFilter: 0,
                  ),
          ).listen(
            (fix) {
              if (_disposed ||
                  !_foreground ||
                  (captain && tracking) ||
                  epoch != _riderGpsEpoch ||
                  !_displayFix(fix))
                return;
              if (captain) {
                acceptCaptainFix(fix);
              } else {
                _lastRiderPosition = fix;
                _riderFixes.add(fix);
              }
            },
            onError: (Object _) {
              _riderGps = null;
            },
            cancelOnError: true,
          );
      unawaited(
        Geolocator.getLastKnownPosition()
            .timeout(const Duration(seconds: 2))
            .then<void>((fix) {
              if (fix != null &&
                  !_disposed &&
                  _foreground &&
                  epoch == _riderGpsEpoch &&
                  _displayFix(fix)) {
                if (_lastRiderPosition == null ||
                    fix.timestamp.isAfter(_lastRiderPosition!.timestamp)) {
                  if (captain) {
                    acceptCaptainFix(fix);
                  } else {
                    _lastRiderPosition = fix;
                    _riderFixes.add(fix);
                  }
                }
              }
            }, onError: (Object _) {}),
      );
    } catch (_) {}
  }

  void stopRiderWarmup() {
    _riderGpsEpoch++;
    final subscription = _riderGps;
    _riderGps = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  Future<Position> locatePrecise() {
    return _preciseRequest ??= _locatePrecise().whenComplete(() {
      _preciseRequest = null;
    });
  }

  Future<Position> _locatePrecise() async {
    if (captain) {
      final fix = position != null && _goodFix(position!)
          ? position!
          : await locate(fresh: true);
      if (_goodFix(fix)) return fix;
      throw const LocationAccessException(
        LocationAccessIssue.accuracyInsufficient,
      );
    }
    final permission = await requestLocationAccess();
    if (permission == LocationPermission.deniedForever)
      throw const LocationAccessException(
        LocationAccessIssue.permissionDeniedForever,
      );
    if (permission == LocationPermission.denied)
      throw const LocationAccessException(LocationAccessIssue.permissionDenied);
    if (!await Geolocator.isLocationServiceEnabled())
      throw const LocationAccessException(LocationAccessIssue.serviceDisabled);
    if (!kIsWeb &&
        await Geolocator.getLocationAccuracy() ==
            LocationAccuracyStatus.reduced)
      throw const LocationAccessException(
        LocationAccessIssue.accuracyInsufficient,
      );
    await warmRiderLocation();
    if (_riderGps == null && _foreground) await warmRiderLocation();
    final cached = _lastRiderPosition;
    if (cached != null && _goodFix(cached)) return cached;
    try {
      return await _riderFixes.stream
          .firstWhere(_goodFix)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const LocationAccessException(
        LocationAccessIssue.accuracyInsufficient,
      );
    }
  }

  Position? _lastRiderPosition;
  bool _riderLocationSending = false;
  DateTime _riderLocationSent = DateTime(2000);
  Future<void> refreshEmergencyLocation(dynamic rideId) async {
    if (captain ||
        _riderLocationSending ||
        _disposed ||
        !_foreground ||
        DateTime.now().difference(_riderLocationSent).inSeconds < 10)
      return;
    _riderLocationSending = true;
    _riderLocationSent = DateTime.now();
    try {
      final fix = await locate(fresh: true);
      if (_disposed ||
          activeRide?['id'] != rideId ||
          activeRide?['status'] != 'in_progress')
        return;
      position = fix;
      await db.rpc(
        'tkt_emergency',
        params: {
          'p_action': 'location',
          'p_data': {
            'ride_id': rideId,
            'lat': fix.latitude,
            'lng': fix.longitude,
            'location_at': fix.timestamp.toUtc().toIso8601String(),
          },
        },
      );
    } catch (_) {
    } finally {
      _riderLocationSending = false;
    }
  }

  Future<Position>? _locationRequest;
  Future<Position> locate({bool fresh = false}) async {
    final permission = await requestLocationAccess(captain: captain);
    if (permission == LocationPermission.deniedForever) {
      throw const LocationAccessException(
        LocationAccessIssue.permissionDeniedForever,
      );
    }
    if (permission == LocationPermission.denied) {
      throw const LocationAccessException(LocationAccessIssue.permissionDenied);
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationAccessException(LocationAccessIssue.serviceDisabled);
    }
    final cached = knownPosition ?? await Geolocator.getLastKnownPosition();
    if (!fresh &&
        cached != null &&
        (captain ? _goodFix(cached) : _displayFix(cached))) {
      _lastRiderPosition = cached;
      return cached;
    }
    if (_locationRequest != null) return _locationRequest!;
    final request = Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: captain
            ? LocationAccuracy.bestForNavigation
            : LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
    _locationRequest = request;
    try {
      final result = await request;
      if (captain && !_goodFix(result)) {
        throw const LocationAccessException(
          LocationAccessIssue.accuracyInsufficient,
        );
      }
      _lastRiderPosition = result;
      return result;
    } finally {
      if (identical(_locationRequest, request)) _locationRequest = null;
    }
  }

  Json? _sharedNavigation;
  late final TripNavigation _navigation = TripNavigation(
    load: (from, to) async {
      if (!kIsWeb) {
        try {
          return await OfflineRoads.shared
              .route(from.latitude, from.longitude, to.latitude, to.longitude)
              .timeout(const Duration(seconds: 3));
        } catch (_) {}
      }
      return DeviceBooking.shared.route(from, to);
    },
    publish: (data) async {
      await db
          .rpc(
            'tkt_navigation',
            params: {'p_action': 'publish', 'p_data': data},
          )
          .timeout(const Duration(seconds: 8));
      if (!_disposed &&
          activeRide?['id'] == data['ride_id'] &&
          TripNavigation.phase(activeRide!) == data['phase']) {
        activeRide = {...activeRide!, 'navigation': data};
        _notifyIfChanged();
      }
    },
  );

  void _syncNavigation() {
    final ride = activeRide;
    final fix = position;
    if (_disposed ||
        !captain ||
        !tracking ||
        ride == null ||
        fix == null ||
        !_goodFix(fix))
      return;
    final phase = TripNavigation.phase(ride);
    unawaited(
      _navigation.update(
        Json.from(ride),
        LatLng(fix.latitude, fix.longitude),
        fix.timestamp,
        isCurrent: () =>
            !_disposed &&
            tracking &&
            activeRide?['id'] == ride['id'] &&
            TripNavigation.phase(activeRide!) == phase,
      ),
    );
  }

  void _locationSendRecovered() {
    if (error == _locationUploadError) error = null;
    _locationUploadError = null;
  }

  bool acceptCaptainFix(Position fix) {
    if (_disposed || !_goodFix(fix)) return false;
    final previous = position;
    if (previous != null && !fix.timestamp.isAfter(previous.timestamp))
      return false;
    position = fix;
    _lastRiderPosition = fix;
    _notifyIfChanged();
    _syncNavigation();
    return true;
  }

  bool _presenceAgain = false;
  Future<void> presence(bool online) {
    if (online && (position == null || !tracking)) return Future<void>.value();
    if (online && _presenceSending) {
      _presenceAgain = true;
      return _presenceQueue;
    }
    _presenceSending = true;
    final next = _presenceQueue.catchError((Object _) {}).then((_) async {
      try {
        _presenceAgain = false;
        if (online && (!tracking || position == null || !_goodFix(position!)))
          return;
        final point = position;
        await db.functions
            .invoke(
              'taktooka-dispatch',
              body: {
                'op': 'presence',
                'online': online,
                if (point != null) 'lat': point.latitude,
                if (point != null) 'lng': point.longitude,
                if (point != null)
                  'gps_at': point.timestamp.toUtc().toIso8601String(),
              },
            )
            .timeout(const Duration(seconds: 15));
        lastPresence = DateTime.now();
      } finally {
        _presenceSending = false;
        if (online && tracking && _presenceAgain && !_disposed) {
          _presenceAgain = false;
          unawaited(
            presence(true).then(
              (_) {
                _locationSendRecovered();
              },
              onError: (Object e) {
                _locationUploadError = readable(e);
                error = _locationUploadError;
                _notifyIfChanged();
              },
            ),
          );
        }
      }
    });
    _presenceQueue = next;
    return next;
  }

  bool _restoringTracking = false;
  Future<void> restoreTracking() async {
    if (_restoringTracking ||
        tracking ||
        !captain ||
        (!canReceiveOrders && commerce['food_active'] != true) ||
        !loggedIn)
      return;
    _restoringTracking = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = db.auth.currentUser?.id;
      if (uid != null &&
          (prefs.getBool('receive_orders_$uid') == true ||
              profile?['online'] == true)) {
        await startTracking();
      }
    } catch (e) {
      error = readable(e);
    } finally {
      _restoringTracking = false;
    }
  }

  Future<void>? _startingTracking;
  Future<void> startTracking() => _startingTracking ??= _startTracking()
      .whenComplete(() => _startingTracking = null);

  Future<void> _startTracking() async {
    if (tracking) return;
    if (!canReceiveOrders && commerce['food_active'] != true)
      throw Exception('جدّد حسابك عبر الدعم أولًا');
    if (!await locationDisclosure(captain: true)) return;
    await requestLocationAccess(captain: true, background: true);
    if ((profile?['name'] ?? '').isEmpty || (profile?['phone'] ?? '').isEmpty)
      throw Exception('أكمل اسمك ورقم هاتفك أولًا');
    final fix = await locatePrecise();
    if (_disposed || !loggedIn || !captain) return;
    position = fix;
    final warming = _riderGps;
    stopRiderWarmup();
    if (warming != null) await warming.cancel();
    tracking = true;
    _notifyIfChanged();
    try {
      await _listenCaptainGps();
      await presence(true);
    } catch (_) {
      tracking = false;
      await gps?.cancel();
      gps = null;
      _notifyIfChanged();
      unawaited(warmRiderLocation());
      rethrow;
    }
    final prefs = await SharedPreferences.getInstance();
    final uid = db.auth.currentUser?.id;
    if (uid != null) await prefs.setBool('receive_orders_$uid', true);
    unawaited(refresh());
  }

  DateTime _gpsRetryAt = DateTime(2000);
  bool _restartingGps = false;
  Future<void> _listenCaptainGps() async {
    if (!tracking || _disposed || _restartingGps) return;
    _restartingGps = true;
    try {
      await gps?.cancel();
      gps =
          Geolocator.getPositionStream(
            locationSettings: defaultTargetPlatform == TargetPlatform.android
                ? AndroidSettings(
                    accuracy: LocationAccuracy.bestForNavigation,
                    distanceFilter: 0,
                    intervalDuration: const Duration(seconds: 1),
                    foregroundNotificationConfig:
                        const ForegroundNotificationConfig(
                          notificationTitle: 'تكتوكة — مشاركة موقع الكابتن',
                          notificationText: 'موقعك يُشارك لاستقبال الرحلات وتتبع الرحلة الحالية',
                          enableWakeLock: true,
                          setOngoing: true,
                        ),
                  )
                : AppleSettings(
                    accuracy: LocationAccuracy.bestForNavigation,
                    distanceFilter: 0,
                    activityType: ActivityType.automotiveNavigation,
                    pauseLocationUpdatesAutomatically: false,
                    allowBackgroundLocationUpdates: true,
                    showBackgroundLocationIndicator: true,
                  ),
          ).listen(
            (p) async {
              if (!tracking || !acceptCaptainFix(p)) return;
              if (!_presenceSending &&
                  DateTime.now().difference(lastPresence).inSeconds < 1)
                return;
              try {
                await presence(true);
                _locationSendRecovered();
                _notifyIfChanged();
              } catch (e) {
                _locationUploadError = readable(e);
                error = _locationUploadError;
                _notify();
              }
            },
            onError: (Object e) {
              gps = null;
              _gpsRetryAt = DateTime.now().add(const Duration(seconds: 2));
              _locationUploadError = readable(e);
              error = _locationUploadError;
              _notifyIfChanged();
            },
            cancelOnError: true,
          );
    } finally {
      _restartingGps = false;
    }
  }

  Future<void> stopTracking() async {
    final uid = db.auth.currentUser?.id;
    if (uid != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('receive_orders_$uid', false);
    }
    tracking = false;
    _presenceAgain = false;
    _notifyIfChanged();
    await gps?.cancel();
    gps = null;
    if (loggedIn && captain) {
      try {
        await presence(false);
      } catch (_) {}
    }
    requests = [];
    _notify();
    unawaited(warmRiderLocation());
  }

  Future<void>? _signingOut;

  Future<void> signOut() => _signingOut ??= _performSignOut().whenComplete(() {
    _signingOut = null;
  });

  Future<void> _logoutCleanup(Future<void> Function() action) async {
    try {
      await action().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  void _clearSignedOutState() {
    stopRiderWarmup();
    _lastRiderPosition = null;
    _authEpoch++;
    profile = null;
    commerce = {};
    _sharedNavigation = null;
    accountGender.value = 'male';
    extras = {};
    dispatchInfo = {};
    failedRide = activeRide = contact = null;
    rides = [];
    requests = [];
    nearby = [];
    tracking = false;
    _extrasAt = DateTime(2000);
    _bindRealtime();
    _notify();
  }

  Future<void> _performSignOut() async {
    final cleanup = beforeSignOut;
    await Future.wait([
      if (loggedIn) _logoutCleanup(appPreferences.rememberAccountUse),
      if (cleanup != null) _logoutCleanup(cleanup),
      _logoutCleanup(stopTracking),
    ]);
    try {
      await db.auth
          .signOut(scope: SignOutScope.local)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      if (db.auth.currentSession != null) rethrow;
    } finally {
      if (db.auth.currentSession == null) {
        _clearSignedOutState();
        await appPreferences.showOnboardingAfterLogout();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    stopRiderWarmup();
    _riderFixes.close();
    _nearbyTimer?.cancel();
    _disposed = true;
    timer?.cancel();
    _eventTimer?.cancel();
    gps?.cancel();
    authListener?.cancel();
    if (channel != null) db.removeChannel(channel!);
    super.dispose();
  }
}

String readable(Object e) {
  final m = e is FunctionException && e.details is Map
      ? (e.details as Map)['error'].toString()
      : e.toString();
  if (m.contains('الخدمة متاحة داخل الحسينية') ||
      m.contains('الخدمة متاحة داخل الحسينيه')) {
    return 'المنطقة المحددة خارج خدماتنا، سنصل قريبًا';
  }
  const errors = {
    'FEATURE_NOT_ENABLED': 'هذه الخدمة تحتاج تفعيل تحديث السيرفر',
    'INVALID_ADMIN_LOGIN': 'رقم الإدارة أو الرمز غير صحيح',
    'ADMIN_LOGIN_LOCKED': 'تم إيقاف المحاولات مؤقتًا؛ جرّب بعد 15 دقيقة',
    'ADMIN_LOGIN_UNAVAILABLE': 'دخول الإدارة غير متاح حاليًا؛ حاول مجددًا',
    'INVALID_NEW_PIN': 'اكتب رمزًا جديدًا من 6 إلى 12 رقمًا غير متكرر',
    'OFFER_EXPIRED': 'انتهت مهلة العرض أو أُلغيت الرحلة',
    'STALE_GPS': 'تعذر تحديث موقعك؛ انتظر إشارة GPS حديثة',
    'INVALID_ZONES': 'حدود منطقة الخدمة غير صحيحة',
    'SEARCH_IN_PROGRESS': 'انتظر انتهاء عمليات البحث قبل تعديل مناطق الخدمة',
    'PGRST202': 'المحفظة والعروض والدعم تحتاج تفعيل تحديث السيرفر',
    'INSUFFICIENT_BALANCE': 'رصيد المحفظة غير كافي',
    'COUPON_EXPIRED': 'الكود غير متاح أو مستخدم؛ احذفه وجرب كود ثاني',
    'INVALID_AMOUNT': 'اكتب مبلغ صحيح',
    'ADDRESS_LIMIT': 'وصلت الحد الأعلى للعناوين المحفوظة',
    'FORBIDDEN': 'هذا الإجراء غير مسموح لحسابك',
    'AUTH_REQUIRED': 'سجّل دخولك أولًا',
    'ACCOUNT_BLOCKED': 'حسابك محظور',
    'SUBSCRIPTION_EXPIRED': 'اشتراكك منتهي',
    'ADMIN_REQUIRED': 'هذا الإجراء للإدارة فقط',
    'RIDE_UNAVAILABLE': 'الطلب لم يعد متاحًا',
    'WAIT_MINUTES_REQUIRED': 'حدد وقت الانتظار من 1 إلى 15 دقيقة',
    'INVALID_TRIP_MODE': 'اختَر نوع الرحلة مرة ثانية',
    'ROUND_TRIP_DESTINATION_LOCKED':
        'وجهة الذهاب والإياب مثبتة مع الرجعة إلى نقطة الانطلاق',
    'INVALID_ROUND_TRIP_PHASE':
        'حدث الرحلة وتأكد من مرحلة الذهاب أو الانتظار أو الرجعة',
    'ROUND_TRIP_RETURN_REQUIRED': 'ابدأ الرجعة قبل إنهاء رحلة الذهاب والإياب',
    'QUOTE_EXPIRED': 'انتهت صلاحية السعر؛ احسب الطريق مجددًا',
    'CAPTAIN_UNAVAILABLE': 'شارك موقعك وتأكد من اشتراكك',
    'INVALID_STATUS_OR_CODE': 'حالة غير صحيحة أو رمز الرحلة غير صحيح',
    'INVALID_PROFILE': 'تأكد من الاسم ورقم الهاتف العراقي',
    'ACTIVE_RIDE': 'أكمل الرحلة الجارية أولًا',
    'OUTSIDE_SERVICE': 'المنطقة المحددة خارج خدماتنا، سنصل قريبًا',
    'ROUTE_UNAVAILABLE':
        'تعذر حساب الطريق والسعر؛ اضغط إعادة حساب الطريق وحاول مجددًا',
    'DESTINATION_CHANGED':
        'تغيّرت حالة الرحلة أو الوجهة؛ حدّث وراجع السعر مجددًا',
    'PRICE_CONFIRMATION_REQUIRED': 'راجع السعر وأكد الحجز من النسخة المحدثة',
    'DESTINATION_CASH_ONLY': 'تغيير الوجهة متاح حاليًا لرحلات الكاش بدون خصم',
    'RATE_LIMIT': 'انتظر دقيقة قبل حساب مسار جديد',
    'SERVICE_UNAVAILABLE': 'خدمة الطريق غير متاحة حاليًا',
    '23505': 'عندك رحلة فعالة أو تم قبول الطلب بالفعل',
    'Invalid login': 'بيانات الدخول غير صحيحة',
    'Email not confirmed': 'أكد بريدك الإلكتروني أولًا',
  };
  for (final item in errors.entries) {
    if (m.contains(item.key)) return item.value;
  }
  if (m.startsWith('Exception:')) return m.substring(11);
  return 'تعذر تنفيذ العملية. تأكد من الاتصال وحاول مجددًا';
}
