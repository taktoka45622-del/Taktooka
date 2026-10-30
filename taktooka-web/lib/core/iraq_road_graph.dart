import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

class RoadSnap {
  final int edge;
  final double along, distance, lat, lng;
  final String name;
  const RoadSnap(
    this.edge,
    this.along,
    this.distance,
    this.lat,
    this.lng,
    this.name,
  );
  Map<String, dynamic> get json => {
    'point': [lat, lng],
    'name': name,
    'street': name,
    'address_ready': false,
  };
}

class _QueueItem {
  final int edge;
  final double cost, length, priority;
  const _QueueItem(this.edge, this.cost, this.length, this.priority);
}

class _Queue {
  final items = <_QueueItem>[];
  bool get isNotEmpty => items.isNotEmpty;
  void add(_QueueItem v) {
    items.add(v);
    var i = items.length - 1;
    while (i > 0) {
      final p = (i - 1) ~/ 2;
      if (items[p].priority <= v.priority) break;
      items[i] = items[p];
      i = p;
    }
    items[i] = v;
  }

  _QueueItem pop() {
    final first = items.first, last = items.removeLast();
    if (items.isEmpty) return first;
    var i = 0;
    while (true) {
      var child = i * 2 + 1;
      if (child >= items.length) break;
      if (child + 1 < items.length &&
          items[child + 1].priority < items[child].priority)
        child++;
      if (items[child].priority >= last.priority) break;
      items[i] = items[child];
      i = child;
    }
    items[i] = last;
    return first;
  }
}

class IraqRoadGraph {
  final ByteData data;
  late final int nodes, edges, geomCount, nodeOffset, edgeOffset, geomOffset;
  late final List<String> names;
  late final List<double> speeds;
  late final Map<String, dynamic> grid;
  final rules = <int, List<List<int>>>{};
  late final Uint32List from;
  IraqRoadGraph(Uint8List bytes) : data = ByteData.sublistView(bytes) {
    if (bytes.length < 32 ||
        ascii.decode(bytes.sublist(0, 8)) != 'TKTRD002' ||
        data.getUint32(8, Endian.little) != 2)
      throw StateError('INVALID_ROAD_PACKAGE');
    nodes = u(12);
    edges = u(16);
    geomCount = u(20);
    final metadataLength = u(24);
    nodeOffset = 32;
    edgeOffset = nodeOffset + nodes * 16;
    geomOffset = edgeOffset + edges * 24;
    final metaOffset = geomOffset + geomCount * 8;
    if (nodes == 0 || edges == 0 || metaOffset + metadataLength != bytes.length)
      throw StateError('INVALID_ROAD_PACKAGE');
    final meta = jsonDecode(utf8.decode(bytes.sublist(metaOffset))) as Map;
    names = List<String>.from(meta['names'] as List);
    speeds = (meta['speeds'] as List)
        .map((n) => (n as num).toDouble())
        .toList();
    grid = Map<String, dynamic>.from(meta['grid'] as Map);
    for (final row in meta['restrictions'] as List) {
      final r = List<int>.from(row as List);
      rules.putIfAbsent(r[0], () => []).add(r);
    }
    from = Uint32List(edges);
    for (var n = 0; n < nodes; n++) {
      final start = first(n), count = degree(n);
      if (start + count > edges) throw StateError('INVALID_ROAD_PACKAGE');
      for (var e = start; e < start + count; e++) from[e] = n;
    }
  }
  int u(int offset) => data.getUint32(offset, Endian.little);
  double latitude(int n) =>
      data.getInt32(nodeOffset + n * 16, Endian.little) * 1e-7;
  double longitude(int n) =>
      data.getInt32(nodeOffset + n * 16 + 4, Endian.little) * 1e-7;
  int first(int n) => u(nodeOffset + n * 16 + 8);
  int degree(int n) => u(nodeOffset + n * 16 + 12);
  int to(int e) => u(edgeOffset + e * 24);
  int way(int e) => u(edgeOffset + e * 24 + 4);
  int geo(int e) => u(edgeOffset + e * 24 + 8);
  int count(int e) => u(edgeOffset + e * 24 + 12);
  double length(int e) => u(edgeOffset + e * 24 + 16) / 1000;
  int flags(int e) => u(edgeOffset + e * 24 + 20);
  double _lat(int i) => data.getInt32(geomOffset + i * 8, Endian.little) * 1e-7;
  double _lng(int i) =>
      data.getInt32(geomOffset + i * 8 + 4, Endian.little) * 1e-7;
  static double meters(double a, double b, double c, double d) {
    final x = (c - a) * math.pi / 180, y = (d - b) * math.pi / 180;
    final h =
        math.pow(math.sin(x / 2), 2) +
        math.cos(a * math.pi / 180) *
            math.cos(c * math.pi / 180) *
            math.pow(math.sin(y / 2), 2);
    return 6371008.8 *
        2 *
        math.atan2(math.sqrt(h.clamp(0, 1)), math.sqrt((1 - h).clamp(0, 1)));
  }

