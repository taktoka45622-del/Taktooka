import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taktooka/pages/lines_page.dart';
import 'package:taktooka/services/backend.dart';

class LinePreviewBackend extends Backend {
  @override
  bool get loggedIn => true;
}

void main() {
  testWidgets('new captain sees a lock, renewal reveals line details', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    late final LinePreviewBackend b;
    await Supabase.initialize(
      url: 'https://example.test',
      anonKey: 'test',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode([
            {
              'id': 'line-one',
              'kind': 'school',
              'status': 'pending',
              'customer_id': 'customer',
              'captain_id': 'unassigned',
              'locked': !b.subscribed,
              'passenger_name': 'راكب الاختبار',
              'pickup_name': 'بيت الاختبار',
              'destination_name': 'مدرسة الاختبار',
              'service_days': 30,
              'start_date': '2026-10-14',
              'end_date': '2026-11-25',
              'departure': '07:00',
              'arrival': '08:00',
              'total_price': 35000,
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
    b = LinePreviewBackend()..profile = {'captain': true};
    await tester.pumpWidget(MaterialApp(home: LinesPage(b: b)));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock), findsOneWidget);
    expect(find.textContaining('راكب الاختبار'), findsNothing);
    expect(find.textContaining('بيت الاختبار'), findsNothing);
    await tester.tap(find.byIcon(Icons.lock));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    expect(find.text('الخط مقفل'), findsOneWidget);
    await tester.tap(find.text('إغلاق'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    b.profile!['expires_at'] = DateTime.now()
        .add(const Duration(days: 7))
        .toIso8601String();
    b.notifyListeners();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock), findsNothing);
    expect(find.textContaining('راكب الاختبار'), findsOneWidget);
    expect(find.textContaining('بيت الاختبار'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await Supabase.instance.dispose();
    b.dispose();
  });
}
