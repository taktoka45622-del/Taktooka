import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:taktooka/core/app_theme.dart';
import 'package:taktooka/models/prize_wheel.dart';
import 'package:taktooka/pages/offers_page.dart';
import 'package:taktooka/pages/prize_wheel_page.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/widgets/prize_wheel_entry.dart';

class WheelBackend extends Backend {
  int spins = 0;
  bool failOnce = false, paused = false;
  String? prize = 'cash';
  DateTime? next;
  final ids = <String>[];
  @override
  bool get loggedIn => true;
  WheelBackend({bool captain = true}) {
    profile = {'captain': captain};
  }
  @override
  Future<void> refresh({
    bool lightweight = false,
    bool queueIfBusy = true,
  }) async {}
  @override
  Future<dynamic> wheel(String action, [Json data = const {}]) async {
    if (action == 'snapshot')
      return {
        'enabled': !paused,
        'history': <Json>[],
        'server_now': DateTime.now().toUtc().toIso8601String(),
        'next_spin_at': next?.toIso8601String(),
      };
    ids.add(data['id'] as String);
    if (failOnce) {
      failOnce = false;
      throw Exception('Network timeout');
    }
    spins++;
    next = DateTime.now().toUtc().add(const Duration(days: 3));
    return {
      'id': data['id'],
      'prize_key': prize,
      'prize_title': prize == null ? 'حظ أوفر' : 'جائزة 35,000 د.ع',
      'status': prize == null ? 'no_prize' : 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'server_now': DateTime.now().toUtc().toIso8601String(),
      'next_spin_at': next!.toIso8601String(),
    };
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
    final fonts = FontLoader('Cairo')
      ..addFont(rootBundle.load('assets/fonts/Cairo.ttf'));
    await fonts.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'each result stops with its own segment underneath the fixed pointer',
    () {
      var angle = 0.0;
      for (final i in [0, 2, 4, 6, 1, 3, 5, 7, 6]) {
        angle = wheelTargetAngle(angle, i);
        final underPointer =
            ((2 * math.pi - angle % (2 * math.pi)) % (2 * math.pi)) /
            (math.pi / 4);
        expect(underPointer.floor(), i);
      }
    },
  );
  Future<void> load(WidgetTester tester, WheelBackend b) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: PrizeWheelPage(backend: b),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }

  testWidgets(
    'cash win is saved, blocks duplicate taps, and starts the 72-hour countdown',
    (tester) async {
      final b = WheelBackend();
      await load(tester, b);
      await tester.tap(find.text('لفّ العجلة'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      expect(b.spins, 1);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -350));
      await tester.pump();
      expect(find.text('مبروك، ربحت جائزة!'), findsOneWidget);
      expect(find.text('جائزة 35,000 د.ع'), findsWidgets);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await dispose(tester);
    },
  );
  testWidgets(
    'failed request retries with the same durable id, then displays no-prize result',
    (tester) async {
      final b = WheelBackend()
        ..prize = null
        ..failOnce = true;
      await load(tester, b);
      await tester.tap(find.text('لفّ العجلة'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.text('استرجاع نتيجة اللفة'), findsOneWidget);
      await tester.tap(find.text('استرجاع نتيجة اللفة'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(b.ids.length, 2);
      expect(b.ids[0], b.ids[1]);
      expect(b.spins, 1);
      await tester.drag(find.byType(ListView), const Offset(0, -350));
      await tester.pump();
      expect(find.text('حظ أوفر'), findsWidgets);
      expect(tester.takeException(), isNull);
      await dispose(tester);
    },
  );
  testWidgets(
    'cooldown survives opening a fresh page and disabled wheel cannot spin',
    (tester) async {
      for (final b in [
        WheelBackend()..next = DateTime.now().add(const Duration(days: 2)),
        WheelBackend()..paused = true,
      ]) {
        await load(tester, b);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        expect(b.spins, 0);
        await dispose(tester);
      }
    },
  );
  testWidgets('wheel entry is hidden for riders and visible to captains', (
    tester,
  ) async {
    for (final captain in [false, true]) {
      final b = WheelBackend(captain: captain);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OffersPage(b: b, run: (fn) => fn(), login: () {}),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byType(PrizeWheelEntry),
        captain ? findsOneWidget : findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    }
  });
}
