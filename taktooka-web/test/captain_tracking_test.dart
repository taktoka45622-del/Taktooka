import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taktooka/services/backend.dart';

Position fix(double lat, double lng, {double accuracy = 8, DateTime? at}) =>
    Position(
      latitude: lat,
      longitude: lng,
      timestamp: at ?? DateTime.now(),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 1,
      heading: 0,
      headingAccuracy: 1,
      speed: 0,
      speedAccuracy: 1,
    );

class CaptainBackend extends Backend {
  @override
  bool get loggedIn => true;
  @override
  Future<void> refresh({
    bool lightweight = false,
    bool queueIfBusy = true,
  }) async {}
}

class FakeGps extends GeolocatorPlatform {
  final updates = StreamController<Position>.broadcast();
  Position current = fix(33.34, 44.4);
  int queries = 0;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.always;
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => current;
  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    queries++;
    return current;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      updates.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final uploads = <Map<String, dynamic>>[];
  Completer<void>? gate;
  Completer<void>? entered;
  late GeolocatorPlatform original;
  late FakeGps gps;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'tkt_captain_location_disclosed_v1': true,
    });
    await Supabase.initialize(
      url: 'https://example.test',
      anonKey: 'test',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('taktooka-dispatch')) {
          uploads.add(
            Map<String, dynamic>.from(jsonDecode(request.body) as Map),
          );
          if (entered != null && !entered!.isCompleted) entered!.complete();
          final pending = gate;
          gate = null;
          if (pending != null) await pending.future;
        }
        return http.Response(
          '{"ok":true}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  setUp(() {
    original = GeolocatorPlatform.instance;
    gps = FakeGps();
    GeolocatorPlatform.instance = gps;
    uploads.clear();
    gate = null;
  });
  tearDown(() async {
    GeolocatorPlatform.instance = original;
    await gps.updates.close();
  });
  CaptainBackend backend() => CaptainBackend()
    ..profile = {
      'name': 'Test Captain',
      'phone': '07700000000',
      'captain': true,
      'expires_at': DateTime.now()
          .add(const Duration(days: 1))
          .toIso8601String(),
    };

  test(
    'location notifies immediately and rejects stale inaccurate or reordered fixes',
    () {
      final b = backend();
      var changes = 0;
      b.addListener(() => changes++);
      final now = DateTime.now();
      expect(b.acceptCaptainFix(fix(33.34, 44.4, at: now)), true);
      final first = changes;
      expect(
        b.acceptCaptainFix(
          fix(33.35, 44.41, at: now.add(const Duration(milliseconds: 1))),
        ),
        true,
      );
      expect(changes, greaterThan(first));
      expect(b.acceptCaptainFix(fix(33.5, 44.5, accuracy: 300)), false);
      expect(
        b.acceptCaptainFix(
          fix(33.5, 44.5, at: now.subtract(const Duration(minutes: 1))),
        ),
        false,
      );
      expect(b.acceptCaptainFix(fix(33.1, 44.1, at: now)), false);
      expect(b.position!.latitude, 33.35);
      b.dispose();
    },
  );

  test(
    'slow presence sends newest pending position without waiting for another GPS event',
    () async {
      final b = backend()..tracking = true;
      b.acceptCaptainFix(fix(33.34, 44.4));
      final pending = Completer<void>();
      gate = pending;
      entered = Completer<void>();
      final first = b.presence(true);
      await entered!.future;
      final secondEntered = Completer<void>();
      entered = secondEntered;
      final next = fix(
        33.35,
        44.41,
        at: DateTime.now().add(const Duration(milliseconds: 1)),
      );
      b.acceptCaptainFix(next);
      final second = b.presence(true);
      pending.complete();
      await Future.wait([first, second]);
      await secondEntered.future.timeout(const Duration(seconds: 2));
      expect(uploads.length, 2);
      expect(uploads.last['lat'], next.latitude);
      expect(uploads.last['lng'], next.longitude);
      expect(uploads.last['gps_at'], next.timestamp.toUtc().toIso8601String());
      b.tracking = false;
      b.dispose();
    },
  );

  test(
    'activation reuses accurate warm position and does not wait for data refresh',
    () async {
      final b = backend();
      b.acceptCaptainFix(gps.current);
      await Future.wait([b.startTracking(), b.startTracking()]);
      expect(b.tracking, true);
      expect(gps.queries, 0);
      expect(uploads.where((p) => p['online'] == true).length, 1);
      final moved = fix(
        33.341,
        44.401,
        at: DateTime.now().add(const Duration(milliseconds: 1)),
      );
      gps.updates.add(moved);
      await Future<void>.delayed(Duration.zero);
      expect(b.position, moved);
      await b.stopTracking();
      expect(uploads.last['online'], false);
      b.dispose();
    },
  );

  test(
    'stale position is never advertised as a fresh captain location',
    () async {
      final b = backend()..tracking = true;
      b.position = fix(
        33.34,
        44.4,
        at: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      await b.presence(true);
      expect(uploads, isEmpty);
      b.tracking = false;
      b.dispose();
    },
  );
  test('switching to another app keeps live GPS and upload active', () async {
    final b = backend();
    b.acceptCaptainFix(gps.current);
    await b.startTracking();
    b.setForeground(false);
    b.lastPresence = DateTime(2000);
    entered = Completer<void>();
    final received = entered!;
    final moved = fix(
      33.342,
      44.402,
      at: DateTime.now().add(const Duration(milliseconds: 1)),
    );
    gps.updates.add(moved);
    await received.future.timeout(const Duration(seconds: 2));
    expect(b.tracking, true);
    expect(b.position, moved);
    expect(uploads.last['lat'], moved.latitude);
    expect(uploads.last['online'], true);
    await b.stopTracking();
    b.dispose();
  });
  test('temporary GPS error does not turn off receiving orders', () async {
    final b = backend();
    b.acceptCaptainFix(gps.current);
    await b.startTracking();
    gps.updates.addError(StateError('temporary location failure'));
    await Future<void>.delayed(Duration.zero);
    expect(b.tracking, true);
    expect(uploads.where((x) => x['online'] == false), isEmpty);
    await b.stopTracking();
    b.dispose();
  });
}
