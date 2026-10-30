import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:taktooka/services/connection_monitor.dart';

void main() {
  test('connection failure becomes offline and a retry recovers', () async {
    var reachable = false;
    final monitor = ConnectionMonitor(probe: () async => reachable);
    addTearDown(monitor.dispose);
    await monitor.check();
    expect(monitor.status, NetworkStatus.offline);
    expect(monitor.checking, isFalse);
    reachable = true;
    await monitor.check();
    expect(monitor.status, NetworkStatus.online);
  });

  test(
    'a hanging request has a deadline and cannot leave loading stuck',
    () async {
      final monitor = ConnectionMonitor(
        probe: () => Completer<bool>().future,
        timeout: const Duration(milliseconds: 20),
      );
      addTearDown(monitor.dispose);
      await monitor.check();
      expect(monitor.status, NetworkStatus.unknown);
      expect(monitor.checking, isFalse);
    },
  );

  test('platform check errors preserve the last network state', () async {
    var fail = false;
    final monitor = ConnectionMonitor(probe: () async {
      if (fail) throw StateError('platform unavailable');
      return true;
    });
    addTearDown(monitor.dispose);
    await monitor.check();
    fail = true;
    await monitor.check();
    expect(monitor.status, NetworkStatus.online);
    expect(monitor.checking, isFalse);
  });

  testWidgets('network events recover without waiting for polling', (tester) async {
    final changes = StreamController<List<ConnectivityResult>>();
    var connected = false;
    final monitor = ConnectionMonitor(
      probe: () async => connected,
      changes: changes.stream,
    );
    monitor.start();
    await tester.pump();
    expect(monitor.status, NetworkStatus.offline);
    connected = true;
    changes.add([ConnectivityResult.wifi]);
    await tester.pump();
    expect(monitor.status, NetworkStatus.online);
    changes.add([ConnectivityResult.none]);
    await tester.pump(const Duration(milliseconds: 300));
    changes.add([ConnectivityResult.mobile]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(monitor.status, NetworkStatus.online);
    connected = false;
    changes.add([ConnectivityResult.none]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(monitor.status, NetworkStatus.offline);
    monitor.dispose();
    await changes.close();
  });

  test('repeated retries share one request', () async {
    var calls = 0;
    final result = Completer<bool>();
    final monitor = ConnectionMonitor(
      probe: () {
        calls++;
        return result.future;
      },
    );
    addTearDown(monitor.dispose);
    final first = monitor.check();
    final second = monitor.check();
    expect(identical(first, second), isTrue);
    result.complete(true);
    await first;
    expect(calls, 1);
  });

  test('disposing during a request prevents late notifications', () async {
    final result = Completer<bool>();
    final monitor = ConnectionMonitor(probe: () => result.future);
    var updates = 0;
    monitor.addListener(() => updates++);
    final pending = monitor.check();
    monitor.dispose();
    result.complete(false);
    await pending;
    expect(updates, 1);
  });
}
