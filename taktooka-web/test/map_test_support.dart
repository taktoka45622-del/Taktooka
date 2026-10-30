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
