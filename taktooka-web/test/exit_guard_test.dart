import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taktooka/core/app_theme.dart';
import 'package:taktooka/widgets/double_back_exit.dart';

void main() {
  testWidgets('Android root exits only on the second back press', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: const DoubleBackExit(child: Scaffold(body: Text('الرئيسية'))),
        ),
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(calls.where((m) => m == 'SystemNavigator.pop'), isEmpty);
      expect(find.text('اضغط رجوع مرة ثانية للخروج'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(calls.where((m) => m == 'SystemNavigator.pop').length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
