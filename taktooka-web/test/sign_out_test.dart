import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:taktooka/services/backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var stalledServer = false;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      anonKey: 'test',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/logout') && stalledServer) {
          return Completer<http.Response>().future;
        }
        return http.Response('{}', 200);
      }),
    );
  });
  setUp(() async {
    stalledServer = false;
    final expiry =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    String part(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token =
        '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'exp': expiry, 'sub': 'logout-test'})}.test';
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode({
        'access_token': token,
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': expiry,
        'user': {
          'id': 'logout-test',
          'aud': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
  });
  test('cleanup failure does not prevent local sign out', () async {
    final backend = Backend();
    addTearDown(backend.dispose);
    backend.profile = {'captain': false, 'name': 'test'};
    backend.beforeSignOut = () async => throw StateError('plugin failed');
    await backend.signOut();
    expect(backend.loggedIn, isFalse);
    expect(backend.profile, isNull);
    expect(backend.tracking, isFalse);
  });
  test(
    'stalled cleanup is bounded and duplicate taps share the operation',
    () async {
      final backend = Backend();
      addTearDown(backend.dispose);
      var calls = 0;
      backend.beforeSignOut = () {
        calls++;
        return Completer<void>().future;
      };
      final first = backend.signOut();
      final second = backend.signOut();
      expect(identical(first, second), isTrue);
      await first.timeout(const Duration(seconds: 4));
      expect(calls, 1);
      expect(backend.loggedIn, isFalse);
    },
  );
  test(
    'offline server cannot leave logout waiting after local session removal',
    () async {
      final backend = Backend();
      addTearDown(backend.dispose);
      stalledServer = true;
      await backend.signOut().timeout(const Duration(seconds: 5));
      expect(backend.loggedIn, isFalse);
      expect(backend.profile, isNull);
    },
  );
}
