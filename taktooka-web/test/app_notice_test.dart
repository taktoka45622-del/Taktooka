import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taktooka/widgets/app_notice.dart';

void main() {
  test(
    'notices classify errors, successful actions, and required user actions',
    () {
      expect(noticeKind('تم حفظ العنوان بنجاح'), AppNoticeKind.success);
      expect(
        noticeKind('تم تفعيل الكود للرحلة القادمة'),
        AppNoticeKind.success,
      );
      expect(noticeKind('تعذّر الاتصال، حاول مرة ثانية'), AppNoticeKind.error);
      expect(noticeKind('كلمة المرور غير صحيحة'), AppNoticeKind.error);
      expect(noticeKind('تم إلغاء الرحلة'), AppNoticeKind.warning);
      expect(noticeKind('حدد نقطة الوصول'), AppNoticeKind.warning);
    },
  );
  for (final rtl in [true, false]) {
    testWidgets(
      'banner reserves its own space, keeps buttons usable and closes after five seconds (rtl=$rtl)',
      (tester) async {
        late BuildContext context;
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: Scaffold(
                appBar: AppBar(title: const Text('تكتوكة')),
                body: Builder(
                  builder: (c) {
                    context = c;
                    return Column(
                      children: [
                        ElevatedButton(
                          onPressed: () => taps++,
                          child: const Text('تأكيد'),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () => taps++,
                          child: const Text('طلب رحلة'),
                        ),
                      ],
                    );
                  },
                ),
                bottomNavigationBar: const SizedBox(
                  height: 64,
                  child: Text('الرئيسية'),
                ),
              ),
            ),
          ),
        );
        showAppNotice(context, 'تم حفظ العنوان بنجاح');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final banner = tester.getRect(find.byType(AppNotice));
        final topButton = tester.getRect(
          find.widgetWithText(ElevatedButton, 'تأكيد'),
        );
        final bottomButton = tester.getRect(
          find.widgetWithText(ElevatedButton, 'طلب رحلة'),
        );
        expect(banner.overlaps(topButton), false);
        expect(banner.overlaps(bottomButton), false);
        expect(find.byIcon(Icons.close_rounded), findsOneWidget);
        final close = tester.getRect(find.byIcon(Icons.close_rounded));
        expect(close.center.dx, greaterThan(banner.center.dx));
        await tester.tap(find.widgetWithText(ElevatedButton, 'تأكيد'));
        expect(taps, 1);
        await tester.pump(const Duration(seconds: 4));
        expect(find.byType(AppNotice), findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(AppNotice), findsNothing);
      },
    );
  }
  testWidgets(
    'single right close button dismisses immediately and new notices replace old ones',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                context = c;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      showAppNotice(context, 'حدد نقطة الوصول');
      await tester.pumpAndSettle();
      showAppNotice(context, 'تم الحفظ');
      await tester.pumpAndSettle();
      expect(find.text('حدد نقطة الوصول'), findsNothing);
      expect(find.text('تم الحفظ'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(AppNotice), findsNothing);
    },
  );
}
