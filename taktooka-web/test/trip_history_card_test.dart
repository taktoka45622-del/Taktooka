import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taktooka/core/app_theme.dart';
import 'package:taktooka/widgets/trip_history_card.dart';

void main() {
  testWidgets(
    'history fits small phones and shows route, Baghdad date and payment',
    (tester) async {
      for (final width in [320.0, 360.0, 390.0]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 780);
        for (final payment in ['wallet', 'cash']) {
          await tester.pumpWidget(
            MaterialApp(
              theme: appTheme(),
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  body: ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      TripHistoryCard(
                        ride: {
                          'id': '9ec2d2c4-test',
                          'status': 'completed',
                          'created_at': '2026-10-11T01:13:00Z',
                          'pickup_name': 'القاهرة بالقرب من جامع النداء',
                          'destination_name':
                              'الحسينية شارع طويل لاختبار عرض النص',
                          'fare': 1500,
                          'customer_due': 1000,
                          'payment_method': payment,
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.text('رحلة \u2066#9EC2D2C4\u2069'), findsOneWidget);
          expect(find.text('11 أكتوبر 2026 • 4:13 صباحًا'), findsOneWidget);
          expect(
            find.text(payment == 'wallet' ? 'دفع من المحفظة' : 'دفع كاش'),
            findsOneWidget,
          );
          expect(find.text('تفاصيل الرحلة'), findsNothing);
          expect(tester.takeException(), isNull);
        }
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
