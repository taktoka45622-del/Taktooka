import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:taktooka/core/map_config.dart';
import 'package:taktooka/core/local_fare.dart';
import 'package:taktooka/core/local_address.dart';
import 'package:taktooka/core/local_route_metrics.dart';

class DeviceBooking {
  final http.Client client;
  DeviceBooking({http.Client? client}) : client = client ?? http.Client();
  static DeviceBooking shared = DeviceBooking();
  Future<Map<String, dynamic>> _get(Uri url) async {
    final response = await client.get(url).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw StateError('ROUTE_UNAVAILABLE');
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Uri _directions(
    LatLng a,
    LatLng b, {
    bool snap = false,
    String bias = '-1',
  }) => Uri.https(
    'api.mapbox.com',
    '/directions/v5/mapbox/driving/'
        '${a.longitude},${a.latitude};${b.longitude},${b.latitude}',
    {
      'access_token': mapboxToken,
      'overview': snap ? 'false' : 'full',
      'geometries': 'geojson',
      'steps': 'true',
      'exclude': 'motorway,toll,ferry',
      'alternatives': snap ? 'false' : 'true',
      'radiuses': snap ? '150;150' : '75;75',
      'alley_bias': bias,
      'continue_straight': 'true',
    },
  );

  Future<Map<String, dynamic>> snap(LatLng p) async {
    final data = await _get(
      _directions(p, LatLng(p.latitude + .00001, p.longitude), snap: true),
    );
    final ways = data['waypoints'];
    if (data['code'] != 'Ok' ||
        ways is! List ||
        ways.isEmpty ||
        data['routes'] is! List ||
        (data['routes'] as List).isEmpty)
      throw StateError('NO_NEARBY_ROAD');
    final xy = ways.first['location'];
    if (xy is! List ||
        xy.length != 2 ||
        xy.any((n) => n is! num || !n.isFinite)) {
      throw StateError('NO_NEARBY_ROAD');
    }
    final q = LatLng((xy[1] as num).toDouble(), (xy[0] as num).toDouble());
    if (const Distance().as(LengthUnit.Meter, p, q) > 150)
      throw StateError('NO_NEARBY_ROAD');
    for (final route in data['routes'] as List) {
      if (_violation(route as Map)) throw StateError('NO_NEARBY_ROAD');
    }
    final name = ways.first['name'] is String
        ? ways.first['name'] as String
        : '';
    return {
      'point': [q.latitude, q.longitude],
      'name': name,
      'street': name,
    };
  }

  final _addressCache = <String, (DateTime, Map<String, dynamic>)>{};
  final _addressPending = <String, Future<Map<String, dynamic>>>{};
  final _addressUpdates = <String, Set<void Function(Map<String, dynamic>)>>{};
  final _addressLatest = <String, Map<String, dynamic>>{};
  Future<Map<String, dynamic>> address(
    LatLng p,
    String street, {
    void Function(Map<String, dynamic>)? onUpdate,
  }) async {
    final key =
        '${p.latitude.toStringAsFixed(5)}:${p.longitude.toStringAsFixed(5)}:$street';
    final cached = _addressCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(minutes: 10)) {
      onUpdate?.call(cached.$2);
      return cached.$2;
    }
    if (onUpdate != null) {
      (_addressUpdates[key] ??= {}).add(onUpdate);
      final latest = _addressLatest[key];
      if (latest != null) onUpdate(latest);
    }
    var request = _addressPending[key];
    if (request == null) {
      request =
          _loadAddress(p, street, (value) {
                _addressLatest[key] = value;
                for (final listener
                    in _addressUpdates[key]?.toList() ??
                        <void Function(Map<String, dynamic>)>[]) {
                  listener(value);
                }
              })
              .then((result) {
                if ((result['province'] as String? ?? '').isNotEmpty ||
                    (result['area'] as String? ?? '').isNotEmpty) {
                  if (_addressCache.length >= 80)
                    _addressCache.remove(_addressCache.keys.first);
                  _addressCache[key] = (DateTime.now(), result);
                }
                return result;
              })
              .whenComplete(() {
                _addressPending.remove(key);
                _addressUpdates.remove(key);
                _addressLatest.remove(key);
              });
      _addressPending[key] = request;
    }
    try {
      return await request;
    } finally {
      if (onUpdate != null) _addressUpdates[key]?.remove(onUpdate);
    }
  }

