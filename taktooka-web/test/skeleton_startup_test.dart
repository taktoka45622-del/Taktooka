import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taktooka/widgets/account_startup_gate.dart';
import 'package:taktooka/widgets/skeleton.dart';

void main() {
  testWidgets('account content is never built before identity is resolved', (
    tester,
  ) async {
    var builds = 0;
    Widget app(bool ready, String role) => MaterialApp(
      home: AccountStartupGate(
        ready: ready,
        retry: () {},
        signOut: () {},
        builder: (_) {
          builds++;
          return Scaffold(body: Text(role));
        },
      ),
    );
    for (final role in ['captain', 'restaurant', 'customer']) {
      await tester.pumpWidget(app(false, role));
      expect(find.byType(SkeletonPage), findsOneWidget);
      expect(find.text(role), findsNothing);
      expect(builds, 0);
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pumpWidget(app(true, 'restaurant'));
    expect(find.text('restaurant'), findsOneWidget);
    expect(find.byType(SkeletonPage), findsNothing);
    expect(builds, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed identity can retry without rendering account content', (
    tester,
  ) async {
    var retries = 0, builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountStartupGate(
          ready: false,
          error: 'connection failed',
          retry: () => retries++,
          signOut: () {},
          builder: (_) {
            builds++;
            return const Text('customer');
          },
        ),
      ),
    );
    await tester.tap(find.byType(FilledButton));
    expect(retries, 1);
    expect(builds, 0);
  });

  testWidgets('shimmer animates while visible and stops in hidden tabs', (
    tester,
  ) async {
    Widget app(bool enabled) => MaterialApp(
      home: Scaffold(
        body: TickerMode(enabled: enabled, child: const SkeletonContent()),
      ),
    );
    await tester.pumpWidget(app(true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, true);
    await tester.pumpWidget(app(false));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, false);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 640), const Size(1024, 768)]) {
    for (final dark in [false, true]) {
      testWidgets('skeleton fits $size dark=$dark with reduced motion', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            home: const MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(body: SkeletonPage()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.binding.hasScheduledFrame, false);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
