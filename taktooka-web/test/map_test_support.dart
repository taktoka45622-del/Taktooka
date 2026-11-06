import 'package:flutter/widgets.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> mockMapCacheDirectories() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final directory = await Directory.systemTemp.createTemp('taktooka-map-test-');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => directory.path,
      );
}

void mapLayoutTestWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    await http.runWithClient(
      () async {
        try {
          await callback(tester);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(seconds: 30));
        }
      },
      () => MockClient((request) async {
        if (request.url.path.contains('/tiles/')) {
          return http.Response.bytes(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQABpfZFQAAAAABJRU5ErkJggg==',
            ),
            200,
            request: request,
            headers: {'content-type': 'image/png', 'cache-control': 'no-store'},
          );
        }
        return http.Response('{}', 503, request: request);
      }),
    );
  });
}
