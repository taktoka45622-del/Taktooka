import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/page_snapshot_cache.dart';
import 'package:taktooka/services/food_catalog_cache.dart';

class CacheBackend extends Backend {
  int epoch = 0;
  @override
  int get cacheEpoch => epoch;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      anonKey: 'test',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  test('page snapshots isolate nested edits and sessions', () {
    final b = CacheBackend();
    final original = <String, dynamic>{
      'rows': [
        {'name': 'first'},
      ],
    };
    PageSnapshotCache.save(b, 'page', original);
    (original['rows'] as List).clear();
    final first = PageSnapshotCache.read(b, 'page')!;
    (first['rows'] as List).clear();
    expect((PageSnapshotCache.read(b, 'page')!['rows'] as List).length, 1);
    b.epoch++;
    expect(PageSnapshotCache.read(b, 'page'), isNull);
    b.dispose();
  });
  test('catalog reuses data and coalesces simultaneous reads', () async {
    final b = CacheBackend(), pending = Completer<dynamic>();
    final cache = FoodCatalogCache.forBackend(b);
    var calls = 0;
    Future<dynamic> request() {
      calls++;
      return pending.future;
    }

    final a = cache.read('menu', {}, request);
    final c = cache.read('menu', {}, request);
    pending.complete([
      {'id': 'meal'},
    ]);
    await Future.wait([a, c]);
    final saved = await cache.read('menu', {}, request);
    expect(calls, 1);
    expect(saved[0]['id'], 'meal');
    b.dispose();
  });
  test('in-flight old session cannot populate a new session cache', () async {
    final b = CacheBackend(), pending = Completer<dynamic>();
    final cache = FoodCatalogCache.forBackend(b);
    final old = cache.read('menu', {}, () => pending.future);
    b.epoch++;
    pending.complete(['old']);
    await old;
    var calls = 0;
    final next = await cache.read('menu', {}, () async {
      calls++;
      return ['new'];
    });
    expect(calls, 1);
    expect(next, ['new']);
    b.dispose();
  });
  test(
    'invalidation prevents an old request restoring removed menu data',
    () async {
      final b = CacheBackend(), pending = Completer<dynamic>();
      final cache = FoodCatalogCache.forBackend(b);
      final old = cache.read('menu', {}, () => pending.future);
      cache.invalidate();
      pending.complete(['deleted']);
      await old;
      expect(await cache.read('menu', {}, () async => ['current']), [
        'current',
      ]);
      b.dispose();
    },
  );
}
