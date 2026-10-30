import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taktooka/core/app_theme.dart';
import 'package:taktooka/services/connection_monitor.dart';
import 'package:taktooka/widgets/connection_gate.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Cairo',
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'initial connection check stays in background without a loading screen',
    (tester) async {
      final result = Completer<bool>();
      final monitor = ConnectionMonitor(probe: () => result.future);
      await tester.pumpWidget(
        MaterialApp(
          home: ConnectionGate(
            monitor: monitor,
            child: const Scaffold(body: Text('current page')),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ConnectionScreen), findsNothing);
      expect(find.text('current page'), findsOneWidget);
      result.complete(false);
      await tester.pump();
      await tester.pump();
      expect(find.text('لا يوجد اتصال بالإنترنت'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      monitor.dispose();
    },
  );

  testWidgets('retry hides offline screen and preserves the current form', (
    tester,
  ) async {
    var reachable = true;
    final monitor = ConnectionMonitor(probe: () async => reachable);
    final field = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: ConnectionGate(
          monitor: monitor,
          child: Scaffold(body: TextField(controller: field)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(ConnectionScreen), findsNothing);
    await tester.enterText(find.byType(TextField), 'saved input');
    reachable = false;
    await monitor.check();
    await tester.pump();
    expect(find.text('لا يوجد اتصال بالإنترنت'), findsOneWidget);
    expect(field.text, 'saved input');
    reachable = true;
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(ConnectionScreen), findsNothing);
    expect(field.text, 'saved input');
    reachable = false;
    await monitor.check();
    await tester.pump();
    reachable = true;
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    await tester.pump();
    expect(find.byType(ConnectionScreen), findsNothing);
    expect(field.text, 'saved input');
    await tester.pumpWidget(const SizedBox.shrink());
    monitor.dispose();
    field.dispose();
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(430, 932),
    const Size(844, 390),
    const Size(768, 1024),
  ]) {
    for (final offline in [false, true]) {
      testWidgets(
        'connection screen fits $size offline=$offline at large text',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final capture = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: appTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: child!,
                ),
              ),
              home: RepaintBoundary(
                key: capture,
                child: ConnectionScreen(
                  checking: !offline,
                  offline: offline,
                  retry: () {},
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 200));
          expect(tester.takeException(), isNull);
          final output = Platform.environment['CONNECTION_QA_DIR'];
          if (output != null && size.width == 390) {
            final boundary =
                capture.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '$output/connection-${offline ? "offline" : "loading"}.png',
              ).writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
        },
      );
    }
  }
}