  List<List<double>> points(int e) {
    final g = geo(e), size = count(e);
    final p = List.generate(size, (i) => [_lng(g + i), _lat(g + i)]);
    return flags(e) & 256 == 0 ? p : p.reversed.toList();
  }

  RoadSnap snap(double lat, double lng, {double radius = 150}) {
    if (!lat.isFinite ||
        !lng.isFinite ||
        lat < 29 ||
        lat > 38 ||
        lng < 38 ||
        lng > 49)
      throw StateError('OUTSIDE_ROAD_PACKAGE');
    final row = (lat * 100).floor(), col = (lng * 100).floor();
    final candidates = <int>{};
    for (var dy = -1; dy <= 1; dy++)
      for (var dx = -1; dx <= 1; dx++) {
        candidates.addAll(
          (grid['${(row + dy) * 100000 + col + dx}'] as List? ?? [])
              .cast<int>(),
        );
      }
    RoadSnap? best;
    var bestScore = double.infinity;
    final scale = 111320 * math.cos(lat * math.pi / 180);
    for (final e in candidates) {
      final g = geo(e), size = count(e);
      var traveled = 0.0;
      for (var i = 1; i < size; i++) {
        final aLat = _lat(g + i - 1),
            aLng = _lng(g + i - 1),
            bLat = _lat(g + i),
            bLng = _lng(g + i);
        final x = (bLng - aLng) * scale, y = (bLat - aLat) * 111320;
        final px = (lng - aLng) * scale, py = (lat - aLat) * 111320;
        final denominator = x * x + y * y;
        final t = denominator == 0
            ? 0.0
            : ((px * x + py * y) / denominator).clamp(0.0, 1.0);
        final qLat = aLat + (bLat - aLat) * t, qLng = aLng + (bLng - aLng) * t;
        final dist = meters(lat, lng, qLat, qLng),
            segment = meters(aLat, aLng, bLat, bLng);
        final score = dist + (flags(e) & 255) * 1.3;
        if (dist <= radius && score < bestScore) {
          final along = traveled + segment * t;
          best = RoadSnap(
            e,
            flags(e) & 256 == 0 ? along : math.max(0, length(e) - along),
            dist,
            qLat,
            qLng,
            names[way(e)],
          );
          bestScore = score;
        }
        traveled += segment;
      }
    }
    if (best == null) throw StateError('NO_NEARBY_ROAD');
    return best;
  }

  List<RoadSnap> directions(RoadSnap p) {
    final e = p.edge, origin = from[e], end = to(e);
    final result = [p];
    for (var r = first(end); r < first(end) + degree(end); r++) {
      if (to(r) == origin && geo(r) == geo(e))
        result.add(
          RoadSnap(r, length(r) - p.along, p.distance, p.lat, p.lng, p.name),
        );
    }
    return result;
  }

  bool allowed(int previous, int next) {
    final node = to(previous),
        a = way(previous),
        b = way(next),
        uturn = to(next) == from[previous];
    for (final r in rules[node] ?? const <List<int>>[]) {
      if (r[1] != a) continue;
      if (r[3] == 0 && r[2] == b) return false;
      if (r[3] == 1 && r[2] != b) return false;
      if (r[3] == 2 && r[2] == b && uturn) return false;
      if (r[3] == 3 && !(r[2] == b && uturn)) return false;
    }
    return true;
  }

  double _cost(int e, bool preferred) =>
      length(e) *
      (preferred ? 1.0 + (flags(e) & 255) * .018 + 1.8 / speeds[way(e)] : 1.0);
  Map<String, dynamic> route(
    double aLat,
    double aLng,
    double bLat,
    double bLng,
  ) {
    final start = snap(aLat, aLng), target = snap(bLat, bLng);
    final shortest = _search(start, target, false, double.infinity);
    final base = shortest['distance'] as double;
    try {
      return _search(start, target, true, base + math.min(base * .15, 400));
    } catch (_) {
      return shortest;
    }
  }

