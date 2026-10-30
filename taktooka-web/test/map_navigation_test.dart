import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taktooka/services/map_navigation.dart';
import 'package:taktooka/widgets/map_navigation_setting.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MapNavigation.channel, (call) async {
          calls.add(call);
          if (call.method == 'apps')
            return [
              {'id': 'com.waze', 'name': 'Waze'},
              {'id': 'com.google.android.apps.maps', 'name': 'Google Maps'},
            ];
          return true;
        });
  });
  Future<void> screen(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () => MapNavigation.open(context, 33.5, 44.4),
                child: const Text('open'),
              ),
              TextButton(
                onPressed: () =>
                    MapNavigation.open(context, 33.6, 44.5, choose: true),
                child: const Text('change'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  testWidgets('taxi and delivery handlers are excluded, including saved defaults', (tester) async {
    SharedPreferences.setMockInitialValues({
      MapNavigation.preferenceKey: 'taxi.handler',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MapNavigation.channel, (call) async {
          calls.add(call);
          if (call.method == 'apps') return [
            {'id': 'taxi.handler', 'name': 'Baly'},
            {'id': 'delivery.handler', 'name': 'Toters'},
            {'id': 'com.waze', 'name': 'Waze'},
          ];
          return true;
        });
    await screen(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Baly'), findsNothing);
    expect(find.text('Toters'), findsNothing);
    expect(find.text('Waze'), findsOneWidget);
    expect(calls.where((c) => c.method == 'open'), isEmpty);
    expect((await SharedPreferences.getInstance()).getString(MapNavigation.preferenceKey), isNull);
  });
  testWidgets('once opens selected destination without remembering', (
    tester,
  ) async {
    await screen(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google Maps'));
    await tester.pump();
    await tester.tap(find.text('لمرة واحدة'));
    await tester.pumpAndSettle();
    expect(calls.last.arguments, {
      'id': 'com.google.android.apps.maps',
      'lat': 33.5,
      'lng': 44.4,
    });
    expect(
      (await SharedPreferences.getInstance()).getString(
        MapNavigation.preferenceKey,
      ),
      isNull,
    );
  });
  testWidgets('always persists, bypasses chooser and can be changed', (
    tester,
  ) async {
    await screen(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('دائماً'));
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getString(
        MapNavigation.preferenceKey,
      ),
      'com.waze',
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('فتح الملاحة باستخدام'), findsNothing);
    await tester.tap(find.text('change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google Maps'));
    await tester.pump();
    await tester.tap(find.text('دائماً'));
    await tester.pumpAndSettle();
    expect(calls.last.arguments['lat'], 33.6);
    expect(
      (await SharedPreferences.getInstance()).getString(
        MapNavigation.preferenceKey,
      ),
      'com.google.android.apps.maps',
    );
  });
  testWidgets('cancel never opens navigation', (tester) async {
    await screen(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'open'), isEmpty);
  });
  testWidgets('removed remembered app returns to chooser', (tester) async {
    SharedPreferences.setMockInitialValues({
      MapNavigation.preferenceKey: 'removed.app',
    });
    await screen(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('فتح الملاحة باستخدام'), findsOneWidget);
    expect(calls.where((c) => c.method == 'open'), isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getString(
        MapNavigation.preferenceKey,
      ),
      isNull,
    );
    await tester.tap(find.text('لمرة واحدة'));
    await tester.pumpAndSettle();
  });
  testWidgets('failed launch does not persist always choice', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MapNavigation.channel, (call) async {
          if (call.method == 'apps')
            return [
              {'id': 'com.waze', 'name': 'Waze'},
            ];
          return false;
        });
    await screen(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('دائماً'));
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getString(
        MapNavigation.preferenceKey,
      ),
      isNull,
    );
    expect(
      find.text('تعذّر فتح تطبيق الخرائط؛ حاول اختيار تطبيق آخر'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 6));
  });
  testWidgets('settings saves app without launching and allows changing it', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MapNavigationSetting())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تحديد تطبيق الخرائط')); await tester.pumpAndSettle();
    await tester.tap(find.text('Google Maps')); await tester.pumpAndSettle();
    expect(find.text('Google Maps'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString(MapNavigation.preferenceKey), 'com.google.android.apps.maps');
    expect(calls.where((c) => c.method == 'open'), isEmpty);
    await tester.tap(find.text('تحديد تطبيق الخرائط')); await tester.pumpAndSettle();
    await tester.tap(find.text('Waze')); await tester.pumpAndSettle();
    expect(find.text('Waze'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString(MapNavigation.preferenceKey), 'com.waze');
    expect(calls.where((c) => c.method == 'open'), isEmpty);
  });

}
