import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

enum NetworkStatus { unknown, online, offline }

final connectionMonitor = ConnectionMonitor();

class ConnectionMonitor extends ChangeNotifier {
  final Future<bool> Function() probe;
  final Stream<List<ConnectivityResult>>? changes;
  final Duration timeout;
  final Duration interval;
  NetworkStatus status = NetworkStatus.unknown;
  bool checking = false;
  bool _closed = false;
  int _revision = 0;
  Timer? _timer;
  Timer? _settle;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Future<void>? _running;

  ConnectionMonitor({
    Future<bool> Function()? probe,
    Stream<List<ConnectivityResult>>? changes,
    this.timeout = const Duration(seconds: 5),
    this.interval = const Duration(seconds: 15),
  }) : probe = probe ?? _probeNetwork,
       changes = changes ?? (probe == null ? Connectivity().onConnectivityChanged : null);

  static bool _connected(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);

  static Future<bool> _probeNetwork() async =>
      _connected(await Connectivity().checkConnectivity());

  void start() {
    if (_closed || _timer != null) return;
    _subscription = changes?.listen((results) {
      _revision++;
      _settle?.cancel();
      if (_connected(results)) {
        _setStatus(NetworkStatus.online);
      } else {
        _settle = Timer(const Duration(milliseconds: 800), () => unawaited(check()));
      }
    }, onError: (Object error) {});
    unawaited(check());
    _timer = Timer.periodic(interval, (_) => unawaited(check()));
  }

  void pause() {
    _revision++;
    _timer?.cancel();
    _timer = null;
    _settle?.cancel();
    _settle = null;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  void _setStatus(NetworkStatus next) {
    if (_closed || next == status) return;
    status = next;
    notifyListeners();
  }

  Future<void> check() {
    if (_closed) return Future<void>.value();
    return _running ??= _check().whenComplete(() => _running = null);
  }

  Future<void> _check() async {
    final revision = _revision;
    checking = true;
    notifyListeners();
    try {
      final connected = await probe().timeout(timeout);
      if (!_closed && revision == _revision) {
        status = connected ? NetworkStatus.online : NetworkStatus.offline;
      }
    } catch (_) {
    } finally {
      if (!_closed) {
        checking = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    pause();
    super.dispose();
  }
}
