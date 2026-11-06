import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'backend.dart';
import 'commerce.dart';
import 'location_disclosure.dart';

class RestaurantCourierTracking extends ChangeNotifier {
  final Backend b;
  RestaurantCourierTracking(this.b);
  StreamSubscription<Position>? _stream;
  Timer? _heartbeat;
  Position? _latest;
  Future<void>? _sending;
  bool online = false, working = false, _uploading = false, _closed = false;
  String? error;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> start() async {
    if (working || online) return;
    working = true;
    error = null;
    _notify();
    try {
      await b.enableOrderNotifications?.call();
      if (!await locationDisclosure(captain: true)) return;
      if (!await Geolocator.isLocationServiceEnabled())
        throw const LocationAccessException(
          LocationAccessIssue.serviceDisabled,
        );
      final permission = await requestLocationAccess(
        captain: true,
        background: true,
      );
      if (permission == LocationPermission.deniedForever)
        throw const LocationAccessException(
          LocationAccessIssue.permissionDeniedForever,
        );
      if (permission == LocationPermission.denied)
        throw const LocationAccessException(
          LocationAccessIssue.permissionDenied,
        );
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      _latest = position;
      if (_closed) return;
      await _send(position);
      if (_closed) return;
      online = true;
      final LocationSettings settings =
          defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
              intervalDuration: const Duration(seconds: 10),
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationTitle: 'تكتوكة — مندوب المطعم',
                notificationText:
                    'مشاركة الموقع فعالة لاستقبال وتتبع طلبات مطعمك',
                enableWakeLock: true,
              ),
            )
          : AppleSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
              pauseLocationUpdatesAutomatically: false,
              showBackgroundLocationIndicator: true,
              allowBackgroundLocationUpdates: true,
            );
      _stream = Geolocator.getPositionStream(locationSettings: settings).listen(
        (position) {
          _latest = position;
          unawaited(_upload());
        },
        onError: (Object e) {
          error = readable(e);
          _notify();
        },
      );
      _heartbeat = Timer.periodic(
        const Duration(seconds: 20),
        (_) => unawaited(_upload()),
      );
    } catch (e) {
      error = commerceError(e);
    } finally {
      working = false;
      _notify();
    }
  }

  Future<void> _send(Position position) async {
    if (position.accuracy > 100 ||
        DateTime.now().difference(position.timestamp).inSeconds > 60)
      throw StateError('STALE_GPS');
    final request = commerceRpc(b, 'courier_location', {
      'online': true,
      'lat': position.latitude,
      'lng': position.longitude,
    }).then<void>((_) {});
    _sending = request;
    try {
      await request;
    } finally {
      if (identical(_sending, request)) _sending = null;
    }
  }

  Future<void> _upload() async {
    if (_uploading || working || !online || _closed || _latest == null) return;
    _uploading = true;
    try {
      if (DateTime.now().difference(_latest!.timestamp).inSeconds > 40) {
        _latest = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
      }
      if (working || !online || _closed) return;
      await _send(_latest!);
      error = null;
    } catch (e) {
      error = commerceError(e);
    } finally {
      _uploading = false;
      _notify();
    }
  }

  Future<void> stop() async {
    if (working) return;
    working = true;
    _notify();
    try {
      try {
        await _sending;
      } catch (_) {}
      await commerceRpc(b, 'courier_location', {'online': false});
      online = false;
      _heartbeat?.cancel();
      _heartbeat = null;
      await _stream?.cancel();
      _stream = null;
      error = null;
    } catch (e) {
      error = commerceError(e);
    } finally {
      working = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _heartbeat?.cancel();
    unawaited(_stream?.cancel());
    super.dispose();
  }
}
