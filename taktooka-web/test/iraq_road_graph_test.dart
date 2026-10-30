import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:taktooka/core/iraq_road_graph.dart';
import 'package:taktooka/core/local_route_metrics.dart';

IraqRoadGraph graph(
  List<List<double>> nodes,
  List<List<int>> ways, {
  List<List<int>> restrictions = const [],
}) {
  final adjacency = List.generate(nodes.length, (_) => <List<int>>[]),
      geometry = <List<double>>[];
  for (var w = 0; w < ways.length; w++) {
    final spec = ways[w],
        a = spec[0],
        b = spec[1],
        oneway = spec.length > 2 ? spec[2] : 0,
        g = geometry.length;
    geometry.addAll([nodes[a], nodes[b]]);
    final m =
        (IraqRoadGraph.meters(
                  nodes[a][0],
                  nodes[a][1],
                  nodes[b][0],
                  nodes[b][1],
                ) *
                1000)
            .round();
    if (oneway >= 0) adjacency[a].add([b, w, g, 2, m, 1]);
    if (oneway <= 0) adjacency[b].add([a, w, g, 2, m, 257]);
  }
  final flat = <List<int>>[], grid = <String, Set<int>>{};
  final n = ByteData(nodes.length * 16);
  for (var i = 0; i < nodes.length; i++) {
    n.setInt32(i * 16, (nodes[i][0] * 1e7).round(), Endian.little);
    n.setInt32(i * 16 + 4, (nodes[i][1] * 1e7).round(), Endian.little);
    n.setUint32(i * 16 + 8, flat.length, Endian.little);
    n.setUint32(i * 16 + 12, adjacency[i].length, Endian.little);
    flat.addAll(adjacency[i]);
  }
  final e = ByteData(flat.length * 24), g = ByteData(geometry.length * 8);
  for (var i = 0; i < flat.length; i++) {
    for (var j = 0; j < 6; j++)
      e.setUint32(i * 24 + j * 4, flat[i][j], Endian.little);
    final p = geometry[flat[i][2]];
    final key = '${(p[0] * 100).floor() * 100000 + (p[1] * 100).floor()}';
    grid.putIfAbsent(key, () => {}).add(i);
  }
  for (var i = 0; i < geometry.length; i++) {
    g.setInt32(i * 8, (geometry[i][0] * 1e7).round(), Endian.little);
    g.setInt32(i * 8 + 4, (geometry[i][1] * 1e7).round(), Endian.little);
  }
  final metadata = utf8.encode(
    jsonEncode({
      'names': List.generate(ways.length, (i) => 'Road $i'),
      'speeds': List.filled(ways.length, 25),
      'restrictions': restrictions,
      'grid': grid.map((k, v) => MapEntry(k, v.toList())),
    }),
  );
  final header = ByteData(32);
  header.buffer.asUint8List().setRange(0, 8, ascii.encode('TKTRD002'));
  for (final x in [
    [8, 2],
    [12, nodes.length],
    [16, flat.length],
    [20, geometry.length],
    [24, metadata.length],
    [28, restrictions.length],
  ])
    header.setUint32(x[0], x[1], Endian.little);
  final bytes = BytesBuilder(copy: false)
    ..add(header.buffer.asUint8List())
    ..add(n.buffer.asUint8List())
    ..add(e.buffer.asUint8List())
    ..add(g.buffer.asUint8List())
    ..add(metadata);
  return IraqRoadGraph(bytes.takeBytes());
}

void main() {
  const a = [33.0, 44.0],
      b = [33.0, 44.01],
      c = [33.01, 44.01],
      d = [33.01, 44.0];
  test('snap projects on the road rather than jumping to an intersection', () {
    final g = graph(
          [a, b],
          [
            [0, 1],
          ],
        ),
        p = g.snap(33.0001, 44.005);
    expect(p.lat, closeTo(33, 1e-7));
    expect(p.lng, closeTo(44.005, 1e-7));
    expect(p.distance, closeTo(11.12, .2));
  });
  test('same segment route follows only its legal direction', () {
    final g = graph(
      [a, b],
      [
        [0, 1, 1],
      ],
    );
    final r = g.route(33, 44.002, 33, 44.008);
    expect(
      r['distance'],
      closeTo(IraqRoadGraph.meters(33, 44.002, 33, 44.008), .1),
    );
    expect(() => g.route(33, 44.008, 33, 44.002), throwsStateError);
  });
  test('reverse of a one-way road takes a legal loop', () {
    final g = graph(
      [a, b, c, d],
      [
        [0, 1, 1],
        [1, 2, 1],
        [2, 3, 1],
        [3, 0, 1],
      ],
    );
    final r = g.route(33, 44.009, 33, 44.001);
    expect((r['distance'] as double) > 2500, true);
    final coords = (r['geometry'] as Map)['coordinates'] as List;
    expect(coords.any((p) => (p[1] as num) > 33.009), true);
  });
  test('no-turn restriction is respected at the junction', () {
    final g = graph(
      [a, b, c, d],
      [
        [0, 1],
        [1, 2],
        [0, 3],
        [3, 2],
      ],
      restrictions: [
        [1, 0, 1, 0],
      ],
    );
    final r = g.route(33, 44.001, 33.009, 44.01);
    final coords = (r['geometry'] as Map)['coordinates'] as List;
    expect(
      coords.any((p) => (p[0] as num) < 44.0001 && (p[1] as num) > 33.009),
      true,
    );
  });
  test('only-turn restriction excludes another outgoing way', () {
    final g = graph(
      [a, b, c, d],
      [
        [0, 1, 1],
        [1, 2, 1],
        [1, 3, 1],
      ],
      restrictions: [
        [1, 0, 1, 1],
      ],
    );
    expect(() => g.route(33, 44.001, 33.009, 44.001), throwsStateError);
  });
  test('disconnected roads cannot produce a straight-line route', () {
    final g = graph(
      [a, b, c, d],
      [
        [0, 1],
        [2, 3],
      ],
    );
    expect(() => g.route(33, 44.005, 33.01, 44.005), throwsStateError);
  });
  test('route distance agrees with its full road geometry', () {
    final g = graph(
      [a, b, c],
      [
        [0, 1],
        [1, 2],
      ],
    );
    final r = g.route(33, 44.002, 33.008, 44.01);
    final measured = LocalRouteMetrics.meters(
      Map<String, dynamic>.from(r['geometry'] as Map),
    );
    expect(measured, closeTo(r['distance'] as double, .02));
  });
  test('outside coverage and far-away pins are rejected', () {
    final g = graph(
      [a, b],
      [
        [0, 1],
      ],
    );
    expect(() => g.snap(0, 0), throwsStateError);
    expect(() => g.snap(33.1, 44.1), throwsStateError);
  });
  test('invalid road packages cannot be loaded', () {
    expect(() => IraqRoadGraph(Uint8List(32)), throwsStateError);
  });
}