  Future<Map<String, dynamic>> _loadAddress(
    LatLng p,
    String street,
    void Function(Map<String, dynamic>)? onUpdate,
  ) async {
    Future<Map<String, dynamic>> get(Uri uri) async {
      try {
        return await _get(uri).timeout(const Duration(milliseconds: 2500));
      } catch (_) {
        return {};
      }
    }

    final tasks = [
      get(
        Uri.https('api.mapbox.com', '/search/geocode/v6/reverse', {
          'access_token': mapboxToken,
          'longitude': '${p.longitude}',
          'latitude': '${p.latitude}',
          'language': 'ar',
          'types': 'street,neighborhood,locality,place,district,region',
        }),
      ),
      get(
        Uri.https(
          'api.mapbox.com',
          '/v4/mapbox.mapbox-streets-v8/tilequery/${p.longitude},${p.latitude}.json',
          {
            'access_token': mapboxToken,
            'radius': '500',
            'limit': '50',
            'layers': 'poi_label,road',
          },
        ),
      ),
      get(
        Uri.https('photon.komoot.io', '/reverse', {
          'lat': '${p.latitude}',
          'lon': '${p.longitude}',
          'limit': '10',
          'radius': '1',
        }),
      ),
    ];

    final results = List<Map<String, dynamic>>.generate(3, (_) => {});
    Map<String, dynamic> best = {};
    var bestScore = -1;
    void publish() {
      final result = LocalAddress.resolve(results[0], street, results[1], [
        p.latitude,
        p.longitude,
      ], results[2]);
      final score =
          ((result['province'] as String).isEmpty ? 0 : 2) +
          ((result['area'] as String).isEmpty ? 0 : 4) +
          ((result['street'] as String).isEmpty ? 0 : 3) +
          ((result['landmark'] as String).isEmpty ? 0 : 1);
      if ((result['name'] as String).trim().isEmpty || score < bestScore)
        return;
      bestScore = score;
      best = result;
      onUpdate?.call(result);
    }

    publish();
    await Future.wait([
      for (var i = 0; i < tasks.length; i++)
        tasks[i].then((value) {
          results[i] = value;
          publish();
        }),
    ]);
    return best;
  }

