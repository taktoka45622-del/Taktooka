import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:taktooka/services/location_disclosure.dart';

class PermissionGPS extends GeolocatorPlatform {
  LocationPermission current = LocationPermission.denied;
  int requests = 0;
  Completer<LocationPermission>? pending;
  @override
  Future<LocationPermission> checkPermission() async => current;
  @override
  Future<LocationPermission> requestPermission() {
    requests++;
    return pending?.future ?? Future.value(LocationPermission.whileInUse);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('system location prompt opens directly on $platform', () async {
      final original = GeolocatorPlatform.instance;
      final gps = PermissionGPS();
      GeolocatorPlatform.instance = gps;
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() {
        GeolocatorPlatform.instance = original;
        debugDefaultTargetPlatformOverride = null;
      });
      expect(await requestLocationAccess(), LocationPermission.whileInUse);
      expect(gps.requests, 1);
    });
  }

  test('permanent denial does not repeatedly open system permission', () async {
    final original = GeolocatorPlatform.instance;
    final gps = PermissionGPS()..current = LocationPermission.deniedForever;
    GeolocatorPlatform.instance = gps;
    addTearDown(() => GeolocatorPlatform.instance = original);
    expect(await requestLocationAccess(), LocationPermission.deniedForever);
    expect(gps.requests, 0);
  });

  test('concurrent callers share one system prompt', () async {
    final original = GeolocatorPlatform.instance;
    final gps = PermissionGPS()..pending = Completer<LocationPermission>();
    GeolocatorPlatform.instance = gps;
    addTearDown(() => GeolocatorPlatform.instance = original);
    final first = requestLocationAccess();
    final second = requestLocationAccess();
    await Future<void>.delayed(Duration.zero);
    expect(gps.requests, 1);
    gps.pending!.complete(LocationPermission.whileInUse);
    expect(await first, LocationPermission.whileInUse);
    expect(await second, LocationPermission.whileInUse);
  });
}
