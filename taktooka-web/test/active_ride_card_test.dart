import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taktooka/core/app_theme.dart';
import 'package:taktooka/widgets/active_ride_card.dart';

void main() {
  testWidgets(
    'Rider and captain cards fit phones; captain starts directly without a code',
    (tester) async {
      for (final width in [360.0, 390.0]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 780);
        for (final captain in [false, true]) {
          String? action;
          await tester.pumpWidget(
            MaterialApp(
              theme: appTheme(),
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(18),
                    child: ActiveRideCard(
                      ride: const {
                        'status': 'arrived',
                        'fare': 1000,
                        'customer_due': 1000,
                        'payment_method': 'wallet',
                      },
                      contact: const {
                        'name': 'كرار',
                        'phone': '+9647736578908',
                        'location_at': '2020-01-01T00:00:00Z',
                      },
                      captain: captain,
                      busy: false,
                      now: DateTime.utc(2026, 10, 10),
                      onStatus: (value) => action = value,
                      onContact: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.text('الرحلة مدفوعة بالمحفظة'), findsOneWidget);
          expect(find.text('الكابتن وصل'), findsOneWidget);
          expect(find.text('كرار'), findsOneWidget);
          expect(find.byType(TextField), findsNothing);
          expect(find.textContaining('رمز'), findsNothing);
          expect(tester.takeException(), isNull);
          if (captain) {
            expect(find.text('ويز للزبون'), findsOneWidget);
            await tester.tap(find.text('بدء الرحلة'));
            expect(action, 'in_progress');
            expect(find.byType(AlertDialog), findsNothing);
          } else {
            expect(find.text('بدء الرحلة'), findsNothing);
            expect(find.textContaining('المتابعة متوقفة'), findsOneWidget);
          }
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