  Future<Map<String, dynamic>> quote(
    LatLng a,
    LatLng b,
    DateTime at, {
    required bool roundTrip,
    required int waitMinutes,
    Map<String, dynamic>? pricing,
    Future<Map<String, dynamic>> Function(LatLng, LatLng)? routeLoader,
  }) async {
    final load = routeLoader ?? route;
    final routes = await Future.wait([load(a, b), if (roundTrip) load(b, a)]);
    final outgoing = routes[0], returning = roundTrip ? routes[1] : null;
    final distance = LocalRouteMetrics.meters(
      Map<String, dynamic>.from(outgoing['geometry'] as Map),
    );
    final returnDistance = returning == null
        ? 0.0
        : LocalRouteMetrics.meters(
            Map<String, dynamic>.from(returning['geometry'] as Map),
          );
    final now = at.toUtc();
    return {
      ...LocalFare(pricing ?? LocalFare.defaults).calculate(
        distance,
        now,
        roundTrip: roundTrip,
        waitMinutes: waitMinutes,
      ),
      'local_preview': true,
      'pickup': [a.latitude, a.longitude],
      'destination': [b.latitude, b.longitude],
      'geometry': outgoing['geometry'],
      'route_distance_m': distance,
      'distance_m': (distance + returnDistance).ceil(),
      'duration_s':
          (outgoing['duration'] as num).ceil() +
          (returning == null
              ? 0
              : (returning['duration'] as num).ceil() + waitMinutes * 60),
      'return_geometry': returning?['geometry'],
      'return_distance_m': roundTrip ? returnDistance : null,
      'return_duration_s': returning?['duration'],
      'created_at': now.toIso8601String(),
      'expires_at': now.add(const Duration(seconds: 60)).toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> route(LatLng a, LatLng b) async {
    final candidates = await Future.wait(
      ['0', '-1'].map((bias) async {
        try {
          final data = await _get(_directions(a, b, bias: bias));
          return data['code'] == 'Ok'
              ? (data['routes'] as List? ?? [])
              : <dynamic>[];
        } catch (_) {
          return <dynamic>[];
        }
      }),
    );
    return selectRoute(candidates.expand((x) => x).toList());
  }

  static bool _violation(Map route) {
    final notices = [...(route['notifications'] as List? ?? [])];
    for (final leg in route['legs'] as List? ?? []) {
      notices.addAll(leg['notifications'] as List? ?? []);
      for (final step in leg['steps'] as List? ?? []) {
        notices.addAll(step['notifications'] as List? ?? []);
      }
    }
    return notices.any((n) => n is Map && n['type'] == 'violation');
  }

  static bool _valid(dynamic value) {
    try {
      if (value is! Map ||
          value['distance'] is! num ||
          value['duration'] is! num)
        return false;
      final distance = value['distance'] as num,
          duration = value['duration'] as num;
      if (!distance.isFinite ||
          distance <= 0 ||
          distance > 2147483647 ||
          !duration.isFinite ||
          duration <= 0)
        return false;
      final geo = value['geometry'];
      if (geo is! Map ||
          geo['type'] != 'LineString' ||
          geo['coordinates'] is! List ||
          (geo['coordinates'] as List).length < 2)
        return false;
      for (final p in geo['coordinates'] as List) {
        if (p is! List ||
            p.length < 2 ||
            p.any((x) => x is! num || !x.isFinite) ||
            (p[0] as num).abs() > 180 ||
            (p[1] as num).abs() > 90)
          return false;
      }
      for (final leg in value['legs'] as List? ?? []) {
        for (final step in leg['steps'] as List? ?? []) {
          final m = step['distance'];
          if (m != null && (m is! num || !m.isFinite || m < 0)) return false;
          if (step['mode'] != null && step['mode'] != 'driving') return false;
          for (final i in step['intersections'] as List? ?? []) {
            if ([
              'path',
              'footway',
              'pedestrian',
              'steps',
              'cycleway',
            ].contains(i['mapbox_streets_v8']?['class']))
              return false;
          }
        }
      }
      return !_violation(value);
    } catch (_) {
      return false;
    }
  }

  static double _score(Map r) {
    const costs = {
      'primary': 0.0,
      'primary_link': .02,
      'secondary': .03,
      'secondary_link': .04,
      'tertiary': .07,
      'tertiary_link': .08,
      'street': .14,
      'street_limited': .22,
      'service': .35,
    };
    var roads = 0.0, turns = 0.0;
    for (final leg in r['legs'] as List? ?? []) {
      for (final step in leg['steps'] as List? ?? []) {
        final intersections = step['intersections'] as List? ?? [];
        final cost = intersections.isEmpty
            ? .14
            : intersections.fold<double>(
                    0,
                    (sum, i) =>
                        sum + (costs[i['mapbox_streets_v8']?['class']] ?? .14),
                  ) /
                  intersections.length;
        roads += ((step['distance'] as num?)?.toDouble() ?? 0) * cost;
        final maneuver = step['maneuver'] as Map? ?? {};
        final type = maneuver['type'],
            modifier = maneuver['modifier'] as String?;
        if (type == 'depart' || type == 'arrive') continue;
        if (modifier == 'uturn') {
          turns += 120;
        } else if (['roundabout', 'rotary', 'roundabout turn'].contains(type)) {
          turns += 30;
        } else if (['turn', 'fork', 'end of road', 'continue'].contains(type) &&
            modifier != null &&
            modifier != 'straight') {
          turns += modifier.contains('sharp')
              ? 40
              : modifier.contains('slight')
              ? 10
              : 20;
        }
      }
    }
    return (r['distance'] as num).toDouble() +
        .5 * (r['duration'] as num) +
        math.min(roads, (r['distance'] as num) * .25) +
        turns;
  }

  static Map<String, dynamic> selectRoute(List<dynamic> candidates) {
    final safe = candidates
        .where(_valid)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    if (safe.isEmpty) throw StateError('ROUTE_UNAVAILABLE');
    safe.sort((a, b) => (a['distance'] as num).compareTo(b['distance'] as num));
    final shortest = safe.first;
    final extra = math.min((shortest['distance'] as num) * .15, 400);
    final time = math.min(
      180,
      math.max(60, (shortest['duration'] as num) * .25),
    );
    final options = safe
        .where(
          (r) =>
              (r['distance'] as num) <= (shortest['distance'] as num) + extra &&
              (r['duration'] as num) <= (shortest['duration'] as num) + time,
        )
        .toList();
    options.sort((a, b) => _score(a).compareTo(_score(b)));
    return options.first;
  }
}
