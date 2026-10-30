import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

class RouteProgress {
  final List<LatLng> points;
  final double distanceToRoute;
  const RouteProgress(this.points, this.distanceToRoute);

  static RouteProgress remaining(List<LatLng> path, LatLng position) {
    if (path.length < 2) return RouteProgress(path, double.infinity);
    var best = double.infinity;
    var segment = 0;
    var projected = path.first;
    final scale = math.cos(position.latitude * math.pi / 180);
    for (var i = 0; i < path.length - 1; i++) {
      final a = path[i], b = path[i + 1];
      final ax = (a.longitude - position.longitude) * scale;
      final ay = a.latitude - position.latitude;
      final dx = (b.longitude - a.longitude) * scale;
      final dy = b.latitude - a.latitude;
      final length = dx * dx + dy * dy;
      final t = length == 0
          ? 0.0
          : (-(ax * dx + ay * dy) / length).clamp(0.0, 1.0);
      final distance =
          math.sqrt(math.pow(ax + dx * t, 2) + math.pow(ay + dy * t, 2)) *
          111320;
      if (distance < best) {
        best = distance;
        segment = i;
        projected = LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        );
      }
    }
    final rest = [projected, ...path.skip(segment + 1)];
    if (const Distance().as(LengthUnit.Meter, position, path.last) <= 12) {
      return RouteProgress([path.last], best);
    }
    return RouteProgress(rest, best);
  }

  static List<LatLng> decode(dynamic geometry) {
    final raw = geometry is Map ? geometry['coordinates'] : null;
    if (raw is! List || raw.length > 8000) return [];
    final points = <LatLng>[];
    for (final xy in raw) {
      if (xy is! List ||
          xy.length != 2 ||
          xy.any((v) => v is! num || !v.isFinite))
        return [];
      final lat = (xy[1] as num).toDouble(), lng = (xy[0] as num).toDouble();
      if (lat.abs() > 90 || lng.abs() > 180) return [];
      points.add(LatLng(lat, lng));
    }
    return points;
  }
}

class TripNavigation {
  final Future<Map<String, dynamic>> Function(LatLng, LatLng) load;
  final Future<void> Function(Map<String, dynamic>) publish;
  TripNavigation({required this.load, required this.publish});
  String? _key;
  List<LatLng> _path = [];
  DateTime _requested = DateTime(2000);
  bool _busy = false;

  static String phase(Map ride) =>
      '${ride['status']}:${ride['round_trip_stage'] ?? ''}:${ride['destination_revision'] ?? 0}';
  static LatLng? target(Map ride) {
    final state = ride['status'];
    final raw =
        state == 'accepted' ||
            state == 'arrived' ||
            (state == 'in_progress' && ride['round_trip_stage'] == 'returning')
        ? ride['pickup']
        : state == 'in_progress'
        ? ride['destination']
        : null;
    if (raw is! List ||
        raw.length != 2 ||
        raw.any((v) => v is! num || !v.isFinite))
      return null;
    return LatLng((raw[0] as num).toDouble(), (raw[1] as num).toDouble());
  }

  static Map? shared(Map? ride) {
    final value = ride?['navigation'];
    if (value is! Map ||
        ride == null ||
        value['phase'] != phase(ride) ||
        value['ride_id'] != ride['id'])
      return null;
    return value;
  }

  Future<void> update(
    Map<String, dynamic> ride,
    LatLng from,
    DateTime gpsAt, {
    required bool Function() isCurrent,
  }) async {
    final to = target(ride);
    if (to == null || _busy) return;
    final key = '${ride['id']}:${phase(ride)}:$to';
    final now = DateTime.now();
    if (_key != key) {
      _key = key;
      _path = RouteProgress.decode(shared(ride)?['geometry']);
      _requested = DateTime(2000);
    }
    final progress = RouteProgress.remaining(_path, from);
    if (_path.isNotEmpty && progress.distanceToRoute <= 40) return;
    if (now.difference(_requested) < const Duration(seconds: 5)) return;
    _requested = now;
    _busy = true;
    try {
      final route = await load(from, to);
      final path = RouteProgress.decode(route['geometry']);
      if (!isCurrent() ||
          _key != key ||
          path.length < 2 ||
          const Distance().as(LengthUnit.Meter, path.first, from) > 150 ||
          const Distance().as(LengthUnit.Meter, path.last, to) > 150)
        return;
      final data = <String, dynamic>{
        'ride_id': ride['id'],
        'phase': phase(ride),
        'geometry': route['geometry'],
        'gps_at': gpsAt.toUtc().toIso8601String(),
      };
      await publish(data);
      if (isCurrent() && _key == key) _path = path;
    } catch (_) {
    } finally {
      _busy = false;
    }
  }
}
