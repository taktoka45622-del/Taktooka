import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taktooka/widgets/app_notice.dart';

void main() {
  late BuildContext pageContext;
  const bodyKey = Key('page-body');
  Widget app() => MaterialApp(
    home: Builder(
      builder: (context) {
        pageContext = context;
        return Scaffold(
          appBar: AppBar(title: const Text('تكتوكة')),
          body: const SizedBox.expand(key: bodyKey, child: Text('حسابي')),
        );
      },
    ),
  );
  testWidgets(
    'notice does not move the page and disappears after five seconds',
    (tester) async {
      await tester.pumpWidget(app());
      final before = tester.getTopLeft(find.byKey(bodyKey));
      showAppNotice(pageContext, 'إشعار تجريبي');
      await tester.pump();
      expect(find.byType(AppNotice), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(bodyKey)), before);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.byType(AppNotice), findsNothing);
      expect(tester.getTopLeft(find.byKey(bodyKey)), before);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('a new notice replaces the previous one and owns its timeout', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    showAppNotice(pageContext, 'الأول');
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    showAppNotice(pageContext, 'الثاني');
    await tester.pump();
    expect(find.text('الأول'), findsNothing);
    expect(find.text('الثاني'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('الثاني'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.byType(AppNotice), findsNothing);
  });
  testWidgets(
    'close button removes notice immediately without reserving space',
    (tester) async {
      await tester.pumpWidget(app());
      final before = tester.getTopLeft(find.byKey(bodyKey));
      showAppNotice(pageContext, 'إغلاق');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(find.byType(AppNotice), findsNothing);
      expect(tester.getTopLeft(find.byKey(bodyKey)), before);
    },
  );
  testWidgets('swipe dismisses notice without leaving a gap', (tester) async {
    await tester.pumpWidget(app());
    final before = tester.getTopLeft(find.byKey(bodyKey));
    showAppNotice(pageContext, 'اسحب للأعلى');
    await tester.pump();
    await tester.drag(find.byType(AppNotice), const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(find.byType(AppNotice), findsNothing);
    expect(tester.getTopLeft(find.byKey(bodyKey)), before);
  });
  testWidgets('disposing the overlay cancels its notice timeout', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    showAppNotice(pageContext, 'مؤقت');
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });
  testWidgets('rapid consecutive notices leave only the newest card', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    showAppNotice(pageContext, 'واحد');
    showAppNotice(pageContext, 'اثنين');
    showAppNotice(pageContext, 'ثلاثة');
    await tester.pump();
    expect(find.byType(AppNotice), findsOneWidget);
    expect(find.text('ثلاثة'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.byType(AppNotice), findsNothing);
  });
  testWidgets('navigation does not leave space when the notice expires', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    showAppNotice(pageContext, 'تنبيه قبل الانتقال');
    await tester.pump();
    Navigator.of(pageContext).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(
          appBar: null,
          body: SizedBox.expand(
            key: Key('next-body'),
            child: Text('الصفحة التالية'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.byKey(const Key('next-body')));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.byType(AppNotice), findsNothing);
    expect(tester.getTopLeft(find.byKey(const Key('next-body'))), before);
  });

  testWidgets('disposing before the notice first renders is safe', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    showAppNotice(pageContext, 'إشعار قبل الإغلاق');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });
  testWidgets('page controls remain usable while the notice is visible', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () {
                    taps++;
                  },
                  child: const Text('متابعة'),
                ),
              ),
            );
          },
        ),
      ),
    );
    showAppNotice(pageContext, 'إشعار أعلى الصفحة');
    await tester.pump();
    await tester.tap(find.text('متابعة'));
    await tester.pump();
    expect(taps, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
