import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:taktooka/core/iraq_road_graph.dart';

class OfflineRoads {
  Future<Map<String, dynamic>> Function(double, double)? snapOverride;
  Future<Map<String, dynamic>> Function(double, double, double, double)?
  routeOverride;

  static final shared = OfflineRoads();
  bool get isReady => snapOverride != null || _worker != null;
  Future<void>? _ready;
  SendPort? _worker;
  ReceivePort? _receive;
  Isolate? _isolate;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  int _sequence = 0;
  Future<void> warmUp() => snapOverride != null && routeOverride != null
      ? Future.value()
      : _ready ??= _start().catchError((Object e) {
          _ready = null;
          throw e;
        });
  Future<void> _start() async {
    final manifest =
        jsonDecode(await rootBundle.loadString('assets/routing/manifest.json'))
            as Map;
    final base = await getApplicationSupportDirectory();
    final folder = Directory('${base.path}/iraq-roads');
    await folder.create(recursive: true);
    final file = File('${folder.path}/${manifest['sha256']}.bin.gz');
    if (!await file.exists()) {
      final asset = await rootBundle.load('assets/routing/iraq-roads-v2.bin.gz');
      final temporary = File('${file.path}.part');
      await temporary.writeAsBytes(asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes));
      await temporary.rename(file.path);
    }
    final ready = Completer<void>();
    _receive = ReceivePort();
    _receive!.listen((dynamic message) {
      if (message is SendPort) {
        _worker = message;
        if (!ready.isCompleted) ready.complete();
        return;
      }
      if (message is Map && message['init_error'] != null) {
        if (!ready.isCompleted)
          ready.completeError(StateError('${message['init_error']}'));
        return;
      }
      if (message is! Map) return;
      final completer = _pending.remove(message['id']);
      if (completer == null) return;
      if (message['error'] != null)
        completer.completeError(StateError('${message['error']}'));
      else
        completer.complete(Map<String, dynamic>.from(message['result'] as Map));
    });
    _isolate = await Isolate.spawn(_entry, [
      _receive!.sendPort,
      file.path,
      manifest['sha256'],
    ]);
    try {
      await ready.future.timeout(const Duration(seconds: 45));
    } catch (_) {
      _isolate?.kill(priority: Isolate.immediate);
      _receive?.close();
      _worker = null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _request(String op, List<double> points) async {
    await warmUp();
    final id = ++_sequence, completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _worker!.send({'id': id, 'op': op, 'points': points});
    try {
      return await completer.future.timeout(const Duration(seconds: 12));
    } finally {
      _pending.remove(id);
    }
  }

  Future<Map<String, dynamic>> snap(double lat, double lng) =>
      snapOverride != null
      ? snapOverride!(lat, lng)
      : _request('snap', [lat, lng]);
  Future<Map<String, dynamic>> route(double a, double b, double c, double d) =>
      routeOverride != null
      ? routeOverride!(a, b, c, d)
      : _request('route', [a, b, c, d]);
  static void _entry(List<dynamic> args) async {
    final reply = args[0] as SendPort;
    try {
      final file = File(args[1] as String);
      final compressed = await file.readAsBytes();
      if (sha256.convert(compressed).toString() != args[2]) {
        await file.delete();
        throw StateError('INVALID_ROAD_PACKAGE');
      }
      final decoded = gzip.decode(compressed);
      final graph = IraqRoadGraph(
        decoded is Uint8List ? decoded : Uint8List.fromList(decoded),
      );
      final receive = ReceivePort();
      reply.send(receive.sendPort);
      receive.listen((dynamic value) {
        final message = value as Map, id = message['id'];
        try {
          final p = List<double>.from(message['points'] as List);
          final result = message['op'] == 'snap'
              ? graph.snap(p[0], p[1]).json
              : graph.route(p[0], p[1], p[2], p[3]);
          reply.send({'id': id, 'result': result});
        } catch (e) {
          reply.send({'id': id, 'error': e.toString()});
        }
      });
    } catch (e) {
      reply.send({'init_error': e.toString()});
    }
  }
}
