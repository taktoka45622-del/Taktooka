import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/notifications.dart';
import 'offer_ring_test.dart' show FakeAudio;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      anonKey: 'test',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient(
        (_) async => http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
  });
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({'notice_user': 'captain'});
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'initialize' ? true : null;
        });
    await setupNative();
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });
  Map<String, dynamic> offer(String id) => {
    'kind': 'offer',
    'notification_id': id,
    'recipient_id': 'captain',
    'title': 'old title',
    'body': 'old body',
    'offer_id': 'offer-$id',
    'ride_id': 'ride-$id',
    'screen': 'ride',
    'expires_at': DateTime.now()
        .add(const Duration(seconds: 30))
        .toUtc()
        .toIso8601String(),
  };

  test(
    'background notice rings using existing audio and carries the correct clickable ride',
    () async {
      final n = offer('1');
      await displayNotice(n);
      final args = Map<String, dynamic>.from(
        calls.singleWhere((c) => c.method == 'show').arguments as Map,
      );
      expect(args['title'], 'كابتن، عندك رحلة');
      final android = Map<String, dynamic>.from(
        args['platformSpecifics'] as Map,
      );
      expect(android['channelId'], offerChannelId);
      expect(android['playSound'], true);
      expect(android['sound'], 'captain_request');
      expect(android['timeoutAfter'], inInclusiveRange(1, 30000));
      final payload = Map<String, dynamic>.from(
        jsonDecode(args['payload'] as String) as Map,
      );
      final b = Backend();
      Map<String, dynamic>? opened;
      final center = NotificationCenter(
        b,
        (value) => opened = value,
        audioPlayer: FakeAudio(),
      )..user = 'captain';
      center.tap(payload);
      expect(opened?['ride_id'], 'ride-1');
      expect(opened?['offer_id'], 'offer-1');
      center.dispose();
      b.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );
  test('sound channel exists before any silent foreground offer', () async {
    final channelArgs = Map<String, dynamic>.from(
      calls
              .singleWhere((c) => c.method == 'createNotificationChannel')
              .arguments
          as Map,
    );
    final configured = channelArgs;
    expect(configured['id'], offerChannelId);
    expect(configured['playSound'], true);
    expect(configured['sound'], 'captain_request');
    expect(configured['enableVibration'], true);
    await displayNotice(offer('foreground'), ring: false);
    await displayNotice(offer('background'));
    final shown = calls.where((c) => c.method == 'show').toList();
    final first = Map.from(
      (shown[0].arguments as Map)['platformSpecifics'] as Map,
    );
    final next = Map.from(
      (shown[1].arguments as Map)['platformSpecifics'] as Map,
    );
    expect(first['silent'], true);
    expect(next['silent'], false);
    expect(next['playSound'], true);
    expect(next['enableVibration'], true);
    expect(next['vibrationPattern'], [0, 600, 300, 600, 300, 900]);
    expect(next['additionalFlags'], contains(4));
  });
  test('expired or different-user offers never ring', () async {
    await displayNotice({
      ...offer('expired'),
      'expires_at': '2020-01-01T00:00:00Z',
    });
    await displayNotice({...offer('other'), 'recipient_id': 'other'});
    expect(calls.where((c) => c.method == 'show'), isEmpty);
  });
  test(
    'duplicate offers do not ring twice and expiry cancels the matching notice',
    () async {
      final n = offer('2');
      await displayNotice(n);
      await displayNotice(n);
      expect(calls.where((c) => c.method == 'show').length, 1);
      await displayNotice({...n, 'kind': 'offer_end'});
      expect(calls.where((c) => c.method == 'cancel').length, 1);
    },
  );
}
