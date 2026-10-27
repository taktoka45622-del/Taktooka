import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/notifications.dart';

class FakeAudio extends Fake implements AudioPlayer {
  int plays = 0;
  bool playing = false;
  @override
  Future<void> stop() async {
    playing = false;
  }

  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {}
  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    plays++;
    playing = true;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      anonKey: 'test',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
  });
  test(
    'iOS cancels the remote offer by offer ID even without a local notice',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(appleNotices, (call) async {
            calls.add(call);
            return null;
          });
      final b = Backend();
      final center = NotificationCenter(b, (_) {}, audioPlayer: FakeAudio());
      try {
        await center.cancelDeviceOffer('old-offer');
        await center.cancelDeviceOffer('new-offer');
        expect(calls.map((c) => c.method), ['cancelOffer', 'cancelOffer']);
        expect(calls.map((c) => c.arguments), ['old-offer', 'new-offer']);
      } finally {
        center.dispose();
        b.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(appleNotices, null);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
  testWidgets(
    'New offers ring again; acceptance and removal stop only the matching offer',
    (tester) async {
      final b = Backend()
        ..tracking = true
        ..profile = {'captain': true, 'expires_at': '2099-01-01'};
      final audio = FakeAudio();
      final center = NotificationCenter(b, (_) {}, audioPlayer: audio);
      center.startRing('first', null);
      await tester.pump();
      expect(audio.playing, true);
      await tester.pump(const Duration(seconds: 30));
      expect(audio.playing, false);
      center.startRing('first', null);
      await tester.pump();
      expect(audio.plays, 1);
      center.startRing('second', null);
      await tester.pump();
      expect(audio.plays, 2);
      // Delayed cancellation of an old offer must not silence the new offer.
      await center.silenceOffer('first');
      expect(audio.playing, true);
      expect(center.ringing, 'second');
      b.activeRide = {'id': 'accepted'};
      center.syncOffers();
      await tester.pump();
      expect(audio.playing, false);
      b.activeRide = null;
      center.startRing('third', null);
      await tester.pump();
      expect(audio.plays, 3);
      center
          .syncOffers(); // The offer has been cancelled/removed from the feed.
      await tester.pump();
      expect(audio.playing, false);
      center.dispose();
      await tester.pump();
    },
  );
  final now = DateTime.utc(2026, 10, 10);
  test('Offer countdown allows thirty seconds and never revives expiry', () {
    final b = Backend();
    final now = b.serverNow;
    expect(
      b.offerSeconds({
        'offer_expires_at': now
            .add(const Duration(seconds: 30))
            .toIso8601String(),
      }),
      inInclusiveRange(29, 30),
    );
    expect(
      b.offerSeconds({
        'offer_expires_at': now
            .subtract(const Duration(seconds: 1))
            .toIso8601String(),
      }),
      0,
    );
    b.dispose();
  });
  test('Each offer rings for until expiry, at most thirty seconds', () {
    expect(
      offerRingDuration(now.add(const Duration(seconds: 30)), now: now),
      const Duration(seconds: 30),
    );
    expect(
      offerRingDuration(now.add(const Duration(seconds: 3)), now: now),
      const Duration(seconds: 3),
    );
    expect(
      offerRingDuration(now.subtract(const Duration(seconds: 1)), now: now),
      Duration.zero,
    );
    expect(offerRingDuration(null, now: now), const Duration(seconds: 30));
  });
}
