import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:taktooka/core/local_place_index.dart';

class IraqPlaces {
  static final shared = IraqPlaces();
  Future<void>? _warming;
  SendPort? _worker;
  Future<void> warmUp() => _warming ??= _start().catchError((Object e) {
    _warming = null;
    throw e;
  });
  Future<void> _start() async {
    final bytes = await rootBundle
        .load('assets/search/iraq-places-v1.json.gz')
        .timeout(const Duration(seconds: 12));
    final receive = ReceivePort();
    final isolate = await Isolate.spawn(_run, [
      receive.sendPort,
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    ], onError: receive.sendPort);
    try {
      final result = await receive.first.timeout(const Duration(seconds: 30));
      if (result is! SendPort) throw StateError('PLACE_INDEX_UNAVAILABLE');
      _worker = result;
    } catch (_) {
      isolate.kill(priority: Isolate.immediate);
      rethrow;
    } finally {
      receive.close();
    }
  }

  Future<List<Map<String, dynamic>>> search(
    String query,
    LatLng origin, {
    bool areasOnly = false,
  }) async {
    await warmUp();
    final reply = ReceivePort();
    _worker!.send([
      reply.sendPort,
      query,
      origin.latitude,
      origin.longitude,
      areasOnly,
    ]);
    try {
      final result = await reply.first.timeout(const Duration(seconds: 3));
      if (result is! List) return [];
      return result.map((r) => Map<String, dynamic>.from(r as Map)).toList();
    } finally {
      reply.close();
    }
  }

  static void _run(List<dynamic> args) {
    final initial = args[0] as SendPort;
    try {
      final data =
          jsonDecode(utf8.decode(gzip.decode(args[1] as List<int>))) as Map;
      final index = LocalPlaceIndex(data['rows'] as List);
      final input = ReceivePort();
      initial.send(input.sendPort);
      input.listen((dynamic message) {
        final m = message as List;
        try {
          (m[0] as SendPort).send(
            index.search(
              m[1] as String,
              LatLng(m[2] as double, m[3] as double),
              areasOnly: m[4] as bool,
            ),
          );
        } catch (_) {
          (m[0] as SendPort).send([]);
        }
      });
    } catch (_) {
      initial.send(null);
    }
  }
}
