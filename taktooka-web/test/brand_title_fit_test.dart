import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taktooka/widgets/brand_title.dart';

void main() {
  for (final width in [280.0, 320.0, 360.0, 390.0, 430.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('toolbar fits width $width and text scale $scale', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(appBar: AppBar(
            centerTitle: true,
            toolbarHeight: 72,
            leadingWidth: 90,
            leading: const SizedBox(width: 90),
            title: const BrandTitle(),
            actions: [
              IconButton(onPressed: () {}, icon: const Icon(Icons.notifications)),
              IconButton(onPressed: () {}, icon: const Icon(Icons.headset_mic)),
            ],
          )),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
