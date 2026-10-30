import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taktooka/pages/welcome_page.dart';

void main() {
  for (final size in const [
    Size(320, 568), Size(360, 640), Size(390, 844),
    Size(430, 932), Size(768, 1024), Size(844, 390), Size(640, 240),
  ]) {
    testWidgets('onboarding fits $size with full-screen artwork and safe controls', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: WelcomePage()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final image = find.byType(Image).first;
      expect(tester.widget<Image>(image).fit, BoxFit.cover);
      final imageRect = tester.getRect(image);
      expect(imageRect.size, size);
      final buttonRect = tester.getRect(find.byType(FilledButton));
      expect(buttonRect.bottom, lessThanOrEqualTo(size.height));
      expect(buttonRect.left, greaterThanOrEqualTo(0));
      expect(buttonRect.right, lessThanOrEqualTo(size.width));
      await tester.drag(find.byType(PageView), const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
