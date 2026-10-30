import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taktooka/widgets/adaptive_viewport.dart';

void main() {
  for (final size in <Size>[
    const Size(320, 568),
    const Size(390, 844),
    const Size(430, 932),
    const Size(768, 1024),
    const Size(1024, 768),
    const Size(844, 390),
  ]) {
    testWidgets('viewport respects safe insets at $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Size? measured;
      Size? reported;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(padding: const EdgeInsets.fromLTRB(0, 44, 0, 34)),
            child: AdaptiveViewport(child: child!),
          ),
          home: LayoutBuilder(
            builder: (context, constraints) {
              measured = constraints.biggest;
              reported = MediaQuery.sizeOf(context);
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      );
      expect(measured!.width, size.width > 600 ? 600 : size.width);
      expect(measured!.height, size.height - 78);
      expect(reported, measured);
      expect(tester.takeException(), isNull);
    });
  }
}
