import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taktooka/services/map_navigation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MapNavigation.channel, null);
  });
  test('Android chooser retains every compatible installed app', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MapNavigation.channel, (call) async {
          if (call.method == 'apps')
            return [
              {'id': 'com.google.android.apps.maps', 'name': 'Maps'},
              {'id': 'com.example.localnavigation', 'name': 'خرائط محلية'},
              {'id': 'com.example.delivery', 'name': 'توصيل'},
              {'id': '', 'name': 'invalid'},
            ];
          return null;
        });
    final apps = await MapNavigation.installedApps();
    expect(
      apps.map((app) => app['id']),
      containsAll([
        'com.google.android.apps.maps',
        'com.example.localnavigation',
        'com.example.delivery',
      ]),
    );
    expect(apps.any((app) => app['id'] == ''), false);
  });
}
