import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taktooka/services/backend.dart';

class OfflineChannel implements RealtimeChannel {
  @override
  dynamic noSuchMethod(Invocation invocation) => this;
}

class IdentityClient extends SupabaseClient {
  IdentityClient(http.Client client)
    : super(
        'https://example.test',
        'fixture-only',
        httpClient: client,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
  @override
  RealtimeChannel channel(
    String name, {
    RealtimeChannelConfig opts = const RealtimeChannelConfig(),
  }) => OfflineChannel();
  @override
  Future<String> removeChannel(RealtimeChannel channel) async => 'ok';
}

class IdentityBackend extends Backend {
  IdentityBackend(SupabaseClient client) : super(client: client);
  @override
  Future<void> warmRiderLocation() async {}
}

Future<void> session(SupabaseClient client) async {
  final expires =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final token =
      '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'exp': expires, 'sub': 'identity-fixture'})}.fixture';
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': token,
      'refresh_token': 'fixture-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at': expires,
      'user': {
        'id': 'identity-fixture',
        'aud': 'authenticated',
        'app_metadata': {},
        'user_metadata': {},
        'created_at': '2026-01-01T00:00:00Z',
      },
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final role in ['captain', 'restaurant', 'customer']) {
    test('$role stays unresolved until both identities finish', () async {
      final started = Completer<void>(), identity = Completer<http.Response>();
      http.Request? identityRequest;
      final client = IdentityClient(
        MockClient((request) async {
          final op = jsonDecode(request.body)['p_action'];
          Object value = {};
          if (request.url.path.endsWith('tkt_commerce')) {
            identityRequest = request;
            started.complete();
            return identity.future;
          }
          if (request.url.path.endsWith('tkt_action'))
            value = op == 'me'
                ? {'captain': role == 'captain', 'name': 'fixture'}
                : [];
          return http.Response(
            jsonEncode(value),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      await session(client);
      final b = IdentityBackend(client);
      expect(await b.action('me'), isA<Map>());
      expect(await b.action('snapshot'), isA<List>());
      expect(await b.dispatch('snapshot'), isA<Map>());
      final pending = b.refresh();
      await started.future;
      expect(b.accountReady, false);
      identity.complete(
        http.Response(
          jsonEncode(
            role == 'restaurant'
                ? {
                    'restaurant': {'id': 'fixture-restaurant'},
                  }
                : {},
          ),
          200,
          headers: {'content-type': 'application/json'},
          request: identityRequest,
        ),
      );
      await pending;
      expect(b.accountReady, true, reason: b.error);
      expect(b.captain, role == 'captain');
      expect(b.restaurantOwner, role == 'restaurant');
      b.dispose();
      await client.dispose();
    });
  }

  test(
    'failed commerce identity cannot become customer on a lightweight retry',
    () async {
      var calls = 0;
      final client = IdentityClient(
        MockClient((request) async {
          final op = jsonDecode(request.body)['p_action'];
          if (request.url.path.endsWith('tkt_commerce')) {
            calls++;
            if (calls == 1)
              return http.Response(
                '{"code":"OFFLINE","message":"fixture offline"}',
                400,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            return http.Response(
              '{"restaurant":{"id":"fixture-restaurant"}}',
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          final Object value = request.url.path.endsWith('tkt_action')
              ? (op == 'me' ? {'captain': false} : [])
              : {};
          return http.Response(
            jsonEncode(value),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      await session(client);
      final b = IdentityBackend(client);
      await b.refresh();
      expect(b.accountReady, false);
      expect(b.error, isNotNull);
      await b.refresh(lightweight: true);
      expect(calls, 2);
      expect(b.accountReady, true, reason: b.error);
      expect(b.restaurantOwner, true);
      b.dispose();
      await client.dispose();
    },
  );
}
