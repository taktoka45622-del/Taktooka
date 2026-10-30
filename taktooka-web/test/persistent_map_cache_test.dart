import 'map_test_support.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taktooka/services/persistent_map_client.dart';

void main() {
  setUpAll(mockMapCacheDirectories);
  final run = DateTime.now().microsecondsSinceEpoch;
  Uri uri(String suffix) => Uri.parse(
    'https://api.mapbox.com/v4/test/$run/$suffix.pbf?access_token=test',
  );
  test('map bytes survive a new client and are read without network', () async {
    var calls = 0;
    final url = uri('persist');
    final first = PersistentMapClient(
      network: MockClient((_) async {
        calls++;
        return http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'cache-control': 'max-age=3600'},
        );
      }),
    );
    expect((await first.get(url)).bodyBytes, [1, 2, 3]);
    first.close();
    final reopened = PersistentMapClient(
      network: MockClient((_) async {
        calls++;
        throw StateError('offline');
      }),
    );
    expect((await reopened.get(url)).bodyBytes, [1, 2, 3]);
    expect(calls, 1);
    reopened.close();
  });
  test('concurrent requests for a tile share one transfer', () async {
    var calls = 0;
    final client = PersistentMapClient(
      network: MockClient((_) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return http.Response.bytes([4, 5], 200);
      }),
    );
    await Future.wait(List.generate(8, (_) => client.get(uri('concurrent'))));
    expect(calls, 1);
    client.close();
  });
  test('expired map stays visible when a background refresh fails', () async {
    final url = uri('stale');
    final first = PersistentMapClient(
      network: MockClient(
        (_) async => http.Response.bytes(
          [7],
          200,
          headers: {'cache-control': 'max-age=0'},
        ),
      ),
    );
    await first.get(url);
    first.close();
    final retry = Completer<void>();
    final next = PersistentMapClient(
      network: MockClient((_) async {
        retry.complete();
        throw StateError('offline');
      }),
    );
    expect((await next.get(url)).bodyBytes, [7]);
    await retry.future;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    next.close();
  });
  test('error responses and no-store responses are never cached', () async {
    var calls = 0;
    final client = PersistentMapClient(
      network: MockClient((_) async {
        calls++;
        return http.Response.bytes(
          [9],
          200,
          headers: {'cache-control': 'no-store'},
        );
      }),
    );
    await client.get(uri('private'));
    await client.get(uri('private'));
    expect(calls, 2);
    client.close();
    var errors = 0;
    final failed = PersistentMapClient(
      network: MockClient((_) async {
        errors++;
        return http.Response('no', 404);
      }),
    );
    await failed.get(uri('missing'));
    await failed.get(uri('missing'));
    expect(errors, 2);
    failed.close();
  });
  test('routing and account endpoints bypass the map file cache', () async {
    var calls = 0;
    final client = PersistentMapClient(
      network: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    final url = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/driving/44,33;44.1,33.1',
    );
    await client.get(url);
    await client.get(url);
    expect(calls, 2);
    client.close();
  });
}
