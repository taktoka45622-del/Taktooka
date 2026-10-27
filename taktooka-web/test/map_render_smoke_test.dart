import 'map_test_support.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taktooka/core/app_preferences.dart';
import 'package:taktooka/widgets/booking_map_layer.dart';
import 'package:taktooka/widgets/street_map_layer.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vector;

class _NetworkOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = (uri) => HttpClient.findProxyFromEnvironment(
          uri,
          environment: Platform.environment,
        );
}

void main() {
  if (const bool.fromEnvironment('LIVE_MAP_TEST')) {
    LiveTestWidgetsFlutterBinding().framePolicy =
        LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  }
  testWidgets(
    'renders live map in every language and both themes, then pans',
    (tester) async {
      await tester.runAsync(mockMapCacheDirectories);
      SharedPreferences.setMockInitialValues({});
      final previous = HttpOverrides.current;
      HttpOverrides.global = _NetworkOverrides();
      addTearDown(() => HttpOverrides.global = previous);
      tester.view.physicalSize = const Size(390, 750);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final font = FontLoader('Cairo')
          ..addFont(rootBundle.load('assets/fonts/Cairo.ttf'));
        await font.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
      final capture = GlobalKey();
      final controller = MapController();
      addTearDown(controller.dispose);
      for (final language in ['ar', 'en', 'ku']) {
        for (final dark in [false, true]) {
          print('Map rendering: $language / ${dark ? "dark" : "light"}');
          appPreferences.language = language;
          appPreferences.themeMode = dark ? ThemeMode.dark : ThemeMode.light;
          await tester.runAsync(
            () => StreetMapLayer.loadStyle(dark: dark, language: language),
          );
          print('Style loaded');
          await tester.pumpWidget(
            PreferencesScope(
              child: MaterialApp(
                theme: dark ? ThemeData.dark() : ThemeData.light(),
                home: Scaffold(
                  body: RepaintBoundary(
                    key: capture,
                    child: FlutterMap(
                      mapController: controller,
                      options: const MapOptions(
                        initialCenter: LatLng(33.3805, 44.380297),
                        initialZoom: 17,
                        maxZoom: 20,
                      ),
                      children: const [BookingMapLayer()],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          for (var frame = 0; frame < 10; frame++) {
            await tester.pump(const Duration(milliseconds: 500));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 1)),
            );
          }
          await tester.pump();
          expect(find.byType(vector.VectorTileLayer), findsOneWidget);
          expect(tester.takeException(), isNull);
          final output = Platform.environment['MAP_TEST_OUTPUT'];
          if (output != null) {
            final boundary =
                capture.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final pixels = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              final colors = <int>{};
              for (
                var offset = 0;
                offset < pixels!.lengthInBytes;
                offset += 64
              ) {
                colors.add(pixels.getUint32(offset));
              }
              expect(
                colors.length,
                greaterThan(8),
                reason: 'map tiles must actually paint',
              );
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '$output/map-$language-${dark ? 'dark' : 'light'}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
      }
      final before = controller.camera.center;
      await tester.drag(find.byType(FlutterMap), const Offset(100, 60));
      await tester.pump();
      expect(controller.camera.center, isNot(before));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !const bool.fromEnvironment('LIVE_MAP_TEST'),
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