  Map<String, dynamic> _search(
    RoadSnap start,
    RoadSnap target,
    bool preferred,
    double limit,
  ) {
    final clock = Stopwatch()..start(),
        queue = _Queue(),
        costs = <int, double>{},
        parents = <int, int>{},
        starts = <int, RoadSnap>{};
    final endOptions = directions(target), startOptions = directions(start);
    var best = double.infinity, bestLength = 0.0, bestState = -1;
    RoadSnap? finish;
    List<List<double>>? direct;
    for (final a in startOptions)
      for (final b in endOptions) {
        if (a.edge == b.edge && b.along >= a.along) {
          final d = b.along - a.along,
              c = d * _cost(a.edge, preferred) / length(a.edge);
          if (c < best && d <= limit) {
            best = c;
            bestLength = d;
            finish = b;
            direct = _slice(a.edge, a.along, b.along);
          }
        }
      }
    for (final s in startOptions) {
      final remaining = math.max(0.0, length(s.edge) - s.along),
          cost = remaining * _cost(s.edge, preferred) / length(s.edge);
      if (costs[s.edge] != null && costs[s.edge]! <= cost) continue;
      costs[s.edge] = cost;
      parents[s.edge] = -1;
      starts[s.edge] = s;
      queue.add(
        _QueueItem(
          s.edge,
          cost,
          remaining,
          cost +
              meters(
                latitude(to(s.edge)),
                longitude(to(s.edge)),
                target.lat,
                target.lng,
              ),
        ),
      );
    }
    var expanded = 0;
    while (queue.isNotEmpty) {
      final item = queue.pop(), e = item.edge;
      if (item.cost != costs[e]) continue;
      if (item.priority >= best) break;
      if (++expanded > 400000 ||
          expanded % 1024 == 0 && clock.elapsedMilliseconds > 4500)
        throw StateError('LOCAL_ROUTE_TIMEOUT');
      final node = to(e);
      for (final end in endOptions) {
        if (from[end.edge] != node || !allowed(e, end.edge)) continue;
        final dist = item.length + end.along;
        final cost =
            item.cost +
            end.along * _cost(end.edge, preferred) / length(end.edge);
        if (dist <= limit && cost < best) {
          best = cost;
          bestLength = dist;
          bestState = e;
          finish = end;
          direct = null;
        }
      }
      for (var next = first(node); next < first(node) + degree(node); next++) {
        if (!allowed(e, next)) continue;
        final dist = item.length + length(next);
        if (dist > limit) continue;
        final turn = preferred && to(next) == from[e] ? 120.0 : 0.0;
        final c = item.cost + _cost(next, preferred) + turn;
        if (c >= best || costs[next] != null && costs[next]! <= c) continue;
        costs[next] = c;
        parents[next] = e;
        final h = meters(
          latitude(to(next)),
          longitude(to(next)),
          target.lat,
          target.lng,
        );
        queue.add(_QueueItem(next, c, dist, c + h));
      }
    }
    if (!best.isFinite || finish == null || bestLength <= .01)
      throw StateError('NO_LOCAL_ROUTE');
    final coordinates = <List<double>>[];
    var duration = 0.0;
    if (direct != null) {
      coordinates.addAll(direct);
      duration = bestLength / (speeds[way(finish.edge)] / 3.6);
    } else {
      final path = <int>[];
      var e = bestState;
      while (e >= 0) {
        path.add(e);
        e = parents[e] ?? -1;
      }
      final ordered = path.reversed.toList();
      for (var i = 0; i < ordered.length; i++) {
        final edge = ordered[i], begin = i == 0 ? starts[edge]!.along : 0.0;
        final p = _slice(edge, begin, length(edge));
        coordinates.addAll(coordinates.isEmpty ? p : p.skip(1));
        duration += (length(edge) - begin) / (speeds[way(edge)] / 3.6);
      }
      final last = _slice(finish.edge, 0, finish.along);
      coordinates.addAll(coordinates.isEmpty ? last : last.skip(1));
      duration += finish.along / (speeds[way(finish.edge)] / 3.6);
    }
    if (coordinates.length < 2) throw StateError('NO_LOCAL_ROUTE');
    return {
      'distance': bestLength,
      'duration': math.max(1, duration),
      'geometry': {'type': 'LineString', 'coordinates': coordinates},
      'route_provider': 'iraq-osm-offline-v2',
      'expanded': expanded,
    };
  }

  List<List<double>> _slice(int e, double a, double b) {
    final p = points(e), result = <List<double>>[];
    var offset = 0.0;
    for (var i = 1; i < p.length; i++) {
      final x = p[i - 1], y = p[i], d = meters(x[1], x[0], y[1], y[0]);
      if (offset + d >= a && offset <= b && d > 0) {
        final lo = ((a - offset) / d).clamp(0.0, 1.0),
            hi = ((b - offset) / d).clamp(0.0, 1.0);
        final left = [x[0] + (y[0] - x[0]) * lo, x[1] + (y[1] - x[1]) * lo];
        final right = [x[0] + (y[0] - x[0]) * hi, x[1] + (y[1] - x[1]) * hi];
        if (result.isEmpty) result.add(left);
        result.add(right);
      }
      offset += d;
      if (offset > b) break;
    }
    return result;
  }
}
