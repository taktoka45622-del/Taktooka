import 'dart:async';
import '../lib/core/map_tile_warmup.dart';

Future<void> main() async {
  var checks = 0;
  void check(bool value, String message) {
    if (!value) throw StateError(message);
    checks++;
  }

  final baghdad = nearbyMapTiles(33.34, 44.4, 14);
  check(baghdad.length == 9, 'only the nearby neighborhood is loaded');
  check(baghdad.map((t) => t.key).toSet().length == 9, 'no duplicate tiles');
  check(
    baghdad.first.x == 10212 && baghdad.first.y == 6580,
    'correct Baghdad center',
  );
  check(
    nearbyMapTiles(double.nan, 44.4, 14).isEmpty,
    'invalid coordinates rejected',
  );
  check(nearbyMapTiles(33, 181, 14).isEmpty, 'invalid longitude rejected');
  check(
    nearbyMapTiles(90, 180, 0).length == 1,
    'poles and zoom zero are bounded',
  );
  final plan = mapWarmupTiles(33.34, 44.4, 0, 14);
  check(plan.length == 36, 'prefetch is bounded to four small neighborhoods');
  check(
    plan.map((t) => t.z).toSet().containsAll({5, 8, 11, 14}),
    'zoom levels have reusable parents',
  );
  check(
    plan.first.z == 14,
    'opening detail has priority over zoomed-out detail',
  );
  check(
    mapWarmupTiles(33.34, 44.4, 14, 14).length == 9,
    'clamped zooms are not duplicated',
  );
  check(
    mapWarmupTiles(33.34, 44.4, 14, 12).isEmpty,
    'invalid provider bounds rejected',
  );
  var time = DateTime.utc(2026, 10, 26);
  final warmer = MapTileWarmup(now: () => time);
  var concurrent = 0, peak = 0, calls = 0;
  final gates = <Completer<void>>[];
  final loads = List.generate(
    9,
    (_) => () async {
      calls++;
      concurrent++;
      if (concurrent > peak) peak = concurrent;
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
      concurrent--;
    },
  );
  final first = warmer.run('baghdad', loads, active: () => true);
  await Future<void>.delayed(Duration.zero);
  check(calls == 2 && peak == 2, 'maximum two background requests');
  await warmer.run('duplicate', loads, active: () => true);
  check(calls == 2, 'a concurrent GPS update starts no duplicate batch');
  for (var i = 0; i < 5; i++) {
    for (final gate in gates.where((g) => !g.isCompleted).toList()) {
      gate.complete();
    }
    await Future<void>.delayed(Duration.zero);
  }
  await first;
  check(
    calls == 9 && peak == 2,
    'all nearby tiles finish within the concurrency limit',
  );
  await warmer.run('baghdad', loads, active: () => true);
  check(
    calls == 9,
    'stationary GPS updates do not redownload the neighborhood',
  );
  var retries = 0;
  Future<void> fail() async {
    retries++;
    throw StateError('offline');
  }

  await warmer.run('offline', [fail], active: () => true);
  await warmer.run('offline', [fail], active: () => true);
  check(retries == 1, 'failed requests are throttled');
  time = time.add(const Duration(seconds: 16));
  await warmer.run('offline', [fail], active: () => true);
  check(retries == 2, 'failed requests can recover');
  var active = true, afterPause = 0;
  await warmer.run('pause', [
    () async {
      afterPause++;
      active = false;
    },
    () async {
      afterPause++;
    },
    () async {
      afterPause++;
    },
  ], active: () => active);
  check(
    afterPause == 1,
    'background work stops when the app leaves foreground',
  );
  print('$checks map warmup checks passed');
}
