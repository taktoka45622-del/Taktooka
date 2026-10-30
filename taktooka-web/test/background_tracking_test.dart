import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:taktooka/services/backend.dart';

Position fix(double latitude) => Position(
  latitude: latitude,
  longitude: 44.4,
  timestamp: DateTime.now(),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 1,
  speedAccuracy: 0,
);

class GPS extends GeolocatorPlatform {
  final updates = StreamController<Position>();
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.always;
  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.always;
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  LocationSettings? settings;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    settings = locationSettings;
    return updates.stream;
  }
}

class TrackingBackend extends Backend {
  int uploads = 0;
  @override
  bool get subscribed => true;
  @override
  bool get captain => true;
  @override
  bool get loggedIn => true;
  @override
  Future<Position> locate({bool fresh = false}) async => fix(33.54);
  @override
  Future<Position> locatePrecise() => locate(fresh: true);
  @override
  Future<void> refresh({
    bool lightweight = false,
    bool queueIfBusy = true,
  }) async {}
  @override
  Future<void> presence(bool online) async {
    if (!online) return;
    uploads++;
    if (uploads == 2) throw Exception('network temporarily offline');
    lastPresence = DateTime.now();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'tkt_captain_location_disclosed_v1': true,
    });
    await Supabase.initialize(
      url: 'https://example.test',
      anonKey: 'test',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      'GPS survives offline upload and stops only when disabled: $platform',
      () async {
        final previous = GeolocatorPlatform.instance;
        final gps = GPS();
        GeolocatorPlatform.instance = gps;
        debugDefaultTargetPlatformOverride = platform;
        final b = TrackingBackend()
          ..profile = {'name': 'Captain', 'phone': '07700000000'};
        try {
          await b.startTracking();
          if (platform == TargetPlatform.iOS) {
            final settings = gps.settings as AppleSettings;
            expect(settings.allowBackgroundLocationUpdates, true);
            expect(settings.pauseLocationUpdatesAutomatically, false);
          } else {
            expect(
              (gps.settings as AndroidSettings).foregroundNotificationConfig,
              isNotNull,
            );
          }
          b.lastPresence = DateTime(2000);
          gps.updates.add(fix(33.541));
          await Future<void>.delayed(Duration.zero);
          expect(b.tracking, true);
          expect(b.error, isNotEmpty);
          b.lastPresence = DateTime(2000);
          gps.updates.add(fix(33.542));
          await Future<void>.delayed(Duration.zero);
          expect(b.uploads, 3);
          expect(b.error, isNull);
          expect(b.position!.latitude, 33.542);
          await b.stopTracking();
          gps.updates.add(fix(33.543));
          await Future<void>.delayed(Duration.zero);
          expect(b.tracking, false);
          expect(b.uploads, 3);
        } finally {
          b.dispose();
          await gps.updates.close();
          GeolocatorPlatform.instance = previous;
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}
